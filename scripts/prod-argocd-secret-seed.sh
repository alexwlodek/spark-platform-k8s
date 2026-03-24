#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=prod-gcp-env.sh
source "${SCRIPT_DIR}/prod-gcp-env.sh"

ARGOCD_SECRET_NAME="${ARGOCD_SECRET_NAME:-spark-platform-prod-argocd}"
ARGOCD_ADMIN_PASSWORD="${ARGOCD_ADMIN_PASSWORD:-}"
ARGOCD_ADMIN_BCRYPT_HASH="${ARGOCD_ADMIN_BCRYPT_HASH:-}"
ARGOCD_ADMIN_PASSWORD_MTIME="${ARGOCD_ADMIN_PASSWORD_MTIME:-}"
ARGOCD_SERVER_SECRETKEY="${ARGOCD_SERVER_SECRETKEY:-}"

require() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 1; }; }
require gcloud
require jq
require openssl

generate_bcrypt_hash() {
  local password="$1"
  local hash

  if command -v htpasswd >/dev/null 2>&1; then
    hash="$(htpasswd -bnBC 10 "" "${password}" | tr -d ':\n')"
    if [[ "${hash}" == '$2y$'* ]]; then
      hash="\$2a\$${hash#\$2y\$}"
    fi
    printf '%s' "${hash}"
    return 0
  fi

  echo "Missing dependency: htpasswd (apache2-utils/httpd-tools) or set ARGOCD_ADMIN_BCRYPT_HASH" >&2
  exit 1
}

secret_exists() {
  gcloud secrets describe "${ARGOCD_SECRET_NAME}" --project "${PROJECT_ID}" >/dev/null 2>&1
}

get_existing_secret_json() {
  if ! secret_exists; then
    return 0
  fi

  gcloud secrets versions access latest \
    --secret "${ARGOCD_SECRET_NAME}" \
    --project "${PROJECT_ID}" 2>/dev/null || true
}

existing_secret_json="$(get_existing_secret_json)"

if [[ -n "${existing_secret_json}" ]] && ! jq -e . >/dev/null 2>&1 <<<"${existing_secret_json}"; then
  echo "Existing Secret Manager payload in ${PROJECT_ID}/${ARGOCD_SECRET_NAME} is not valid JSON." >&2
  exit 1
fi

if ! secret_exists; then
  echo "Creating Secret Manager secret ${PROJECT_ID}/${ARGOCD_SECRET_NAME}..."
  gcloud secrets create "${ARGOCD_SECRET_NAME}" \
    --replication-policy=automatic \
    --project "${PROJECT_ID}" >/dev/null
fi

existing_admin_password_hash="$(jq -r '.["admin.password"] // ""' <<<"${existing_secret_json:-{}}")"
existing_admin_password_mtime="$(jq -r '.["admin.passwordMtime"] // ""' <<<"${existing_secret_json:-{}}")"
existing_server_secretkey="$(jq -r '.["server.secretkey"] // ""' <<<"${existing_secret_json:-{}}")"

if [[ -n "${ARGOCD_ADMIN_BCRYPT_HASH}" ]]; then
  admin_password_hash="${ARGOCD_ADMIN_BCRYPT_HASH}"
elif [[ -n "${ARGOCD_ADMIN_PASSWORD}" ]]; then
  admin_password_hash="$(generate_bcrypt_hash "${ARGOCD_ADMIN_PASSWORD}")"
else
  admin_password_hash="${existing_admin_password_hash}"
fi

if [[ -z "${admin_password_hash}" ]]; then
  echo "Set ARGOCD_ADMIN_PASSWORD or ARGOCD_ADMIN_BCRYPT_HASH before first PROD bootstrap." >&2
  exit 1
fi

if [[ -n "${ARGOCD_ADMIN_PASSWORD_MTIME}" ]]; then
  admin_password_mtime="${ARGOCD_ADMIN_PASSWORD_MTIME}"
elif [[ -n "${ARGOCD_ADMIN_PASSWORD}" || -n "${ARGOCD_ADMIN_BCRYPT_HASH}" ]]; then
  admin_password_mtime="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
else
  admin_password_mtime="${existing_admin_password_mtime}"
fi

if [[ -z "${admin_password_mtime}" ]]; then
  admin_password_mtime="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
fi

if [[ -n "${ARGOCD_SERVER_SECRETKEY}" ]]; then
  server_secretkey="${ARGOCD_SERVER_SECRETKEY}"
elif [[ -n "${existing_server_secretkey}" ]]; then
  server_secretkey="${existing_server_secretkey}"
else
  server_secretkey="$(openssl rand -base64 32 | tr -d '\n')"
fi

payload="$(jq -n \
  --arg admin_password "${admin_password_hash}" \
  --arg admin_password_mtime "${admin_password_mtime}" \
  --arg server_secretkey "${server_secretkey}" \
  '{
    "admin.password": $admin_password,
    "admin.passwordMtime": $admin_password_mtime,
    "server.secretkey": $server_secretkey
  }'
)"

printf '%s\n' "${payload}" | gcloud secrets versions add "${ARGOCD_SECRET_NAME}" \
  --data-file=- \
  --project "${PROJECT_ID}" >/dev/null

echo "Seeded Secret Manager secret:"
echo "  - ${PROJECT_ID}/${ARGOCD_SECRET_NAME}"
echo "Fields:"
echo "  - admin.password"
echo "  - admin.passwordMtime=${admin_password_mtime}"
echo "  - server.secretkey"
