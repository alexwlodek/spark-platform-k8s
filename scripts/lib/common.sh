#!/usr/bin/env bash

COMMON_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "${COMMON_LIB_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${SCRIPTS_DIR}/.." && pwd)"

timestamp() {
  date +"%H:%M:%S"
}

log() {
  printf '[%s] %s\n' "$(timestamp)" "$*"
}

warn() {
  printf '[%s] WARN: %s\n' "$(timestamp)" "$*" >&2
}

die() {
  printf '[%s] ERROR: %s\n' "$(timestamp)" "$*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

repo_root() {
  printf '%s\n' "${REPO_ROOT}"
}

default_env_file() {
  local env_name="$1"
  printf '%s/local/%s.env.sh\n' "$(repo_root)" "${env_name}"
}

load_env_file() {
  local env_file="$1"

  if [[ ! -f "${env_file}" ]]; then
    die "Missing env file: ${env_file}. Create it with: cp $(repo_root)/local/prod.env.example ${env_file}"
  fi

  set -a
  # shellcheck source=/dev/null
  source "${env_file}"
  set +a
}

prod_stage_dir() {
  local env_name="$1"
  local stage_name="$2"
  printf '%s/infra/envs/%s/%s\n' "$(repo_root)" "${env_name}" "${stage_name}"
}

confirm_or_die() {
  local prompt="$1"
  local reply

  read -r -p "${prompt} [y/N] " reply
  case "${reply}" in
    y|Y|yes|YES)
      return 0
      ;;
    *)
      die "Aborted."
      ;;
  esac
}

