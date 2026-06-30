#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../infra"

staging_acr="$(terraform output -raw staging_acr_name)"
prod_acr="$(terraform output -raw prod_acr_name)"
image_name="demo-app"

printf '\nStaging ACR tags (%s/%s):\n' "$staging_acr" "$image_name"
az acr repository show-tags \
  --name "$staging_acr" \
  --repository "$image_name" \
  --output table

printf '\nProduction ACR tags (%s/%s):\n' "$prod_acr" "$image_name"
az acr repository show-tags \
  --name "$prod_acr" \
  --repository "$image_name" \
  --output table
