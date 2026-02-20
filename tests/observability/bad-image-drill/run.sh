#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS_DIR="${SCRIPT_DIR}/manifests"

APP_NAMESPACE="apps"
APP_NAME="${APP_NAME:-drill-bad-image}"

require() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 1; }; }
require kubectl

echo "Applying drill PrometheusRule..."
kubectl apply -f "${MANIFESTS_DIR}/prometheusrule-bad-image.yaml"

echo "Applying drill SparkApplication (broken image tag)..."
kubectl apply -f "${MANIFESTS_DIR}/sparkapplication-bad-image.yaml"

echo "Waiting up to 3 minutes for SparkApplication to move out of SUBMITTED..."
for _ in $(seq 1 18); do
  state="$(kubectl -n "${APP_NAMESPACE}" get sparkapplication "${APP_NAME}" -o jsonpath='{.status.applicationState.state}' 2>/dev/null || true)"
  state="${state:-unknown}"
  echo "  state=${state}"
  if [[ "${state}" != "SUBMITTED" && "${state}" != "unknown" && "${state}" != "" ]]; then
    break
  fi
  sleep 10
done

echo
echo "Current SparkApplication state/details:"
kubectl -n "${APP_NAMESPACE}" get sparkapplication "${APP_NAME}" -o wide || true

echo
echo "Next steps:"
echo "  - verify alerts: ${SCRIPT_DIR}/verify.sh"
echo "  - cleanup:       ${SCRIPT_DIR}/cleanup.sh"
