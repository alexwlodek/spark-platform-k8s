#!/usr/bin/env bash
set -euo pipefail

APPS_NAMESPACE="${APPS_NAMESPACE:-apps}"
METABASE_SERVICE="${METABASE_SERVICE:-bi-metabase}"
METABASE_LOCAL_PORT="${METABASE_LOCAL_PORT:-3001}"
METABASE_SERVICE_PORT="${METABASE_SERVICE_PORT:-3000}"

echo "Metabase URL: http://localhost:${METABASE_LOCAL_PORT}"
echo
echo "Starting port-forward..."
kubectl -n "${APPS_NAMESPACE}" port-forward "svc/${METABASE_SERVICE}" "${METABASE_LOCAL_PORT}:${METABASE_SERVICE_PORT}"
