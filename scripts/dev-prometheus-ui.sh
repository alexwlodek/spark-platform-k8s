#!/usr/bin/env bash
set -euo pipefail

MONITORING_NAMESPACE="${MONITORING_NAMESPACE:-monitoring}"
PROMETHEUS_SERVICE="${PROMETHEUS_SERVICE:-kube-prometheus-stack-prometheus}"
PROMETHEUS_LOCAL_PORT="${PROMETHEUS_LOCAL_PORT:-9090}"
PROMETHEUS_SERVICE_PORT="${PROMETHEUS_SERVICE_PORT:-9090}"

echo "Prometheus URL: http://localhost:${PROMETHEUS_LOCAL_PORT}"
echo
echo "Starting port-forward..."
kubectl -n "${MONITORING_NAMESPACE}" port-forward "svc/${PROMETHEUS_SERVICE}" "${PROMETHEUS_LOCAL_PORT}:${PROMETHEUS_SERVICE_PORT}"
