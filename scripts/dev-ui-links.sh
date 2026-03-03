#!/usr/bin/env bash
set -euo pipefail

INGRESS_DOMAIN="${INGRESS_DOMAIN:-127.0.0.1.nip.io}"
INGRESS_PORT="${INGRESS_PORT:-8080}"
ARGO_NAMESPACE="${ARGO_NAMESPACE:-argocd}"
MONITORING_NAMESPACE="${MONITORING_NAMESPACE:-monitoring}"
GRAFANA_SECRET="${GRAFANA_SECRET:-kube-prometheus-stack-grafana}"

require() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 1; }; }
require kubectl

decode_secret() {
  local namespace="$1"
  local name="$2"
  local key="$3"

  kubectl -n "${namespace}" get secret "${name}" -o "jsonpath={.data.${key}}" 2>/dev/null | base64 -d || true
}

echo "DEV UI URLs (Ingress via ingress-nginx on :${INGRESS_PORT})"
echo "  Argo CD:    http://argocd.${INGRESS_DOMAIN}:${INGRESS_PORT}"
echo "  Grafana:    http://grafana.${INGRESS_DOMAIN}:${INGRESS_PORT}"
echo "  Prometheus: http://prometheus.${INGRESS_DOMAIN}:${INGRESS_PORT}"
echo "  Kibana:     http://kibana.${INGRESS_DOMAIN}:${INGRESS_PORT}"
echo "  Metabase:   http://metabase.${INGRESS_DOMAIN}:${INGRESS_PORT}"
echo
echo "Credentials:"
echo "  Argo CD:"
echo "    user: admin"
echo -n "    pass: "
decode_secret "${ARGO_NAMESPACE}" argocd-initial-admin-secret password
echo
echo "  Grafana:"
echo -n "    user: "
decode_secret "${MONITORING_NAMESPACE}" "${GRAFANA_SECRET}" admin-user
echo
echo -n "    pass: "
decode_secret "${MONITORING_NAMESPACE}" "${GRAFANA_SECRET}" admin-password
echo
echo
echo "Fallback port-forward scripts:"
echo "  scripts/dev-argocd-ui.sh"
echo "  scripts/dev-grafana-ui.sh"
echo "  scripts/dev-prometheus-ui.sh"
echo "  scripts/dev-kibana-ui.sh"
echo "  scripts/dev-metabase-ui.sh"
