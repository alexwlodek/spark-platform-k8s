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
AUTO_APPROVE="${AUTO_APPROVE:-1}"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/prod-up.sh --env prod [--env-file local/prod.env.sh] [--manual-approve]

Options:
  --env <name>        Environment to provision (currently only: prod)
  --env-file <path>   Override the default local env file path
  --auto-approve      Explicitly enable automatic Terraform apply confirmation (default)
  --manual-approve    Require manual confirmation during Terraform apply
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
      --auto-approve)
        AUTO_APPROVE="1"
        shift
        ;;
      --manual-approve)
        AUTO_APPROVE="0"
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

resolve_argocd_public_host_from_values() {
  local values_file="$(repo_root)/values/prod/public-gateway.yaml"

  if [[ ! -f "${values_file}" ]]; then
    return 0
  fi

  awk '
    $1 == "-" && $2 == "name:" {
      in_argocd = ($3 == "argocd")
      next
    }
    in_argocd && $1 == "host:" {
      print $2
      exit
    }
  ' "${values_file}"
}

resolve_gateway_ip() {
  local gateway_ip="${PUBLIC_GATEWAY_IP_ADDRESS:-}"

  if [[ -n "${gateway_ip}" ]]; then
    printf '%s' "${gateway_ip}"
    return 0
  fi

  kubectl -n "${PUBLIC_GATEWAY_NAMESPACE}" get gateway "${PUBLIC_GATEWAY_NAME}" \
    -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || true
}

wait_for_deployment_ready() {
  local namespace="$1"
  local deployment="$2"
  local deadline=$((SECONDS + POST_BOOTSTRAP_WAIT_SECONDS))

  log "Waiting for deployment ${namespace}/${deployment}"
  while (( SECONDS < deadline )); do
    if kubectl -n "${namespace}" rollout status "deployment/${deployment}" --timeout=5s >/dev/null 2>&1; then
      return 0
    fi
    sleep 5
  done

  die "Timed out waiting for deployment ${namespace}/${deployment}"
}

wait_for_clustersecretstore_ready() {
  local name="$1"
  local deadline=$((SECONDS + POST_BOOTSTRAP_WAIT_SECONDS))
  local ready=""

  log "Waiting for ClusterSecretStore ${name}"
  while (( SECONDS < deadline )); do
    ready="$(kubectl get clustersecretstore "${name}" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)"
    if [[ "${ready}" == "True" ]]; then
      return 0
    fi
    sleep 5
  done

  die "Timed out waiting for ClusterSecretStore ${name}"
}

wait_for_externalsecret_ready() {
  local namespace="$1"
  local name="$2"
  local deadline=$((SECONDS + POST_BOOTSTRAP_WAIT_SECONDS))
  local ready=""

  log "Waiting for ExternalSecret ${namespace}/${name}"
  while (( SECONDS < deadline )); do
    ready="$(kubectl -n "${namespace}" get externalsecret "${name}" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)"
    if [[ "${ready}" == "True" ]]; then
      return 0
    fi
    sleep 5
  done

  die "Timed out waiting for ExternalSecret ${namespace}/${name}"
}

wait_for_secret_data_keys() {
  local namespace="$1"
  local name="$2"
  local description="$3"
  shift 3

  local deadline=$((SECONDS + POST_BOOTSTRAP_WAIT_SECONDS))
  local key
  local value
  local all_present

  log "Waiting for secret ${namespace}/${name} to contain ${description}"
  while (( SECONDS < deadline )); do
    all_present=1
    for key in "$@"; do
      value="$(kubectl -n "${namespace}" get secret "${name}" -o "jsonpath={.data['${key}']}" 2>/dev/null || true)"
      if [[ -z "${value}" ]]; then
        all_present=0
        break
      fi
    done

    if (( all_present )); then
      return 0
    fi

    sleep 5
  done

  die "Timed out waiting for secret ${namespace}/${name}"
}

wait_for_gateway_programmed() {
  local deadline=$((SECONDS + POST_BOOTSTRAP_WAIT_SECONDS))
  local programmed=""

  log "Waiting for Gateway ${PUBLIC_GATEWAY_NAMESPACE}/${PUBLIC_GATEWAY_NAME}"
  while (( SECONDS < deadline )); do
    programmed="$(kubectl -n "${PUBLIC_GATEWAY_NAMESPACE}" get gateway "${PUBLIC_GATEWAY_NAME}" -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}' 2>/dev/null || true)"
    if [[ "${programmed}" == "True" ]]; then
      return 0
    fi
    sleep 5
  done

  die "Timed out waiting for Gateway ${PUBLIC_GATEWAY_NAMESPACE}/${PUBLIC_GATEWAY_NAME}"
}

