#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=prod-gcp-env.sh
source "${SCRIPT_DIR}/prod-gcp-env.sh"

require() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 1; }; }
validate_identifier() {
  local name="$1"
  local value="$2"

  if [[ ! "${value}" =~ ^[a-z0-9][a-z0-9._-]*$ ]]; then
    echo "Invalid ${name}: '${value}'" >&2
    echo "Set ${name} explicitly or run terraform apply first." >&2
    exit 1
  fi
}

require gcloud
require kubectl
require curl

validate_identifier PROJECT_ID "${PROJECT_ID}"
validate_identifier REGION "${REGION}"
validate_identifier CLUSTER_NAME "${CLUSTER_NAME}"

POST_BOOTSTRAP_WAIT_SECONDS="${POST_BOOTSTRAP_WAIT_SECONDS:-600}"
PUBLIC_GATEWAY_NAMESPACE="${PUBLIC_GATEWAY_NAMESPACE:-gateway-system}"
PUBLIC_GATEWAY_NAME="${PUBLIC_GATEWAY_NAME:-prod-public-gateway}"
PUBLIC_GATEWAY_CERTIFICATE_NAME="${PUBLIC_GATEWAY_CERTIFICATE_NAME:-prod-wildcard}"

resolve_argocd_public_host_from_values() {
  local values_file="${REPO_ROOT}/values/prod/public-gateway.yaml"

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

ARGOCD_PUBLIC_HOST="${ARGOCD_PUBLIC_HOST:-$(resolve_argocd_public_host_from_values)}"

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

  echo "Waiting for deployment ${namespace}/${deployment}..."
  while (( SECONDS < deadline )); do
    if kubectl -n "${namespace}" rollout status "deployment/${deployment}" --timeout=5s >/dev/null 2>&1; then
      return 0
    fi
    sleep 5
  done

  echo "Timed out waiting for deployment ${namespace}/${deployment}" >&2
  return 1
}

wait_for_clustersecretstore_ready() {
  local name="$1"
  local deadline=$((SECONDS + POST_BOOTSTRAP_WAIT_SECONDS))
  local ready=""

  echo "Waiting for ClusterSecretStore ${name}..."
  while (( SECONDS < deadline )); do
    ready="$(kubectl get clustersecretstore "${name}" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)"
    if [[ "${ready}" == "True" ]]; then
      return 0
    fi
    sleep 5
  done

  echo "Timed out waiting for ClusterSecretStore ${name}" >&2
  return 1
}

wait_for_externalsecret_ready() {
  local namespace="$1"
  local name="$2"
  local deadline=$((SECONDS + POST_BOOTSTRAP_WAIT_SECONDS))
  local ready=""

  echo "Waiting for ExternalSecret ${namespace}/${name}..."
  while (( SECONDS < deadline )); do
    ready="$(kubectl -n "${namespace}" get externalsecret "${name}" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)"
    if [[ "${ready}" == "True" ]]; then
      return 0
    fi
    sleep 5
  done

  echo "Timed out waiting for ExternalSecret ${namespace}/${name}" >&2
  return 1
}

wait_for_secret_data_keys() {
  local namespace="$1"
  local name="$2"
  local description="$3"
  shift 3
  local deadline=$((SECONDS + POST_BOOTSTRAP_WAIT_SECONDS))
  local key=""
  local value=""
  local all_present=0

  echo "Waiting for secret ${namespace}/${name} to contain ${description}..."
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

  echo "Timed out waiting for secret ${namespace}/${name}" >&2
  return 1
}

wait_for_gateway_programmed() {
  local deadline=$((SECONDS + POST_BOOTSTRAP_WAIT_SECONDS))
  local programmed=""

  echo "Waiting for Gateway ${PUBLIC_GATEWAY_NAMESPACE}/${PUBLIC_GATEWAY_NAME}..."
  while (( SECONDS < deadline )); do
    programmed="$(kubectl -n "${PUBLIC_GATEWAY_NAMESPACE}" get gateway "${PUBLIC_GATEWAY_NAME}" -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}' 2>/dev/null || true)"
    if [[ "${programmed}" == "True" ]]; then
      return 0
    fi
    sleep 5
  done

  echo "Timed out waiting for Gateway ${PUBLIC_GATEWAY_NAMESPACE}/${PUBLIC_GATEWAY_NAME}" >&2
  return 1
}

wait_for_certificate_ready() {
  local deadline=$((SECONDS + POST_BOOTSTRAP_WAIT_SECONDS))
  local ready=""

  echo "Waiting for Certificate ${PUBLIC_GATEWAY_NAMESPACE}/${PUBLIC_GATEWAY_CERTIFICATE_NAME}..."
  while (( SECONDS < deadline )); do
    ready="$(kubectl -n "${PUBLIC_GATEWAY_NAMESPACE}" get certificate "${PUBLIC_GATEWAY_CERTIFICATE_NAME}" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)"
    if [[ "${ready}" == "True" ]]; then
      return 0
    fi
    sleep 5
  done

  echo "Timed out waiting for Certificate ${PUBLIC_GATEWAY_NAMESPACE}/${PUBLIC_GATEWAY_CERTIFICATE_NAME}" >&2
  return 1
}

wait_for_public_https() {
  local host="$1"
  local gateway_ip="$2"
  local deadline=$((SECONDS + POST_BOOTSTRAP_WAIT_SECONDS))
  local http_code=""

  if [[ -z "${host}" || -z "${gateway_ip}" ]]; then
    echo "Skipping public HTTPS wait because host or gateway IP is missing." >&2
    return 0
  fi

  echo "Waiting for HTTPS endpoint https://${host}/ via ${gateway_ip}..."
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

  echo "Timed out waiting for https://${host}/ (last HTTP code: ${http_code:-n/a})" >&2
  return 1
}

echo "Setting active gcloud project to '${PROJECT_ID}'..."
gcloud config set project "${PROJECT_ID}" >/dev/null

echo "Configuring kubectl context for GKE cluster '${CLUSTER_NAME}'..."
gcloud container clusters get-credentials "${CLUSTER_NAME}" \
  --region "${REGION}" \
  --project "${PROJECT_ID}" >/dev/null

ALLOW_EMPTY_TOKEN=1 "${SCRIPT_DIR}/prod-cloudflare-secret-seed.sh"
"${SCRIPT_DIR}/prod-grafana-secret-seed.sh"

APPLY_K8S_SECRET=1 \
ARGO_NAMESPACE="${ARGO_NAMESPACE:-argocd}" \
"${SCRIPT_DIR}/prod-argocd-secret-seed.sh"

PROJECT_ID="${PROJECT_ID}" \
REGION="${REGION}" \
CLUSTER_NAME="${CLUSTER_NAME}" \
"${SCRIPT_DIR}/prod-bootstrap-argocd.sh"

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

echo
echo "✅ PROD bootstrap ready."
echo "Check:"
echo "  - https://${ARGOCD_PUBLIC_HOST}/"
echo "  - kubectl -n argocd get applications"
echo "  - kubectl get gateway -A"
echo "  - kubectl get httproute -A"
echo "  - kubectl -n gateway-system get certificate"
echo "  - kubectl -n spark-operator get pods"
