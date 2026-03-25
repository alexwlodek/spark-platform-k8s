#!/usr/bin/env bash

VALIDATE_ENV_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${VALIDATE_ENV_LIB_DIR}/common.sh"

validate_required_vars() {
  local missing=()
  local var_name

  for var_name in "$@"; do
    if [[ -z "${!var_name:-}" ]]; then
      missing+=("${var_name}")
    fi
  done

  if (( ${#missing[@]} > 0 )); then
    die "Missing required environment variables: ${missing[*]}"
  fi
}

validate_one_of() {
  local description="$1"
  shift
  local var_name

  for var_name in "$@"; do
    if [[ -n "${!var_name:-}" ]]; then
      return 0
    fi
  done

  die "Set ${description}."
}

validate_json_var() {
  local var_name="$1"
  local raw_value="${!var_name:-}"

  if [[ -z "${raw_value}" ]]; then
    return 0
  fi

  if ! jq -e . >/dev/null 2>&1 <<<"${raw_value}"; then
    die "${var_name} must be valid JSON."
  fi
}

validate_prod_tooling() {
  local mode="${1:-up}"

  need_cmd terraform
  need_cmd gcloud
  need_cmd kubectl
  need_cmd helm
  need_cmd jq

  if [[ "${mode}" == "up" ]]; then
    need_cmd curl
    need_cmd openssl
  fi
}

validate_prod_env() {
  apply_prod_env_defaults
  validate_prod_tooling up

  validate_required_vars \
    GCP_PROJECT_ID \
    GCP_REGION \
    GCP_ZONES \
    GKE_CLUSTER_NAME \
    GRAFANA_ADMIN_PASSWORD \
    CLOUDFLARE_API_TOKEN

  validate_one_of "ARGOCD_ADMIN_PASSWORD or ARGOCD_ADMIN_BCRYPT_HASH" \
    ARGOCD_ADMIN_PASSWORD \
    ARGOCD_ADMIN_BCRYPT_HASH

  validate_json_var GCP_ZONES
  validate_json_var PUBLIC_HOSTNAMES
  validate_json_var GKE_MASTER_AUTHORIZED_NETWORKS
  validate_json_var TF_RESOURCE_LABELS
}

validate_prod_destroy_env() {
  apply_prod_env_defaults
  validate_prod_tooling destroy

  validate_required_vars \
    GCP_PROJECT_ID \
    GCP_REGION \
    GCP_ZONES \
    GKE_CLUSTER_NAME

  if [[ -n "${CLOUDFLARE_ZONE_ID:-}" ]]; then
    validate_required_vars CLOUDFLARE_API_TOKEN
  fi

  validate_json_var GCP_ZONES
  validate_json_var PUBLIC_HOSTNAMES
  validate_json_var GKE_MASTER_AUTHORIZED_NETWORKS
  validate_json_var TF_RESOURCE_LABELS
}
