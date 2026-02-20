#!/usr/bin/env bash
set -euo pipefail

MONITORING_NAMESPACE="${MONITORING_NAMESPACE:-monitoring}"
PROMETHEUS_SERVICE="${PROMETHEUS_SERVICE:-kube-prometheus-stack-prometheus}"
PROMETHEUS_LOCAL_PORT="${PROMETHEUS_LOCAL_PORT:-19090}"
PROMETHEUS_SERVICE_PORT="${PROMETHEUS_SERVICE_PORT:-9090}"
PROMETHEUS_URL="${PROMETHEUS_URL:-}"
USE_PORT_FORWARD="0"
if [[ -z "${PROMETHEUS_URL}" ]]; then
  PROMETHEUS_URL="http://127.0.0.1:${PROMETHEUS_LOCAL_PORT}"
  USE_PORT_FORWARD="1"
fi

METRIC_QUERY='drill:spark_image_pull_backoff_pods'
ALERT_QUERY='ALERTS{alertname="DrillSparkImagePullBackOff",alertstate="firing"}'

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
  echo "Starting local port-forward to Prometheus on :${PROMETHEUS_LOCAL_PORT} ..."
  kubectl -n "${MONITORING_NAMESPACE}" port-forward "svc/${PROMETHEUS_SERVICE}" "${PROMETHEUS_LOCAL_PORT}:${PROMETHEUS_SERVICE_PORT}" >/tmp/bad-image-drill-prometheus-pf.log 2>&1 &
  PF_PID=$!
  sleep 2
fi

query() {
  local q="$1"
  curl -fsS --get "${PROMETHEUS_URL}/api/v1/query" --data-urlencode "query=${q}"
}

metric_raw="$(query "${METRIC_QUERY}")"
alert_raw="$(query "${ALERT_QUERY}")"

if command -v jq >/dev/null 2>&1; then
  metric_value="$(printf '%s' "${metric_raw}" | jq -r '.data.result[0].value[1] // "0"')"
  firing_count="$(printf '%s' "${alert_raw}" | jq -r '.data.result | length')"
else
  metric_value="$(printf '%s' "${metric_raw}" | sed -n 's/.*"value":\[[^]]*,\"\([0-9.][0-9.]*\)\"\].*/\1/p' | head -n1)"
  metric_value="${metric_value:-0}"
  if printf '%s' "${alert_raw}" | grep -q '"result":\[\]'; then
    firing_count="0"
  else
    firing_count="1"
  fi
fi

echo "Metric ${METRIC_QUERY} = ${metric_value}"
echo "Firing alerts (${ALERT_QUERY}) = ${firing_count}"

if [[ "${firing_count}" -ge 1 ]]; then
  echo "Drill alert is firing."
  exit 0
fi

echo "Alert is not firing yet. Wait ~2-3 minutes and run verify again."
exit 1
