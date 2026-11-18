#!/bin/bash
# ==============================================================================
# File: .github/scripts/check-vars.sh
# Runs on the GitHub Actions runner, first step of every workflow.
# Fails with a clear message if a required repository variable is empty, instead
# of a confusing error later (e.g. "Could not assume role" with an empty ARN).
#
# Usage: check-vars.sh NAME [NAME ...]   (names of environment variables)
# Set them in: Settings > Secrets and variables > Actions > Variables
# ==============================================================================
set -euo pipefail

missing=()
for name in "$@"; do
    if [ -z "${!name:-}" ]; then
        missing+=("$name")
    fi
done

if [ ${#missing[@]} -gt 0 ]; then
    echo "::error::Missing repository variable(s): ${missing[*]}. Add them in Settings > Secrets and variables > Actions > Variables (see README: Repository variables)."
    exit 1
fi
echo "Repository variables OK: $*"
