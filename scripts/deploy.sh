#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <target-org-alias-or-username>"
  exit 1
fi

TARGET_ORG="$1"

echo "Deploying SCV Genesys migration package to ${TARGET_ORG} ..."
sf project deploy start \
  --target-org "${TARGET_ORG}" \
  --manifest manifest/package.xml \
  --test-level RunLocalTests \
  --wait 30

echo "Deployment command submitted/completed."
