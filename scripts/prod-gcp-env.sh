#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TERRAFORM_GCP_ROOT_DIR="${TERRAFORM_GCP_ROOT_DIR:-${REPO_ROOT}/infra/envs/gcp}"
TERRAFORM_GCP_NETWORK_DIR="${TERRAFORM_GCP_NETWORK_DIR:-${TERRAFORM_GCP_ROOT_DIR}/network}"
TERRAFORM_GCP_GKE_DIR="${TERRAFORM_GCP_GKE_DIR:-${TERRAFORM_GCP_ROOT_DIR}/gke}"
TERRAFORM_GCP_DIR="${TERRAFORM_GCP_DIR:-${TERRAFORM_GCP_GKE_DIR}}"

looks_like_tf_identifier() {
  local value="$1"
  [[ "${value}" =~ ^[a-z0-9][a-z0-9._-]*$ ]]
}

resolve_tf_output() {
  local terraform_dir="$1"
  local output_name="$2"
  local value

  if ! command -v terraform >/dev/null 2>&1; then
    return 0
  fi

  if [[ ! -d "${terraform_dir}" ]]; then
    return 0
  fi

  value="$(terraform -chdir="${terraform_dir}" output -raw "${output_name}" 2>/dev/null || true)"
  value="${value//$'\r'/}"

  if [[ -z "${value}" ]]; then
    return 0
  fi

  if ! looks_like_tf_identifier "${value}"; then
    return 0
  fi

  printf '%s' "${value}"
}

resolve_tf_output_raw() {
  local terraform_dir="$1"
  local output_name="$2"
  local value

  if ! command -v terraform >/dev/null 2>&1; then
    return 0
  fi

  if [[ ! -d "${terraform_dir}" ]]; then
    return 0
  fi

  value="$(terraform -chdir="${terraform_dir}" output -raw "${output_name}" 2>/dev/null || true)"
  value="${value//$'\r'/}"

  if [[ -z "${value}" ]]; then
    return 0
  fi

  printf '%s' "${value}"
}

PROJECT_ID="${PROJECT_ID:-$(resolve_tf_output "${TERRAFORM_GCP_GKE_DIR}" project_id)}"
PROJECT_ID="${PROJECT_ID:-$(resolve_tf_output "${TERRAFORM_GCP_NETWORK_DIR}" project_id)}"
PROJECT_ID="${PROJECT_ID:-data-platform-prod-491113}"

REGION="${REGION:-$(resolve_tf_output "${TERRAFORM_GCP_GKE_DIR}" cluster_region)}"
REGION="${REGION:-$(resolve_tf_output "${TERRAFORM_GCP_NETWORK_DIR}" region)}"
REGION="${REGION:-europe-central2}"

CLUSTER_NAME="${CLUSTER_NAME:-$(resolve_tf_output "${TERRAFORM_GCP_GKE_DIR}" cluster_name)}"
CLUSTER_NAME="${CLUSTER_NAME:-data-platform-prod}"

PUBLIC_GATEWAY_IP_NAME="${PUBLIC_GATEWAY_IP_NAME:-$(resolve_tf_output "${TERRAFORM_GCP_NETWORK_DIR}" public_gateway_ip_name)}"
PUBLIC_GATEWAY_IP_NAME="${PUBLIC_GATEWAY_IP_NAME:-data-platform-prod-public-gateway-ip}"

PUBLIC_GATEWAY_IP_ADDRESS="${PUBLIC_GATEWAY_IP_ADDRESS:-$(resolve_tf_output_raw "${TERRAFORM_GCP_NETWORK_DIR}" public_gateway_ip_address)}"

KUBE_CONTEXT="${KUBE_CONTEXT:-gke_${PROJECT_ID}_${REGION}_${CLUSTER_NAME}}"

export SCRIPT_DIR REPO_ROOT TERRAFORM_GCP_ROOT_DIR TERRAFORM_GCP_NETWORK_DIR TERRAFORM_GCP_GKE_DIR TERRAFORM_GCP_DIR PROJECT_ID REGION CLUSTER_NAME PUBLIC_GATEWAY_IP_NAME PUBLIC_GATEWAY_IP_ADDRESS KUBE_CONTEXT
