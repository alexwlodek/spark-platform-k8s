#!/usr/bin/env bash
set -euo pipefail

AWS_REGION="${AWS_REGION:-eu-central-1}"
AWS_PROFILE="${AWS_PROFILE:-}"
AWS_SM_PREFIX="${AWS_SM_PREFIX:-/spark-platform/dev}"

MINIO_ROOT_USER="${MINIO_ROOT_USER:-minio}"
MINIO_ROOT_PASSWORD="${MINIO_ROOT_PASSWORD:-minio123}"

NESSIE_DB_NAME="${NESSIE_DB_NAME:-nessie}"
NESSIE_DB_USER="${NESSIE_DB_USER:-nessie}"
NESSIE_DB_PASSWORD="${NESSIE_DB_PASSWORD:-nessie123}"
NESSIE_DB_POSTGRES_PASSWORD="${NESSIE_DB_POSTGRES_PASSWORD:-postgres123}"

require() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 1; }; }
require aws

AWS_ARGS=(--region "${AWS_REGION}")
if [[ -n "${AWS_PROFILE}" ]]; then
  AWS_ARGS+=(--profile "${AWS_PROFILE}")
fi

upsert_secret() {
  local secret_id="$1"
  local secret_json="$2"
  if aws "${AWS_ARGS[@]}" secretsmanager describe-secret --secret-id "${secret_id}" >/dev/null 2>&1; then
    aws "${AWS_ARGS[@]}" secretsmanager update-secret --secret-id "${secret_id}" --secret-string "${secret_json}" >/dev/null
    echo "Updated ${secret_id}"
  else
    aws "${AWS_ARGS[@]}" secretsmanager create-secret --name "${secret_id}" --secret-string "${secret_json}" >/dev/null
    echo "Created ${secret_id}"
  fi
}

upsert_secret \
  "${AWS_SM_PREFIX}/storage-minio" \
  "{\"root-user\":\"${MINIO_ROOT_USER}\",\"root-password\":\"${MINIO_ROOT_PASSWORD}\"}"

upsert_secret \
  "${AWS_SM_PREFIX}/storage-nessie" \
  "{\"db-username\":\"${NESSIE_DB_USER}\",\"db-password\":\"${NESSIE_DB_PASSWORD}\"}"

upsert_secret \
  "${AWS_SM_PREFIX}/storage-nessie-db" \
  "{\"database\":\"${NESSIE_DB_NAME}\",\"username\":\"${NESSIE_DB_USER}\",\"password\":\"${NESSIE_DB_PASSWORD}\",\"postgres-password\":\"${NESSIE_DB_POSTGRES_PASSWORD}\"}"

echo
echo "Seed completed in region ${AWS_REGION} with prefix ${AWS_SM_PREFIX}."
