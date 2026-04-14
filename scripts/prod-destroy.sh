#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/validate-env.sh
source "${SCRIPT_DIR}/lib/validate-env.sh"
# shellcheck source=lib/terraform.sh
source "${SCRIPT_DIR}/lib/terraform.sh"

ENV_NAME=""
ENV_FILE=""
FORCE="0"
CLOUD_SQL_DELETE_WAIT_TIMEOUT_SECONDS="${CLOUD_SQL_DELETE_WAIT_TIMEOUT_SECONDS:-600}"
CLOUD_SQL_DELETE_WAIT_INTERVAL_SECONDS="${CLOUD_SQL_DELETE_WAIT_INTERVAL_SECONDS:-15}"
SERVICE_NETWORKING_DELETE_RETRIES="${SERVICE_NETWORKING_DELETE_RETRIES:-4}"
SERVICE_NETWORKING_DELETE_RETRY_DELAY_SECONDS="${SERVICE_NETWORKING_DELETE_RETRY_DELAY_SECONDS:-60}"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/prod-destroy.sh --env prod [--env-file local/prod.env.sh] [--force]

Options:
  --env <name>        Environment to destroy (currently only: prod)
  --env-file <path>   Override the default local env file path
  --force             Skip the interactive confirmation prompt
  -h, --help          Show this help
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --env)
        [[ $# -ge 2 ]] || die "Missing value for --env"
        ENV_NAME="$2"
        shift 2
        ;;
      --env-file)
        [[ $# -ge 2 ]] || die "Missing value for --env-file"
        ENV_FILE="$2"
        shift 2
        ;;
      --force)
        FORCE="1"
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Unknown argument: $1"
        ;;
    esac
  done
}

cluster_exists() {
  gcloud container clusters describe "${GKE_CLUSTER_NAME}" \
    --region "${GCP_REGION}" \
    --project "${GCP_PROJECT_ID}" >/dev/null 2>&1
}

cleanup_argocd_bootstrap() {
  local root_file
  local project_file

  root_file="$(repo_root)/clusters/${ENV_NAME}/root.yaml"
  project_file="$(repo_root)/clusters/${ENV_NAME}/projects/platform.yaml"

  if ! cluster_exists; then
    warn "GKE cluster ${GKE_CLUSTER_NAME} is not reachable, skipping in-cluster Argo CD cleanup"
    return 0
  fi

  log "Fetching credentials for in-cluster cleanup"
  gcloud container clusters get-credentials "${GKE_CLUSTER_NAME}" \
    --region "${GCP_REGION}" \
    --project "${GCP_PROJECT_ID}" >/dev/null

  if [[ -n "${KUBE_CONTEXT:-}" ]]; then
    kubectl config use-context "${KUBE_CONTEXT}" >/dev/null 2>&1 || true
  fi

  if [[ -f "${root_file}" ]]; then
    log "Removing root Argo CD application"
    kubectl delete -n "${ARGO_NAMESPACE}" -f "${root_file}" --ignore-not-found >/dev/null 2>&1 || warn "Unable to delete ${root_file}"
  fi

  if [[ -f "${project_file}" ]]; then
    log "Removing platform AppProject"
    kubectl delete -n "${ARGO_NAMESPACE}" -f "${project_file}" --ignore-not-found >/dev/null 2>&1 || warn "Unable to delete ${project_file}"
  fi

  if helm -n "${ARGO_NAMESPACE}" status "${ARGO_RELEASE_NAME}" >/dev/null 2>&1; then
    log "Uninstalling Argo CD Helm release ${ARGO_RELEASE_NAME}"
    helm -n "${ARGO_NAMESPACE}" uninstall "${ARGO_RELEASE_NAME}" >/dev/null 2>&1 || warn "Unable to uninstall Argo CD cleanly"
  fi
}

prepare_shared_services_destroy() {
  local state_addresses=(
    "module.shared_services.google_sql_database.nessie"
    "module.shared_services.google_sql_user.nessie"
  )
  local present_addresses=()
  local state_address

  terraform_init_dir "${SHARED_SERVICES_DIR}"

  for state_address in "${state_addresses[@]}"; do
    if terraform -chdir="${SHARED_SERVICES_DIR}" state show "${state_address}" >/dev/null 2>&1; then
      present_addresses+=("${state_address}")
    fi
  done

  if (( ${#present_addresses[@]} == 0 )); then
    log "Cloud SQL child resources already absent from Terraform state"
    return 0
  fi

  log "Removing Cloud SQL child resources from Terraform state before destroy"
  terraform -chdir="${SHARED_SERVICES_DIR}" state rm "${present_addresses[@]}"
}

cloud_sql_instance_exists() {
  gcloud sql instances describe "${CLOUD_SQL_INSTANCE_NAME}" \
    --project "${GCP_PROJECT_ID}" >/dev/null 2>&1
}

wait_for_cloud_sql_instance_cleanup() {
  local waited_seconds="0"

  if ! cloud_sql_instance_exists; then
    log "Cloud SQL instance ${CLOUD_SQL_INSTANCE_NAME} is already absent"
    return 0
  fi

  log "Waiting for Cloud SQL instance ${CLOUD_SQL_INSTANCE_NAME} to finish deleting"

  while (( waited_seconds < CLOUD_SQL_DELETE_WAIT_TIMEOUT_SECONDS )); do
    sleep "${CLOUD_SQL_DELETE_WAIT_INTERVAL_SECONDS}"
    waited_seconds=$((waited_seconds + CLOUD_SQL_DELETE_WAIT_INTERVAL_SECONDS))

    if ! cloud_sql_instance_exists; then
      log "Cloud SQL instance ${CLOUD_SQL_INSTANCE_NAME} is gone"
      return 0
    fi
  done

  warn "Cloud SQL instance ${CLOUD_SQL_INSTANCE_NAME} is still present after ${CLOUD_SQL_DELETE_WAIT_TIMEOUT_SECONDS}s; network teardown may need a later retry"
  return 0
}

service_networking_connection_still_in_use() {
  local connections_json

  connections_json="$(gcloud services vpc-peerings list \
    --network="${GCP_NETWORK_NAME}" \
    --service="servicenetworking.googleapis.com" \
    --project="${GCP_PROJECT_ID}" \
    --format=json 2>/dev/null || printf '[]')"

  jq -e 'length > 0' >/dev/null 2>&1 <<<"${connections_json}"
}

wait_for_service_networking_connection_cleanup() {
  local waited_seconds="0"

  while (( waited_seconds < CLOUD_SQL_DELETE_WAIT_TIMEOUT_SECONDS )); do
    if ! service_networking_connection_still_in_use; then
      log "Private Service Access connection is gone"
      return 0
    fi

    sleep "${CLOUD_SQL_DELETE_WAIT_INTERVAL_SECONDS}"
    waited_seconds=$((waited_seconds + CLOUD_SQL_DELETE_WAIT_INTERVAL_SECONDS))
  done

  die "Private Service Access connection for ${GCP_NETWORK_NAME} is still present after ${CLOUD_SQL_DELETE_WAIT_TIMEOUT_SECONDS}s. Try rerunning ./scripts/prod-destroy.sh --env ${ENV_NAME} or delete the connection from the Google Cloud console."
}

delete_service_networking_connection() {
  local attempt

  if ! service_networking_connection_still_in_use; then
    log "Private Service Access connection is already absent"
    return 0
  fi

  for (( attempt=1; attempt<=SERVICE_NETWORKING_DELETE_RETRIES; attempt++ )); do
    log "Deleting Private Service Access connection with gcloud (attempt ${attempt}/${SERVICE_NETWORKING_DELETE_RETRIES})"

    if gcloud services vpc-peerings delete \
      --network="${GCP_NETWORK_NAME}" \
      --service="servicenetworking.googleapis.com" \
      --project="${GCP_PROJECT_ID}" \
      --quiet; then
      wait_for_service_networking_connection_cleanup
      return 0
    fi

    if ! service_networking_connection_still_in_use; then
      log "Private Service Access connection disappeared despite delete error"
      return 0
    fi

    if (( attempt == SERVICE_NETWORKING_DELETE_RETRIES )); then
      die "Unable to delete the Private Service Access connection for ${GCP_NETWORK_NAME} with gcloud. The Google Cloud console can sometimes complete this step when the Terraform provider cannot. If the console delete succeeds, rerun ./scripts/prod-destroy.sh --env ${ENV_NAME} to finish 00-network teardown."
    fi

    warn "Private Service Access connection delete did not complete; retrying in ${SERVICE_NETWORKING_DELETE_RETRY_DELAY_SECONDS}s"
    sleep "${SERVICE_NETWORKING_DELETE_RETRY_DELAY_SECONDS}"
  done
}

prepare_network_destroy() {
  local connection_state_address="module.network.google_service_networking_connection.private_vpc_connection"

  terraform_init_dir "${NETWORK_DIR}"

  delete_service_networking_connection

  if terraform -chdir="${NETWORK_DIR}" state show "${connection_state_address}" >/dev/null 2>&1; then
    log "Removing Private Service Access connection from Terraform state before network destroy"
    terraform -chdir="${NETWORK_DIR}" state rm "${connection_state_address}"
  fi
}

parse_args "$@"

[[ -n "${ENV_NAME}" ]] || die "Use --env prod"
[[ "${ENV_NAME}" == "prod" ]] || die "Only --env prod is currently supported"

ENV_FILE="${ENV_FILE:-$(default_env_file "${ENV_NAME}")}"

log "Loading environment from ${ENV_FILE}"
load_env_file "${ENV_FILE}"
validate_prod_destroy_env
export_prod_terraform_vars

NETWORK_DIR="$(prod_stage_dir "${ENV_NAME}" "00-network")"
GKE_DIR="$(prod_stage_dir "${ENV_NAME}" "10-gke")"
SHARED_SERVICES_DIR="$(prod_stage_dir "${ENV_NAME}" "20-shared-services")"

if [[ "${FORCE}" != "1" ]]; then
  printf 'Environment: %s\n' "${ENV_NAME}"
  printf 'Project: %s\n' "${GCP_PROJECT_ID}"
  printf 'Cluster: %s\n' "${GKE_CLUSTER_NAME}"
  printf 'Stages: 20-shared-services -> 10-gke -> 00-network\n'
  confirm_or_die "Destroy the production infrastructure and bootstrap resources?"
fi

log "Setting active gcloud project to ${GCP_PROJECT_ID}"
gcloud config set project "${GCP_PROJECT_ID}" >/dev/null

cleanup_argocd_bootstrap

export TF_VAR_lake_bucket_force_destroy="true"
prepare_shared_services_destroy

log "Destroying staged Terraform for ${ENV_NAME} in reverse order"
terraform_destroy_dir "${SHARED_SERVICES_DIR}" "1"
terraform_destroy_dir "${GKE_DIR}" "1"
wait_for_cloud_sql_instance_cleanup
prepare_network_destroy
terraform_destroy_dir "${NETWORK_DIR}" "1"

printf '\n'
log "Production infrastructure destroy completed"
