# Week 19: attack the Sentinel Agent, then catch it

This folder attacks the capstone lab and shows the SIEM catching or blocking every step. It
runs only against the user's own lab (`rg-sentinel-lab`). Nothing is left behind: the poisoned
article and the temporary role grant are removed before `run-chain.sh` exits.

The shipped lab already stops the attack, so there is nothing to catch. To show "attack lands,
then is caught", each of the two week-18 locks is made removable by a toggle the attack sets
and then undoes, never a weak default committed to the repo:

- **Lock 1, the code key check.** The real agent refuses any blob key outside `kb/`. The weak
  twin is `weak_agent.py`, a copy of the loop whose tool trusts whatever path the model asks
  for. It runs as a one-off job execution, the same way `probe-finance.sh` injects its command.
- **Lock 2, the RBAC role.** The agent's identity has no role on the `finance` container. The
  attack grants it Storage Blob Data Reader for a few minutes, then removes it.

## The chain

| Step | Technique | What happens | Caught or blocked by |
|---|---|---|---|
| A | Prompt injection (LLM01), Tool Misuse (OWASP ASI02), Excessive Agency (LLM06) | A poisoned help article (`poisoned-article.md`) tells the model to read the payroll. | Lock 1 denies the finance key on the real agent. Rule **100822** fires on the weak twin's non-`kb/` tool call and stays quiet on the real run. |
| B | Data from Cloud Storage (ATT&CK T1530), exfiltration | The weak twin reads `finance/records/payroll-2026-11.csv` and prints it, so the data leaves through the console log. | Rule **100820** on any finance access; rule **100821** (level 14) on a successful read. After lock 2 is restored the read is **403**. |
| C | Valid Cloud Accounts (T1078.004), Account Manipulation (T1098) | Run Command on the lab's own SIEM VM runs a harmless command; the temporary grant is a role write on the finance container. | Rule **100823** on the `runCommand` action; rule **100824** on a role grant scoped to `finance`. |

The payroll file is synthetic (`finance/payroll-2026-11.csv`); every name and number in it is
made up for the lab.

## The defences this adds

- **Detections** (`../siem/local_rules.xml`, rules 100820–100824) over `StorageBlobLogs`,
  `ContainerAppConsoleLogs` and `AzureActivity`. A blocked finance read was level 3 in week 18;
  it is level 12 now, and a successful read is level 14.
- **Policy-as-code** (`../policy/checkov/checks`): a Checkov custom check, `CKV_SENTINEL_1`,
  that fails the gate if any Terraform grants a Storage Blob Data role on the `finance`
  container. The fixtures in `../policy/checkov/fixture` prove it: it fails the bad grant and
  passes the good one, and the gate asserts exactly that.

## Run it

```
scripts/update-rules.sh          # push the week-19 rules onto the running SIEM VM (once)
attack/run-chain.sh              # run the attack, then the hardened re-run; prints a tag
attack/evidence.sh <tag>         # poll the SIEM until every detection has fired
```

`run-chain.sh` needs the SIEM VM running (`az vm start -g rg-sentinel-lab -n vm-sentinel-siem`)
and you signed in to Azure as Owner of the lab.
