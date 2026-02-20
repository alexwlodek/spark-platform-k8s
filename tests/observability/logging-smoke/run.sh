#!/usr/bin/env bash
set -euo pipefail

APP_NAMESPACE="${APP_NAMESPACE:-apps}"
POD_NAME="${POD_NAME:-log-smoke-drill}"
MARKER="${MARKER:-LOG_SMOKE_MARKER_$(date +%s)}"

require() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 1; }; }
require kubectl

echo "Deleting previous pod (if present)..."
kubectl -n "${APP_NAMESPACE}" delete pod "${POD_NAME}" --ignore-not-found >/dev/null

echo "Creating drill pod and emitting logs..."
kubectl -n "${APP_NAMESPACE}" run "${POD_NAME}" \
  --image=busybox:1.36 \
  --restart=Never \
  -- /bin/sh -c "i=0; while [ \$i -lt 20 ]; do echo ${MARKER} line-\$i; i=\$((i+1)); sleep 1; done"

echo "Waiting for pod completion..."
kubectl -n "${APP_NAMESPACE}" wait --for=condition=Ready "pod/${POD_NAME}" --timeout=120s >/dev/null 2>&1 || true
kubectl -n "${APP_NAMESPACE}" wait --for=jsonpath='{.status.phase}'=Succeeded "pod/${POD_NAME}" --timeout=180s >/dev/null 2>&1 || true

echo
echo "Marker used by this run:"
echo "  ${MARKER}"
echo
echo "Next:"
echo "  MARKER=${MARKER} tests/observability/logging-smoke/verify.sh"
