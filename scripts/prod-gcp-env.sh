#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TERRAFORM_GCP_DIR="${TERRAFORM_GCP_DIR:-${REPO_ROOT}/infra/envs/gcp}"

resolve_tf_output() {
  local output_name="$1"

  if ! command -v terraform >/dev/null 2>&1; then
    return 0
  fi

  if [[ ! -d "${TERRAFORM_GCP_DIR}" ]]; then
    return 0
  fi

  terraform -chdir="${TERRAFORM_GCP_DIR}" output -raw "${output_name}" 2>/dev/null || true
}

PROJECT_ID="${PROJECT_ID:-$(resolve_tf_output project_id)}"
PROJECT_ID="${PROJECT_ID:-data-platform-prod-491113}"

REGION="${REGION:-$(resolve_tf_output cluster_region)}"
REGION="${REGION:-europe-central2}"

CLUSTER_NAME="${CLUSTER_NAME:-$(resolve_tf_output cluster_name)}"
CLUSTER_NAME="${CLUSTER_NAME:-data-platform-prod}"

KUBE_CONTEXT="${KUBE_CONTEXT:-gke_${PROJECT_ID}_${REGION}_${CLUSTER_NAME}}"

export SCRIPT_DIR REPO_ROOT TERRAFORM_GCP_DIR PROJECT_ID REGION CLUSTER_NAME KUBE_CONTEXT
