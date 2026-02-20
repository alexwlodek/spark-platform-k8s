#!/usr/bin/env bash
set -euo pipefail

LOGGING_NAMESPACE="${LOGGING_NAMESPACE:-logging}"
ELASTICSEARCH_SERVICE="${ELASTICSEARCH_SERVICE:-elasticsearch-master}"
ELASTICSEARCH_LOCAL_PORT="${ELASTICSEARCH_LOCAL_PORT:-19200}"
ELASTICSEARCH_SERVICE_PORT="${ELASTICSEARCH_SERVICE_PORT:-9200}"

ELASTICSEARCH_URL="${ELASTICSEARCH_URL:-}"
USE_PORT_FORWARD="0"
if [[ -z "${ELASTICSEARCH_URL}" ]]; then
  ELASTICSEARCH_URL="http://127.0.0.1:${ELASTICSEARCH_LOCAL_PORT}"
  USE_PORT_FORWARD="1"
fi

MARKER="${MARKER:-LOG_SMOKE_MARKER_}"
PF_PID=""

require() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 1; }; }
require kubectl
require curl

cleanup() {
  if [[ -n "${PF_PID}" ]]; then
    kill "${PF_PID}" >/dev/null 2>&1 || true
    wait "${PF_PID}" 2>/dev/null || true
  fi
}
trap cleanup EXIT

if [[ "${USE_PORT_FORWARD}" == "1" ]]; then
  echo "Starting local port-forward to Elasticsearch on :${ELASTICSEARCH_LOCAL_PORT} ..."
  kubectl -n "${LOGGING_NAMESPACE}" port-forward "svc/${ELASTICSEARCH_SERVICE}" "${ELASTICSEARCH_LOCAL_PORT}:${ELASTICSEARCH_SERVICE_PORT}" >/tmp/logging-smoke-es-pf.log 2>&1 &
  PF_PID=$!
  sleep 2
fi

if [[ "${MARKER}" == "LOG_SMOKE_MARKER_" ]]; then
  echo "Set MARKER from run.sh output, example:"
  echo "  MARKER=LOG_SMOKE_MARKER_1234567890 tests/observability/logging-smoke/verify.sh"
  exit 1
fi

hits="0"
for _ in $(seq 1 24); do
  raw="$(curl -fsS "${ELASTICSEARCH_URL}/_search" -H 'Content-Type: application/json' -d "{\"query\":{\"query_string\":{\"query\":\"${MARKER}\"}},\"size\":1}" || true)"
  if command -v jq >/dev/null 2>&1; then
    hits="$(printf '%s' "${raw}" | jq -r '.hits.total.value // .hits.total // 0' 2>/dev/null || echo 0)"
  else
    hits="$(printf '%s' "${raw}" | sed -n 's/.*\"total\":{[^}]*\"value\":\([0-9][0-9]*\).*/\1/p' | head -n1)"
    hits="${hits:-0}"
  fi

  if [[ "${hits}" =~ ^[0-9]+$ ]] && [[ "${hits}" -gt 0 ]]; then
    echo "Found marker in Elasticsearch. hits=${hits}"
    exit 0
  fi
  sleep 5
done

echo "Marker not found in Elasticsearch yet. hits=${hits}"
exit 1