apply_prod_env_defaults() {
  export DEPLOY_ENV="${DEPLOY_ENV:-prod}"

  if [[ -z "${GCP_PROJECT_ID:-}" && -n "${PROJECT_ID:-}" ]]; then
    export GCP_PROJECT_ID="${PROJECT_ID}"
  fi
  if [[ -z "${GCP_REGION:-}" && -n "${REGION:-}" ]]; then
    export GCP_REGION="${REGION}"
  fi
  if [[ -z "${GKE_CLUSTER_NAME:-}" && -n "${CLUSTER_NAME:-}" ]]; then
    export GKE_CLUSTER_NAME="${CLUSTER_NAME}"
  fi

  export GRAFANA_ADMIN_USER="${GRAFANA_ADMIN_USER:-admin}"
  export CLOUDFLARE_ZONE_ID="${CLOUDFLARE_ZONE_ID:-${CLOUDFLARE_DNS_ZONE_ID:-}}"

  if [[ -z "${GCP_ZONES:-}" && -n "${GCP_REGION:-}" ]]; then
    export GCP_ZONES="[\"${GCP_REGION}-a\",\"${GCP_REGION}-b\",\"${GCP_REGION}-c\"]"
  fi

  if [[ -z "${PUBLIC_HOSTNAMES:-}" ]]; then
    export PUBLIC_HOSTNAMES='["argocd","grafana","kibana"]'
  fi

  export GKE_MASTER_AUTHORIZED_NETWORKS="${GKE_MASTER_AUTHORIZED_NETWORKS:-[]}"
  if [[ -z "${TF_RESOURCE_LABELS:-}" ]]; then
    export TF_RESOURCE_LABELS='{}'
  fi

  if [[ -z "${GCP_NETWORK_NAME:-}" && -n "${GKE_CLUSTER_NAME:-}" ]]; then
    export GCP_NETWORK_NAME="${GKE_CLUSTER_NAME}-vpc"
  fi
  if [[ -z "${GCP_SUBNETWORK_NAME:-}" && -n "${GKE_CLUSTER_NAME:-}" ]]; then
    export GCP_SUBNETWORK_NAME="${GKE_CLUSTER_NAME}-gke"
  fi
  if [[ -z "${PUBLIC_GATEWAY_IP_NAME:-}" && -n "${GKE_CLUSTER_NAME:-}" ]]; then
    export PUBLIC_GATEWAY_IP_NAME="${GKE_CLUSTER_NAME}-public-gateway-ip"
  fi
  if [[ -z "${CLOUD_SQL_PRIVATE_SERVICE_RANGE_NAME:-}" && -n "${GKE_CLUSTER_NAME:-}" ]]; then
    export CLOUD_SQL_PRIVATE_SERVICE_RANGE_NAME="${GKE_CLUSTER_NAME}-cloudsql-private-range"
  fi
  if [[ -z "${LAKE_BUCKET_NAME:-}" && -n "${GKE_CLUSTER_NAME:-}" ]]; then
    export LAKE_BUCKET_NAME="${GKE_CLUSTER_NAME}-lake"
  fi
  if [[ -z "${CLOUD_SQL_INSTANCE_NAME:-}" && -n "${GKE_CLUSTER_NAME:-}" ]]; then
    export CLOUD_SQL_INSTANCE_NAME="${GKE_CLUSTER_NAME}-nessie"
  fi

  export GCP_SUBNET_CIDR="${GCP_SUBNET_CIDR:-10.70.0.0/20}"
  export GCP_PODS_SECONDARY_RANGE_NAME="${GCP_PODS_SECONDARY_RANGE_NAME:-gke-pods}"
  export GCP_PODS_CIDR="${GCP_PODS_CIDR:-10.80.0.0/14}"
  export GCP_SERVICES_SECONDARY_RANGE_NAME="${GCP_SERVICES_SECONDARY_RANGE_NAME:-gke-services}"
  export GCP_SERVICES_CIDR="${GCP_SERVICES_CIDR:-10.84.0.0/20}"
  export BASE_DOMAIN="${BASE_DOMAIN:-alexwlodek.com}"
  export ENVIRONMENT_SUBDOMAIN="${ENVIRONMENT_SUBDOMAIN:-${DEPLOY_ENV}}"
  export CLOUD_SQL_PRIVATE_SERVICE_RANGE_PREFIX_LENGTH="${CLOUD_SQL_PRIVATE_SERVICE_RANGE_PREFIX_LENGTH:-16}"
  export GKE_MASTER_IPV4_CIDR="${GKE_MASTER_IPV4_CIDR:-172.16.0.0/28}"
  export GKE_NODE_SERVICE_ACCOUNT_NAME="${GKE_NODE_SERVICE_ACCOUNT_NAME:-gke-nodes}"
  export GKE_EXTERNAL_SECRETS_GSA_NAME="${GKE_EXTERNAL_SECRETS_GSA_NAME:-external-secrets}"
  export GKE_PLATFORM_MACHINE_TYPE="${GKE_PLATFORM_MACHINE_TYPE:-e2-standard-2}"
  export GKE_PLATFORM_DISK_SIZE_GB="${GKE_PLATFORM_DISK_SIZE_GB:-50}"
  export GKE_PLATFORM_DISK_TYPE="${GKE_PLATFORM_DISK_TYPE:-pd-standard}"
  export GKE_BOOTSTRAP_DISK_SIZE_GB="${GKE_BOOTSTRAP_DISK_SIZE_GB:-20}"
  export GKE_BOOTSTRAP_DISK_TYPE="${GKE_BOOTSTRAP_DISK_TYPE:-pd-standard}"
  export GKE_PLATFORM_TOTAL_MIN_NODES="${GKE_PLATFORM_TOTAL_MIN_NODES:-3}"
  export GKE_PLATFORM_TOTAL_MAX_NODES="${GKE_PLATFORM_TOTAL_MAX_NODES:-6}"
  export PLATFORM_APPS_NAMESPACE="${PLATFORM_APPS_NAMESPACE:-apps}"
  export LAKE_BUCKET_LOCATION="${LAKE_BUCKET_LOCATION:-${GCP_REGION^^}}"
  export LAKE_BUCKET_FORCE_DESTROY="${LAKE_BUCKET_FORCE_DESTROY:-false}"
  export LAKE_RUNTIME_GSA_NAME="${LAKE_RUNTIME_GSA_NAME:-lake-runtime}"
  export NESSIE_RUNTIME_GSA_NAME="${NESSIE_RUNTIME_GSA_NAME:-nessie-runtime}"
  export SPARK_SERVICE_ACCOUNT_NAME="${SPARK_SERVICE_ACCOUNT_NAME:-spark-operator-spark}"
  export TRINO_SERVICE_ACCOUNT_NAME="${TRINO_SERVICE_ACCOUNT_NAME:-bi-trino}"
  export NESSIE_SERVICE_ACCOUNT_NAME="${NESSIE_SERVICE_ACCOUNT_NAME:-storage-nessie}"
  export CLOUD_SQL_DATABASE_VERSION="${CLOUD_SQL_DATABASE_VERSION:-POSTGRES_16}"
  export CLOUD_SQL_EDITION="${CLOUD_SQL_EDITION:-ENTERPRISE}"
  export CLOUD_SQL_TIER="${CLOUD_SQL_TIER:-db-custom-1-3840}"
  export CLOUD_SQL_AVAILABILITY_TYPE="${CLOUD_SQL_AVAILABILITY_TYPE:-ZONAL}"
  export CLOUD_SQL_DISK_TYPE="${CLOUD_SQL_DISK_TYPE:-PD_SSD}"
  export CLOUD_SQL_DISK_SIZE_GB="${CLOUD_SQL_DISK_SIZE_GB:-20}"
  export CLOUD_SQL_BACKUP_START_TIME="${CLOUD_SQL_BACKUP_START_TIME:-03:00}"
  export CLOUD_SQL_ENABLE_POINT_IN_TIME_RECOVERY="${CLOUD_SQL_ENABLE_POINT_IN_TIME_RECOVERY:-true}"
  export CLOUD_SQL_DELETION_PROTECTION="${CLOUD_SQL_DELETION_PROTECTION:-false}"
  export CLOUD_SQL_DATABASE_NAME="${CLOUD_SQL_DATABASE_NAME:-nessie}"
  export CLOUD_SQL_USER_NAME="${CLOUD_SQL_USER_NAME:-nessie}"
  export NESSIE_SECRET_ID="${NESSIE_SECRET_ID:-spark-platform-${DEPLOY_ENV}-storage-nessie}"
  export ARGO_NAMESPACE="${ARGO_NAMESPACE:-argocd}"
  export ARGO_RELEASE_NAME="${ARGO_RELEASE_NAME:-argocd}"
  export ARGO_HELM_REPO_NAME="${ARGO_HELM_REPO_NAME:-argo}"
  export ARGO_HELM_REPO_URL="${ARGO_HELM_REPO_URL:-https://argoproj.github.io/argo-helm}"
  export ARGOCD_CHART_VERSION="${ARGOCD_CHART_VERSION:-7.7.0}"
  export ROLLOUT_TIMEOUT="${ROLLOUT_TIMEOUT:-300s}"
  export POST_BOOTSTRAP_WAIT_SECONDS="${POST_BOOTSTRAP_WAIT_SECONDS:-600}"
  export ARGOCD_SECRET_NAME="${ARGOCD_SECRET_NAME:-spark-platform-${DEPLOY_ENV}-argocd}"
  export GRAFANA_SECRET_NAME="${GRAFANA_SECRET_NAME:-spark-platform-${DEPLOY_ENV}-monitoring-grafana}"
  export CLOUDFLARE_SECRET_NAME="${CLOUDFLARE_SECRET_NAME:-spark-platform-${DEPLOY_ENV}-cert-manager-cloudflare}"
  export PUBLIC_GATEWAY_NAMESPACE="${PUBLIC_GATEWAY_NAMESPACE:-gateway-system}"
  export PUBLIC_GATEWAY_NAME="${PUBLIC_GATEWAY_NAME:-${DEPLOY_ENV}-public-gateway}"
  export PUBLIC_GATEWAY_CERTIFICATE_NAME="${PUBLIC_GATEWAY_CERTIFICATE_NAME:-${DEPLOY_ENV}-wildcard}"
  export ARGOCD_PUBLIC_HOST="${ARGOCD_PUBLIC_HOST:-argocd.${ENVIRONMENT_SUBDOMAIN}.${BASE_DOMAIN}}"

  export PROJECT_ID="${PROJECT_ID:-${GCP_PROJECT_ID:-}}"
  export REGION="${REGION:-${GCP_REGION:-}}"
  export CLUSTER_NAME="${CLUSTER_NAME:-${GKE_CLUSTER_NAME:-}}"
  export KUBE_CONTEXT="${KUBE_CONTEXT:-gke_${PROJECT_ID}_${REGION}_${CLUSTER_NAME}}"
}

