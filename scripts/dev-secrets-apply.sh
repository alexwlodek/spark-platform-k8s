#!/usr/bin/env bash
set -euo pipefail

APPS_NAMESPACE="${APPS_NAMESPACE:-apps}"
MONITORING_NAMESPACE="${MONITORING_NAMESPACE:-monitoring}"

require() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 1; }; }
require kubectl

ensure_namespace() {
  local namespace="$1"
  kubectl get ns "${namespace}" >/dev/null 2>&1 || kubectl create ns "${namespace}" >/dev/null
}

get_existing_secret_value() {
  local namespace="$1"
  local secret_name="$2"
  local key="$3"

  kubectl -n "${namespace}" get secret "${secret_name}" -o "jsonpath={.data.${key}}" 2>/dev/null | base64 -d || true
}

resolve_value() {
  local explicit_value="$1"
  local namespace="$2"
  local secret_name="$3"
  local key="$4"
  local fallback="$5"
  local existing_value=""

  if [[ -n "${explicit_value}" ]]; then
    printf '%s' "${explicit_value}"
    return 0
  fi

  existing_value="$(get_existing_secret_value "${namespace}" "${secret_name}" "${key}")"
  if [[ -n "${existing_value}" ]]; then
    printf '%s' "${existing_value}"
    return 0
  fi

  printf '%s' "${fallback}"
}

ensure_namespace "${APPS_NAMESPACE}"
ensure_namespace "${MONITORING_NAMESPACE}"

MINIO_ROOT_USER_VALUE="$(resolve_value "${MINIO_ROOT_USER:-}" "${APPS_NAMESPACE}" "platform-minio-creds" "root-user" "minio")"
MINIO_ROOT_PASSWORD_VALUE="$(resolve_value "${MINIO_ROOT_PASSWORD:-}" "${APPS_NAMESPACE}" "platform-minio-creds" "root-password" "muminki123")"

NESSIE_DB_NAME_VALUE="$(resolve_value "${NESSIE_DB_NAME:-}" "${APPS_NAMESPACE}" "platform-nessie-db-creds" "database" "nessie")"
NESSIE_DB_USER_VALUE="$(resolve_value "${NESSIE_DB_USER:-}" "${APPS_NAMESPACE}" "platform-nessie-db-creds" "username" "nessie")"
NESSIE_DB_PASSWORD_VALUE="$(resolve_value "${NESSIE_DB_PASSWORD:-}" "${APPS_NAMESPACE}" "platform-nessie-db-creds" "password" "muminki123")"
NESSIE_DB_POSTGRES_PASSWORD_VALUE="$(resolve_value "${NESSIE_DB_POSTGRES_PASSWORD:-}" "${APPS_NAMESPACE}" "platform-nessie-db-creds" "postgres-password" "muminki123")"

GRAFANA_ADMIN_USER_VALUE="$(resolve_value "${GRAFANA_ADMIN_USER:-}" "${MONITORING_NAMESPACE}" "platform-grafana-admin" "admin-user" "admin")"
GRAFANA_ADMIN_PASSWORD_VALUE="$(resolve_value "${GRAFANA_ADMIN_PASSWORD:-}" "${MONITORING_NAMESPACE}" "platform-grafana-admin" "admin-password" "muminki123")"

kubectl -n "${APPS_NAMESPACE}" create secret generic platform-minio-creds \
  --from-literal=root-user="${MINIO_ROOT_USER_VALUE}" \
  --from-literal=root-password="${MINIO_ROOT_PASSWORD_VALUE}" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null

kubectl -n "${APPS_NAMESPACE}" create secret generic platform-nessie-creds \
  --from-literal=db-username="${NESSIE_DB_USER_VALUE}" \
  --from-literal=db-password="${NESSIE_DB_PASSWORD_VALUE}" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null

kubectl -n "${APPS_NAMESPACE}" create secret generic platform-nessie-db-creds \
  --from-literal=database="${NESSIE_DB_NAME_VALUE}" \
  --from-literal=username="${NESSIE_DB_USER_VALUE}" \
  --from-literal=password="${NESSIE_DB_PASSWORD_VALUE}" \
  --from-literal=postgres-password="${NESSIE_DB_POSTGRES_PASSWORD_VALUE}" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null

kubectl -n "${MONITORING_NAMESPACE}" create secret generic platform-grafana-admin \
  --from-literal=admin-user="${GRAFANA_ADMIN_USER_VALUE}" \
  --from-literal=admin-password="${GRAFANA_ADMIN_PASSWORD_VALUE}" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null

echo "Applied local DEV secrets:"
echo "  - ${APPS_NAMESPACE}/platform-minio-creds"
echo "  - ${APPS_NAMESPACE}/platform-nessie-creds"
echo "  - ${APPS_NAMESPACE}/platform-nessie-db-creds"
echo "  - ${MONITORING_NAMESPACE}/platform-grafana-admin"
