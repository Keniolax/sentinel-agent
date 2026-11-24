#!/usr/bin/env bash
# Ask the Sentinel Agent one question: start one Fargate task, wait for it to stop, and
# print the run ID, the task's exit code and its log lines.
#   scripts/ask.sh "What is your return policy?"
set -euo pipefail
question="${1:?usage: scripts/ask.sh \"question\"}"
out() { terraform -chdir="$(dirname "$0")/../infra/main" output -raw "$1"; }
cluster="$(out cluster)"; taskdef="$(out task_definition)"; sg="$(out agent_security_group)"
subnets="$(terraform -chdir="$(dirname "$0")/../infra/main" output -json subnets | python3 -c 'import json,sys; print(",".join(json.load(sys.stdin)))')"
run_id="ask-$(date -u +%Y%m%dT%H%M%SZ)-$RANDOM"

overrides="$(python3 -c 'import json,sys; print(json.dumps({"containerOverrides":[{"name":"agent","environment":[{"name":"QUESTION","value":sys.argv[1]},{"name":"RUN_ID","value":sys.argv[2]}]}]}))' "$question" "$run_id")"
task="$(aws ecs run-task --cluster "$cluster" --task-definition "$taskdef" --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[$subnets],securityGroups=[$sg],assignPublicIp=ENABLED}" \
  --overrides "$overrides" --query 'tasks[0].taskArn' --output text)"
echo "run_id=$run_id task=${task##*/}"
aws ecs wait tasks-stopped --cluster "$cluster" --tasks "$task"
aws ecs describe-tasks --cluster "$cluster" --tasks "$task" \
  --query 'tasks[0].containers[?name==`agent`].[exitCode,reason]' --output text
aws logs get-log-events --log-group-name "$(out agent_log_group)" \
  --log-stream-name "agent/agent/${task##*/}" --query 'events[].message' --output text | tr '\t' '\n'
