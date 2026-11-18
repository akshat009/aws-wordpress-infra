#!/bin/bash
# ==============================================================================
# File: .github/scripts/ssm-run.sh
# Runs on the GitHub Actions runner. Sends shell commands to one EC2 instance
# through SSM Run Command (no SSH), waits for them, prints the output, and
# exits 1 if they failed.
#
# Usage: ssm-run.sh <instance-id> "<comment>" "<command 1>" ["<command 2>" ...]
# Each command is passed through jq, so quotes and $ need no extra escaping.
# ==============================================================================
set -euo pipefail

INSTANCE_ID="${1:?instance id}"
COMMENT="${2:?comment}"
shift 2

PARAMS=$(jq -n --args '{commands: $ARGS.positional, executionTimeout: ["600"]}' "$@")

COMMAND_ID=$(aws ssm send-command \
    --instance-ids "$INSTANCE_ID" \
    --document-name "AWS-RunShellScript" \
    --comment "${COMMENT:0:100}" \
    --parameters "$PARAMS" \
    --query "Command.CommandId" \
    --output text)
echo "SSM command $COMMAND_ID sent to $INSTANCE_ID ($COMMENT)"

STATUS="Pending"
for _ in $(seq 1 100); do
    sleep 6
    STATUS=$(aws ssm get-command-invocation \
        --command-id "$COMMAND_ID" --instance-id "$INSTANCE_ID" \
        --query "Status" --output text 2>/dev/null || echo "Pending")
    case "$STATUS" in
        Pending|InProgress|Delayed) continue ;;
        *) break ;;
    esac
done

echo "Status: $STATUS"
echo "=== Output ==="
aws ssm get-command-invocation --command-id "$COMMAND_ID" --instance-id "$INSTANCE_ID" \
    --query "StandardOutputContent" --output text || true

if [ "$STATUS" != "Success" ]; then
    echo "=== Errors ==="
    aws ssm get-command-invocation --command-id "$COMMAND_ID" --instance-id "$INSTANCE_ID" \
        --query "StandardErrorContent" --output text || true
    exit 1
fi
