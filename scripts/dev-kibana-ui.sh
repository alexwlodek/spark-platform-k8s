#!/usr/bin/env bash
set -euo pipefail

LOGGING_NAMESPACE="${LOGGING_NAMESPACE:-logging}"
KIBANA_SERVICE="${KIBANA_SERVICE:-kibana}"
KIBANA_LOCAL_PORT="${KIBANA_LOCAL_PORT:-5601}"
KIBANA_SERVICE_PORT="${KIBANA_SERVICE_PORT:-5601}"

echo "Kibana URL: http://localhost:${KIBANA_LOCAL_PORT}"
echo
echo "Starting port-forward..."
kubectl -n "${LOGGING_NAMESPACE}" port-forward "svc/${KIBANA_SERVICE}" "${KIBANA_LOCAL_PORT}:${KIBANA_SERVICE_PORT}"
