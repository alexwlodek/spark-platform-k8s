#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=prod-gcp-env.sh
source "${SCRIPT_DIR}/prod-gcp-env.sh"

GRAFANA_SECRET_NAME="${GRAFANA_SECRET_NAME:-spark-platform-prod-monitoring-grafana}"
GRAFANA_ADMIN_USER="${GRAFANA_ADMIN_USER:-}"
GRAFANA_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD:-}"
FORCE_RESEED="${FORCE_RESEED:-0}"

require() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 1; }; }
require gcloud
require jq
require openssl

secret_exists() {
  gcloud secrets describe "${GRAFANA_SECRET_NAME}" --project "${PROJECT_ID}" >/dev/null 2>&1
}

get_existing_secret_json() {
  if ! secret_exists; then
    return 0
  fi

  gcloud secrets versions access latest \
    --secret "${GRAFANA_SECRET_NAME}" \
    --project "${PROJECT_ID}" 2>/dev/null || true
}

existing_secret_json=""
existing_secret_json_for_jq="{}"
generated_admin_password=""

if [[ "${FORCE_RESEED}" == "1" ]]; then
  echo "FORCE_RESEED=1 set; ignoring any existing payload in ${PROJECT_ID}/${GRAFANA_SECRET_NAME}."
else
  existing_secret_json="$(get_existing_secret_json)"

  if [[ -n "${existing_secret_json}" ]] && ! jq -e . >/dev/null 2>&1 <<<"${existing_secret_json}"; then
    echo "Existing Secret Manager payload in ${PROJECT_ID}/${GRAFANA_SECRET_NAME} is not valid JSON." >&2
    echo "Run with FORCE_RESEED=1 to write a fresh version." >&2
    exit 1
  fi
fi

if [[ -n "${existing_secret_json}" ]]; then
  existing_secret_json_for_jq="${existing_secret_json}"
fi

if ! secret_exists; then
  echo "Creating Secret Manager secret ${PROJECT_ID}/${GRAFANA_SECRET_NAME}..."
  gcloud secrets create "${GRAFANA_SECRET_NAME}" \
    --replication-policy=automatic \
    --project "${PROJECT_ID}" >/dev/null
fi

existing_admin_user="$(jq -r '.["admin-user"] // ""' <<<"${existing_secret_json_for_jq}")"
existing_admin_password="$(jq -r '.["admin-password"] // ""' <<<"${existing_secret_json_for_jq}")"

if [[ "${FORCE_RESEED}" != "1" && -z "${GRAFANA_ADMIN_USER}" && -z "${GRAFANA_ADMIN_PASSWORD}" && -n "${existing_admin_user}" && -n "${existing_admin_password}" ]]; then
  echo "Using existing Secret Manager secret:"
  echo "  - ${PROJECT_ID}/${GRAFANA_SECRET_NAME}"
  echo "Fields:"
  echo "  - admin-user=${existing_admin_user}"
  echo "  - admin-password"
  exit 0
fi

if [[ -n "${GRAFANA_ADMIN_USER}" ]]; then
  admin_user="${GRAFANA_ADMIN_USER}"
elif [[ -n "${existing_admin_user}" ]]; then
  admin_user="${existing_admin_user}"
else
  admin_user="admin"
fi

if [[ -n "${GRAFANA_ADMIN_PASSWORD}" ]]; then
  admin_password="${GRAFANA_ADMIN_PASSWORD}"
elif [[ -n "${existing_admin_password}" ]]; then
  admin_password="${existing_admin_password}"
else
  generated_admin_password="$(openssl rand -base64 32 | tr -d '\n')"
  admin_password="${generated_admin_password}"
fi

payload="$(jq -n \
  --arg admin_user "${admin_user}" \
  --arg admin_password "${admin_password}" \
  '{
    "admin-user": $admin_user,
    "admin-password": $admin_password
  }'
)"

printf '%s\n' "${payload}" | gcloud secrets versions add "${GRAFANA_SECRET_NAME}" \
  --data-file=- \
  --project "${PROJECT_ID}" >/dev/null

echo "Seeded Secret Manager secret:"
echo "  - ${PROJECT_ID}/${GRAFANA_SECRET_NAME}"
echo "Fields:"
echo "  - admin-user=${admin_user}"
echo "  - admin-password"

if [[ -n "${generated_admin_password}" ]]; then
  echo "Grafana admin password was generated automatically."
  echo "Retrieve it later with:"
  echo "  gcloud secrets versions access latest --secret ${GRAFANA_SECRET_NAME} --project ${PROJECT_ID} | jq -r '.[\"admin-password\"]'"
fi
