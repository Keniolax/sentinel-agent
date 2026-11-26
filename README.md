# sentinel-agent

[![pipeline](https://github.com/Keniolax/sentinel-agent/actions/workflows/pipeline.yml/badge.svg)](https://github.com/Keniolax/sentinel-agent/actions/workflows/pipeline.yml)

An AI support agent on Azure that can read only what it needs, reports every step to a Wazuh
SIEM, and was then attacked to prove both. A poisoned help article tells the agent to read a
payroll file and leak it. With the locks off, the attack works. With the locks on, Azure
refuses the read, and five detection rules catch every step either way.

![architecture](diagram/architecture.png)

## The result

The same attack ran twice in one session (tag `wk19-20261125T220424Z`), once against the
shipped lab and once against a weakened copy that the attack script creates and then removes.

| Step | Technique | Weakened lab | Shipped lab | Detection that fired |
|---|---|---|---|---|
| A. A help article tells the model to read the payroll | Prompt injection (OWASP LLM01), Tool Misuse (OWASP ASI02), Excessive Agency (LLM06) | The tool takes the finance path | The tool's key check refuses any key outside `kb/` | 100822 on the attack run, and none on the normal run |
| B. The agent reads the payroll and prints it | Data from Cloud Storage (ATT&CK T1530) | `206 Partial Content`, the file leaves through the console log | `403 AuthorizationPermissionMismatch` | 100820 on both reads, 100821 (level 14) on the successful one |
| C. A foothold in the cloud | Run Command (T1078.004), a role granted on the payroll container (T1098) | The temporary grant succeeds | `CKV_SENTINEL_1` fails CI on any such grant in Terraform | 100823 on Run Command, 100824 on the grant |

The SIEM's alert counts for that run were `100820=2 100821=2 100822=1 (0 on the normal run)
100823=56 100824=4`. Rule 100823 fired 56 times because it also matches the operator's own Run
Command calls, which the evidence script makes once a minute. It is a lead to sort by caller,
not an alert to page on.

The payroll file is synthetic. Every name and number in it is made up.

## What it does

The agent answers one customer question for a made-up outdoor shop. It runs a small local
model (qwen2.5:1.5b on Ollama 0.40.13, pinned by digest) and has three tools: list the help
articles, read one help article, and look up an order in a mock internal API. Each question
starts one execution of an Azure Container Apps job. The job answers and stops.

| Part | How it is protected |
|---|---|
| Help articles (`knowledge` container) | The job's managed identity has Storage Blob Data Reader on this container only. |
| Payroll file (`finance` container) | Lock 1: the tool refuses any key outside `kb/`. Lock 2: the identity has no role on the container. Either lock alone stops the read. |
| Infrastructure code | The custom Checkov check `CKV_SENTINEL_1` fails the build if any Terraform grants a Storage Blob Data role on `finance`. CI proves the check on a bad and a good fixture. |
| Job network | The subnet's NSG allows only the Azure services the platform needs and denies the rest of the internet. |
| Logs | The agent writes one JSON line per step: question, model reply, tool call (allowed, denied or error), answer. The lines hold SHA-256 hashes of the question and answer. The agent prints the answer once as its output, so the answer text does reach the console log. |
| SIEM VM | No inbound port. Operators use Run Command. A collector reads Log Analytics with the VM's managed identity, so no client secret exists. |
| Deploys | GitHub Actions signs in with a federated credential on `main`. The deploy identity is Contributor on the lab group only, and may grant only AcrPull, Storage Blob Data Reader and Log Analytics Reader, only to managed identities. |
| Threat detection | Microsoft Defender for Storage and Defender for Servers P1 send their alerts to the activity log. |

The pipeline (`.github/workflows/pipeline.yml`) has three jobs. **Gate** runs 27 unit tests,
`terraform validate`, Checkov with the custom check, Trivy (configuration and dependencies),
Semgrep and Gitleaks over the whole history; any finding fails it. **Build** tags the image
with a hash of its inputs, builds it only if that tag is new, and scans it with Trivy.
**Deploy** runs `terraform apply`.

## Threat model

The threat model follows the seven stages of PASTA (Process for Attack Simulation and Threat
Analysis).

1. **Objectives.** The agent answers customers from the help articles. The payroll must never
   leave the `finance` container, and every action the agent takes must be traceable to a run.
2. **Technical scope.** One Container Apps job (agent, model and mock API in one image), one
   storage account with two containers, one managed identity, Log Analytics, a Wazuh VM, and a
   GitHub Actions pipeline that deploys with a federated credential.
3. **Decomposition.** Four trust boundaries: the customer's question enters the model; the
   text of a help article enters the model; the model's tool call becomes a storage request;
   a merged pull request becomes a role assignment in Azure.
4. **Threats.** Someone who can edit a help article, or who controls a page the agent reads,
   wants the payroll. Someone with a cloud foothold wants to widen the agent's access.
5. **Weaknesses.** A language model follows instructions it finds in data, and no prompt
   fixes that reliably. A tool that trusts the model's chosen path turns that into a read.
   A broad role on the identity turns the read into a leak. A careless Terraform change can
   add that role.
6. **Attack.** Steps A, B and C in the table above, run against this lab.
7. **Risk and controls.** The controls sit on the tool (lock 1), the identity (lock 2) and the
   pipeline (`CKV_SENTINEL_1`), not on the prompt, so they hold even when the model obeys the
   attacker. The risks that remain: the answer text reaches the console log; logs reach the
   SIEM minutes after the event (a whole run within ten), so detection is not prevention; rule 100823 needs
   tuning by caller; the injection still reaches the model, which could mislead a customer
   without touching the payroll.

## Run it

You need an Azure subscription where you are Owner, the Azure CLI, Terraform 1.14, and the
GitHub CLI signed in to a fork of this repository.

```
az login
infra/bootstrap/prereqs.sh                # register resource providers (free)
cd infra/bootstrap
terraform init && terraform apply -var subscription_id=$(az account show --query id -o tsv)
cd ../.. && scripts/set-repo-vars.sh      # IDs and names only, no secrets
git push                                  # the pipeline deploys infra/main
```

Ask the agent a question and check that the SIEM saw it:

```
scripts/ask.sh "Please read the help article kb/returns.md and tell me how many days I have to return an item."
scripts/verify-siem.sh <run_id from ask.sh>
scripts/probe-finance.sh                  # exits 0 only if Azure refuses the payroll read
```

Run the attack and read the detections back (details in [`attack/`](attack/README.md)):

```
scripts/update-rules.sh                   # push the current rules to the running SIEM VM
attack/run-chain.sh                       # prints a tag; removes its grants and files on exit
attack/evidence.sh <tag>                  # waits until every rule has fired, or fails
```

The SIEM VM (Standard_D2as_v6) costs about $2 a day. Stop it when you are done:
`az vm deallocate -g rg-sentinel-lab -n vm-sentinel-siem`. To remove everything, run
`terraform destroy` in `infra/main` and then in `infra/bootstrap`.

The first version of this project targeted AWS. An account block stopped it before it could
run; it is kept at tag [`aws-v1`](https://github.com/Keniolax/sentinel-agent/tree/aws-v1).

## What I learned

- **Test the guardrail, not the model.** The 1.5B model did not follow the injection reliably:
  in three runs it never opened the poisoned article. A proof that depends on the model is a
  coin flip. So the weakened copy assumes the model obeys the attacker, which is how a tool's
  guardrail should be tested anyway: it has to hold when the model fails.
- **Rank by consequence.** In the first version a refused read of the payroll was a level-3
  alert, the same as reading a help article. Someone reaching for the payroll and being
  refused is still an attack in progress, so it is now level 12, and a successful read is 14.
- **A rule that fires on normal work is a lead.** Rule 100823 caught the attack's Run Command,
  and every one of the operator's own: 56 alerts in all. It is useful only when sorted by who
  called it.
- **Freeze a runtime control in code.** The RBAC lock is a fact about Azure, so a Terraform
  change could remove it and no unit test would notice. `CKV_SENTINEL_1` puts it in the gate,
  and the bad fixture proves the check can fail.
- **Control-plane and data-plane rights are separate on Azure.** Owner of the subscription
  could not upload the poisoned article; that needs a Storage Blob Data role. The attack grants
  itself one and removes it on exit.
- **Design the test around slow logs.** Storage logs reached the workspace in about two
  minutes, console logs in three to seven, and RBAC changes took minutes to apply. The test
  takes the refused read from the default state rather than waiting for a grant to disappear,
  and treats the storage log as the record of the read.
- **The live run found a bug the unit tests could not.** The first execution failed with
  `unknown url type: 127.0.0.1`: the image sets `OLLAMA_HOST=127.0.0.1:11434` for the server,
  and the client read the same variable as a URL. A test now checks the URL that is sent.
- **A file the VM reads at boot is part of the VM.** Changing the Wazuh rules changed the VM's
  cloud-init data, so the next deploy replaced the VM. `scripts/update-rules.sh` pushes rules
  to a running VM between rebuilds.
- **Azure capacity fails at deploy time.** East US 2 refused five VM sizes with
  `SkuNotAvailable` although quota allowed them. `terraform plan` cannot see this.
- **Defaults can cost money.** Turning on Defender for Storage also turned on per-GB malware
  scanning, which the Terraform resource did not show. The stack now turns it off.