export_prod_terraform_vars() {
  export TF_VAR_project_id="${GCP_PROJECT_ID}"
  export TF_VAR_region="${GCP_REGION}"
  export TF_VAR_network_name="${GCP_NETWORK_NAME}"
  export TF_VAR_subnetwork_name="${GCP_SUBNETWORK_NAME}"
  export TF_VAR_subnet_cidr="${GCP_SUBNET_CIDR}"
  export TF_VAR_pods_secondary_range_name="${GCP_PODS_SECONDARY_RANGE_NAME}"
  export TF_VAR_pods_cidr="${GCP_PODS_CIDR}"
  export TF_VAR_services_secondary_range_name="${GCP_SERVICES_SECONDARY_RANGE_NAME}"
  export TF_VAR_services_cidr="${GCP_SERVICES_CIDR}"
  export TF_VAR_base_domain="${BASE_DOMAIN}"
  export TF_VAR_environment_subdomain="${ENVIRONMENT_SUBDOMAIN}"
  export TF_VAR_public_hostnames="${PUBLIC_HOSTNAMES}"
  export TF_VAR_cloudflare_zone_id="${CLOUDFLARE_ZONE_ID}"
  export TF_VAR_public_gateway_ip_name="${PUBLIC_GATEWAY_IP_NAME}"
  export TF_VAR_cloud_sql_private_service_range_name="${CLOUD_SQL_PRIVATE_SERVICE_RANGE_NAME}"
  export TF_VAR_cloud_sql_private_service_range_prefix_length="${CLOUD_SQL_PRIVATE_SERVICE_RANGE_PREFIX_LENGTH}"
  export TF_VAR_zones="${GCP_ZONES}"
  export TF_VAR_cluster_name="${GKE_CLUSTER_NAME}"
  export TF_VAR_master_ipv4_cidr_block="${GKE_MASTER_IPV4_CIDR}"
  export TF_VAR_master_authorized_networks="${GKE_MASTER_AUTHORIZED_NETWORKS}"
  export TF_VAR_node_service_account_name="${GKE_NODE_SERVICE_ACCOUNT_NAME}"
  export TF_VAR_external_secrets_gsa_name="${GKE_EXTERNAL_SECRETS_GSA_NAME}"
  export TF_VAR_platform_machine_type="${GKE_PLATFORM_MACHINE_TYPE}"
  export TF_VAR_platform_disk_size_gb="${GKE_PLATFORM_DISK_SIZE_GB}"
  export TF_VAR_platform_disk_type="${GKE_PLATFORM_DISK_TYPE}"
  export TF_VAR_bootstrap_disk_size_gb="${GKE_BOOTSTRAP_DISK_SIZE_GB}"
  export TF_VAR_bootstrap_disk_type="${GKE_BOOTSTRAP_DISK_TYPE}"
  export TF_VAR_platform_total_min_nodes="${GKE_PLATFORM_TOTAL_MIN_NODES}"
  export TF_VAR_platform_total_max_nodes="${GKE_PLATFORM_TOTAL_MAX_NODES}"
  export TF_VAR_environment="${DEPLOY_ENV}"
  export TF_VAR_apps_namespace="${PLATFORM_APPS_NAMESPACE}"
  export TF_VAR_lake_bucket_name="${LAKE_BUCKET_NAME}"
  export TF_VAR_lake_bucket_location="${LAKE_BUCKET_LOCATION}"
  export TF_VAR_lake_bucket_force_destroy="${LAKE_BUCKET_FORCE_DESTROY}"
  export TF_VAR_lake_runtime_gsa_name="${LAKE_RUNTIME_GSA_NAME}"
  export TF_VAR_nessie_runtime_gsa_name="${NESSIE_RUNTIME_GSA_NAME}"
  export TF_VAR_spark_service_account_name="${SPARK_SERVICE_ACCOUNT_NAME}"
  export TF_VAR_trino_service_account_name="${TRINO_SERVICE_ACCOUNT_NAME}"
  export TF_VAR_nessie_service_account_name="${NESSIE_SERVICE_ACCOUNT_NAME}"
  export TF_VAR_cloud_sql_instance_name="${CLOUD_SQL_INSTANCE_NAME}"
  export TF_VAR_cloud_sql_database_version="${CLOUD_SQL_DATABASE_VERSION}"
  export TF_VAR_cloud_sql_edition="${CLOUD_SQL_EDITION}"
  export TF_VAR_cloud_sql_tier="${CLOUD_SQL_TIER}"
  export TF_VAR_cloud_sql_availability_type="${CLOUD_SQL_AVAILABILITY_TYPE}"
  export TF_VAR_cloud_sql_disk_type="${CLOUD_SQL_DISK_TYPE}"
  export TF_VAR_cloud_sql_disk_size_gb="${CLOUD_SQL_DISK_SIZE_GB}"
  export TF_VAR_cloud_sql_backup_start_time="${CLOUD_SQL_BACKUP_START_TIME}"
  export TF_VAR_cloud_sql_enable_point_in_time_recovery="${CLOUD_SQL_ENABLE_POINT_IN_TIME_RECOVERY}"
  export TF_VAR_cloud_sql_deletion_protection="${CLOUD_SQL_DELETION_PROTECTION}"
  export TF_VAR_cloud_sql_database_name="${CLOUD_SQL_DATABASE_NAME}"
  export TF_VAR_cloud_sql_user_name="${CLOUD_SQL_USER_NAME}"
  export TF_VAR_nessie_secret_id="${NESSIE_SECRET_ID}"
  export TF_VAR_labels="${TF_RESOURCE_LABELS}"
}