wait_for_certificate_ready() {
  local deadline=$((SECONDS + POST_BOOTSTRAP_WAIT_SECONDS))
  local ready=""

  log "Waiting for Certificate ${PUBLIC_GATEWAY_NAMESPACE}/${PUBLIC_GATEWAY_CERTIFICATE_NAME}"
  while (( SECONDS < deadline )); do
    ready="$(kubectl -n "${PUBLIC_GATEWAY_NAMESPACE}" get certificate "${PUBLIC_GATEWAY_CERTIFICATE_NAME}" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)"
    if [[ "${ready}" == "True" ]]; then
      return 0
    fi
    sleep 5
  done

  die "Timed out waiting for Certificate ${PUBLIC_GATEWAY_NAMESPACE}/${PUBLIC_GATEWAY_CERTIFICATE_NAME}"
}

wait_for_public_https() {
  local host="$1"
  local gateway_ip="$2"
  local deadline=$((SECONDS + POST_BOOTSTRAP_WAIT_SECONDS))
  local http_code=""

  if [[ -z "${host}" || -z "${gateway_ip}" ]]; then
    warn "Skipping public HTTPS wait because the host or gateway IP is missing"
    return 0
  fi

  log "Waiting for https://${host}/ via ${gateway_ip}"
  while (( SECONDS < deadline )); do
    http_code="$(
      curl --silent --show-error --insecure \
        --output /dev/null \
        --write-out '%{http_code}' \
        --connect-timeout 5 \
        --max-time 15 \
        --resolve "${host}:443:${gateway_ip}" \
        "https://${host}/" 2>/dev/null || true
    )"

    case "${http_code}" in
      200|301|302|307|308)
        return 0
        ;;
    esac

    sleep 5
  done

  die "Timed out waiting for https://${host}/ (last HTTP code: ${http_code:-n/a})"
}

parse_args "$@"

[[ -n "${ENV_NAME}" ]] || die "Use --env prod"
[[ "${ENV_NAME}" == "prod" ]] || die "Only --env prod is currently supported"

ENV_FILE="${ENV_FILE:-$(default_env_file "${ENV_NAME}")}"

log "Loading environment from ${ENV_FILE}"
load_env_file "${ENV_FILE}"
validate_prod_env
export_prod_terraform_vars

NETWORK_DIR="$(prod_stage_dir "${ENV_NAME}" "00-network")"
GKE_DIR="$(prod_stage_dir "${ENV_NAME}" "10-gke")"
SHARED_SERVICES_DIR="$(prod_stage_dir "${ENV_NAME}" "20-shared-services")"

log "Applying staged Terraform for ${ENV_NAME}"
terraform_init_apply_dir "${NETWORK_DIR}" "${AUTO_APPROVE}"
terraform_init_apply_dir "${GKE_DIR}" "${AUTO_APPROVE}"
terraform_init_apply_dir "${SHARED_SERVICES_DIR}" "${AUTO_APPROVE}"

log "Setting active gcloud project to ${GCP_PROJECT_ID}"
gcloud config set project "${GCP_PROJECT_ID}" >/dev/null

log "Fetching credentials for GKE cluster ${GKE_CLUSTER_NAME}"
gcloud container clusters get-credentials "${GKE_CLUSTER_NAME}" \
  --region "${GCP_REGION}" \
  --project "${GCP_PROJECT_ID}" >/dev/null

# Generic bootstrap is the only prod bootstrap entrypoint now.
"${SCRIPT_DIR}/bootstrap-argocd.sh" --env "${ENV_NAME}" --context "${KUBE_CONTEXT}"

ARGOCD_PUBLIC_HOST="${ARGOCD_PUBLIC_HOST:-$(resolve_argocd_public_host_from_values)}"

wait_for_deployment_ready external-secrets external-secrets
wait_for_clustersecretstore_ready gcp-secretmanager
wait_for_externalsecret_ready argocd argocd-admin-credentials
wait_for_secret_data_keys argocd argocd-secret "Argo CD auth data" "admin.password" "admin.passwordMtime" "server.secretkey"
wait_for_externalsecret_ready monitoring monitoring-grafana-admin-credentials
wait_for_secret_data_keys monitoring platform-grafana-admin "Grafana admin credentials" "admin-user" "admin-password"
wait_for_gateway_programmed
wait_for_certificate_ready
wait_for_public_https "${ARGOCD_PUBLIC_HOST}" "$(resolve_gateway_ip)"

kubectl -n argocd delete secret argocd-initial-admin-secret --ignore-not-found >/dev/null 2>&1 || true

printf '\n'
log "Production bootstrap is ready"
printf 'Next commands:\n'
printf '  kubectl -n argocd get applications\n'
printf '  kubectl get gateway -A\n'
printf '  kubectl get httproute -A\n'
printf '  kubectl -n gateway-system get certificate\n'
printf '  kubectl -n spark-operator get pods\n'
printf '  https://%s/\n' "${ARGOCD_PUBLIC_HOST}"
