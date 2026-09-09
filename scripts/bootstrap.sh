#!/usr/bin/env bash
# One-time state backend: S3 bucket + DynamoDB lock table.
set -euo pipefail

cd "$(dirname "$0")/../terraform/bootstrap"

terraform init
terraform apply -auto-approve

echo "State backend ready."
echo "Now run: scripts/deploy.sh"
