#!/usr/bin/env bash
set -euo pipefail

MONITORING_NAMESPACE="${MONITORING_NAMESPACE:-monitoring}"
GRAFANA_SERVICE="${GRAFANA_SERVICE:-kube-prometheus-stack-grafana}"
GRAFANA_SECRET="${GRAFANA_SECRET:-kube-prometheus-stack-grafana}"
GRAFANA_LOCAL_PORT="${GRAFANA_LOCAL_PORT:-3000}"
GRAFANA_SERVICE_PORT="${GRAFANA_SERVICE_PORT:-80}"

echo "Grafana URL: http://localhost:${GRAFANA_LOCAL_PORT}"
echo "Credentials:"
echo -n "  user: "
kubectl -n "${MONITORING_NAMESPACE}" get secret "${GRAFANA_SECRET}" \
  -o jsonpath='{.data.admin-user}' 2>/dev/null | base64 -d || true
echo
echo -n "  pass: "
kubectl -n "${MONITORING_NAMESPACE}" get secret "${GRAFANA_SECRET}" \
  -o jsonpath='{.data.admin-password}' 2>/dev/null | base64 -d || true
echo
echo
echo "Starting port-forward..."
kubectl -n "${MONITORING_NAMESPACE}" port-forward "svc/${GRAFANA_SERVICE}" "${GRAFANA_LOCAL_PORT}:${GRAFANA_SERVICE_PORT}"
