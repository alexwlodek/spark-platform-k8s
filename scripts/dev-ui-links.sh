#!/usr/bin/env bash
set -euo pipefail

INGRESS_DOMAIN="${INGRESS_DOMAIN:-127.0.0.1.nip.io}"
INGRESS_PORT="${INGRESS_PORT:-8080}"
ARGO_NAMESPACE="${ARGO_NAMESPACE:-argocd}"
MONITORING_NAMESPACE="${MONITORING_NAMESPACE:-monitoring}"
GRAFANA_SECRET="${GRAFANA_SECRET:-kube-prometheus-stack-grafana}"

require() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 1; }; }
require kubectl

current_context() {
  kubectl config current-context 2>/dev/null || true
}

expected_control_plane_node() {
  local ctx
  ctx="$(current_context)"
  if [[ "${ctx}" =~ ^kind-(.+)$ ]]; then
    echo "${BASH_REMATCH[1]}-control-plane"
  fi
}

ingress_controller_node() {
  kubectl -n ingress-nginx get pod \
    -l app.kubernetes.io/component=controller \
    -o jsonpath='{.items[0].spec.nodeName}' 2>/dev/null || true
}

decode_secret() {
  local namespace="$1"
  local name="$2"
  local key="$3"

  kubectl -n "${namespace}" get secret "${name}" -o "jsonpath={.data.${key}}" 2>/dev/null | base64 -d || true
}

controller_node="$(ingress_controller_node)"
control_plane_node="$(expected_control_plane_node)"
if [[ -n "${controller_node}" && -n "${control_plane_node}" && "${controller_node}" != "${control_plane_node}" ]]; then
  echo "WARNING: ingress-nginx-controller runs on '${controller_node}', expected '${control_plane_node}'."
  echo "UI links may be unreachable from host because kind maps 8080/8443 only to control-plane."
  echo "Fix:"
  echo "  kubectl -n ingress-nginx patch deployment ingress-nginx-controller --type=merge -p '{\"spec\":{\"template\":{\"spec\":{\"nodeSelector\":{\"kubernetes.io/hostname\":\"${control_plane_node}\",\"kubernetes.io/os\":\"linux\"}}}}}'"
  echo
fi

echo "DEV UI URLs (Ingress via ingress-nginx on :${INGRESS_PORT})"
echo "  Argo CD:    http://argocd.${INGRESS_DOMAIN}:${INGRESS_PORT}"
echo "  Grafana:    http://grafana.${INGRESS_DOMAIN}:${INGRESS_PORT}"
echo "  Prometheus: http://prometheus.${INGRESS_DOMAIN}:${INGRESS_PORT}"
echo "  Kibana:     http://kibana.${INGRESS_DOMAIN}:${INGRESS_PORT}"
echo "  Metabase:   http://metabase.${INGRESS_DOMAIN}:${INGRESS_PORT}"

