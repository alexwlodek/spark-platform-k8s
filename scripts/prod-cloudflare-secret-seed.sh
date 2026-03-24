#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=prod-gcp-env.sh
source "${SCRIPT_DIR}/prod-gcp-env.sh"

CLOUDFLARE_SECRET_NAME="${CLOUDFLARE_SECRET_NAME:-spark-platform-prod-cert-manager-cloudflare}"
CLOUDFLARE_API_TOKEN="${CLOUDFLARE_API_TOKEN:-}"
ALLOW_EMPTY_TOKEN="${ALLOW_EMPTY_TOKEN:-0}"

require() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 1; }; }
require gcloud
require jq

secret_exists() {
  gcloud secrets describe "${CLOUDFLARE_SECRET_NAME}" --project "${PROJECT_ID}" >/dev/null 2>&1
}

if ! secret_exists; then
  echo "Creating Secret Manager secret ${PROJECT_ID}/${CLOUDFLARE_SECRET_NAME}..."
  gcloud secrets create "${CLOUDFLARE_SECRET_NAME}" \
    --replication-policy=automatic \
    --project "${PROJECT_ID}" >/dev/null
fi

if [[ -z "${CLOUDFLARE_API_TOKEN}" ]]; then
  if gcloud secrets versions access latest --secret "${CLOUDFLARE_SECRET_NAME}" --project "${PROJECT_ID}" >/dev/null 2>&1; then
    echo "Using existing Secret Manager secret:"
    echo "  - ${PROJECT_ID}/${CLOUDFLARE_SECRET_NAME}"
    exit 0
  fi

  if [[ "${ALLOW_EMPTY_TOKEN}" == "1" ]]; then
    echo "Skipping Cloudflare token seed because CLOUDFLARE_API_TOKEN is not set."
    echo "HTTPS issuance will remain pending until ${PROJECT_ID}/${CLOUDFLARE_SECRET_NAME} contains {\"api-token\":\"...\"}."
    exit 0
  fi

  echo "Set CLOUDFLARE_API_TOKEN before seeding the cert-manager Cloudflare secret." >&2
  exit 1
fi

payload="$(jq -n --arg api_token "${CLOUDFLARE_API_TOKEN}" '{"api-token": $api_token}')"

printf '%s\n' "${payload}" | gcloud secrets versions add "${CLOUDFLARE_SECRET_NAME}" \
  --data-file=- \
  --project "${PROJECT_ID}" >/dev/null

echo "Seeded Secret Manager secret:"
echo "  - ${PROJECT_ID}/${CLOUDFLARE_SECRET_NAME}"
echo "Fields:"
echo "  - api-token"
