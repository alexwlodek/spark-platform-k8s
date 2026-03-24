#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=prod-gcp-env.sh
source "${SCRIPT_DIR}/prod-gcp-env.sh"

MODE="all"
AUTO_APPROVE="${AUTO_APPROVE:-0}"

usage() {
  cat <<'EOF'
Usage:
  scripts/prod-deploy.sh [--infra | --bootstrap | --all] [--auto-approve]

Modes:
  --infra        Run Terraform init + apply for GKE production infrastructure
  --bootstrap    Configure kube context, seed Argo CD secret, bootstrap Argo CD
  --all          Run infra first, then bootstrap (default)

Options:
  --auto-approve Pass -auto-approve to terraform apply
  -h, --help     Show this help

Useful env overrides:
  TERRAFORM_GCP_DIR
  PROJECT_ID
  REGION
  CLUSTER_NAME
  AUTO_APPROVE=1
  ARGOCD_ADMIN_PASSWORD
  ARGOCD_ADMIN_BCRYPT_HASH
EOF
}

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing dependency: $1" >&2
    exit 1
  }
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --infra)
        MODE="infra"
        ;;
      --bootstrap)
        MODE="bootstrap"
        ;;
      --all)
        MODE="all"
        ;;
      --auto-approve)
        AUTO_APPROVE="1"
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "Unknown argument: $1" >&2
        echo >&2
        usage >&2
        exit 1
        ;;
    esac
    shift
  done
}

run_infra() {
  require terraform

  if [[ ! -d "${TERRAFORM_GCP_DIR}" ]]; then
    echo "Missing Terraform directory: ${TERRAFORM_GCP_DIR}" >&2
    exit 1
  fi

  echo "Running Terraform init for PROD GKE in ${TERRAFORM_GCP_DIR}..."
  terraform -chdir="${TERRAFORM_GCP_DIR}" init

  echo "Applying PROD GKE infrastructure..."
  if [[ "${AUTO_APPROVE}" == "1" ]]; then
    terraform -chdir="${TERRAFORM_GCP_DIR}" apply -auto-approve
  else
    terraform -chdir="${TERRAFORM_GCP_DIR}" apply
  fi
}

run_bootstrap() {
  echo "Bootstrapping Argo CD and phase-1 platform apps on GKE..."
  "${SCRIPT_DIR}/prod-up.sh"
}

parse_args "$@"

case "${MODE}" in
  infra)
    run_infra
    ;;
  bootstrap)
    run_bootstrap
    ;;
  all)
    run_infra
    run_bootstrap
    ;;
esac

echo
echo "Completed PROD deploy mode: ${MODE}"
