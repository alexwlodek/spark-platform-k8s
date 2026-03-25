#!/usr/bin/env bash

TERRAFORM_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${TERRAFORM_LIB_DIR}/common.sh"

terraform_output_raw_if_exists() {
  local terraform_dir="$1"
  local output_name="$2"
  local value=""

  if ! command -v terraform >/dev/null 2>&1; then
    return 0
  fi

  if [[ ! -d "${terraform_dir}" ]]; then
    return 0
  fi

  value="$(terraform -chdir="${terraform_dir}" output -raw "${output_name}" 2>/dev/null || true)"
  value="${value//$'\r'/}"

  if [[ -n "${value}" ]]; then
    printf '%s' "${value}"
  fi
}

terraform_init_dir() {
  local terraform_dir="$1"

  need_cmd terraform

  if [[ ! -d "${terraform_dir}" ]]; then
    die "Missing Terraform directory: ${terraform_dir}"
  fi

  log "Terraform init: ${terraform_dir}"
  terraform -chdir="${terraform_dir}" init -input=false
}

terraform_plan_dir() {
  local terraform_dir="$1"

  terraform_init_dir "${terraform_dir}"
  log "Terraform plan: ${terraform_dir}"
  terraform -chdir="${terraform_dir}" plan -input=false
}

terraform_init_apply_dir() {
  local terraform_dir="$1"
  local auto_approve="${2:-0}"

  terraform_init_dir "${terraform_dir}"
  log "Terraform apply: ${terraform_dir}"

  if [[ "${auto_approve}" == "1" ]]; then
    terraform -chdir="${terraform_dir}" apply -input=false -auto-approve
  else
    terraform -chdir="${terraform_dir}" apply -input=false
  fi
}

terraform_destroy_dir() {
  local terraform_dir="$1"
  local auto_approve="${2:-1}"

  terraform_init_dir "${terraform_dir}"
  log "Terraform destroy: ${terraform_dir}"

  if [[ "${auto_approve}" == "1" ]]; then
    terraform -chdir="${terraform_dir}" destroy -input=false -auto-approve
  else
    terraform -chdir="${terraform_dir}" destroy -input=false
  fi
}
