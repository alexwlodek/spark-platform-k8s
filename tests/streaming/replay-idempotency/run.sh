#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

APP_NAMESPACE="${APP_NAMESPACE:-apps}"
ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
ARGOCD_APP_NAME="${ARGOCD_APP_NAME:-streaming-pipeline}"
TRINO_DEPLOYMENT="${TRINO_DEPLOYMENT:-bi-trino}"
GENERATOR_DEPLOYMENT="${GENERATOR_DEPLOYMENT:-streaming-pipeline-generator}"
REPLAY_APP_NAME="${REPLAY_APP_NAME:-streaming-pipeline-replay}"
REPLAY_QUERY_NAME="${REPLAY_QUERY_NAME:-commerce_events_streaming_replay}"
REPLAY_DRIVER_LABEL="${REPLAY_DRIVER_LABEL:-commerce-events-streaming-replay}"

CATALOG_SCHEMA="${CATALOG_SCHEMA:-iceberg_nessie.streaming}"
SOURCE_SILVER_EVENTS_TABLE="${SOURCE_SILVER_EVENTS_TABLE:-${CATALOG_SCHEMA}.silver_order_events}"
REPLAY_TABLE_SUFFIX="${REPLAY_TABLE_SUFFIX:-_replay}"

REPLAY_STARTING_OFFSETS="${REPLAY_STARTING_OFFSETS:-earliest}"
REPLAY_WAIT_TIMEOUT_SECONDS="${REPLAY_WAIT_TIMEOUT_SECONDS:-900}"
REPLAY_POLL_SECONDS="${REPLAY_POLL_SECONDS:-15}"
REPLAY_STABLE_POLLS="${REPLAY_STABLE_POLLS:-3}"
GENERATOR_FREEZE_WAIT_SECONDS="${GENERATOR_FREEZE_WAIT_SECONDS:-30}"

DROP_REPLAY_TABLES_ON_EXIT="${DROP_REPLAY_TABLES_ON_EXIT:-0}"
KEEP_FAILED_REPLAY_APP="${KEEP_FAILED_REPLAY_APP:-0}"

WORKDIR="${WORKDIR:-$(mktemp -d /tmp/replay-idempotency.XXXXXX)}"
VALUES_FILE="${WORKDIR}/replay-values.yaml"

ORIGINAL_GENERATOR_REPLICAS=""
ORIGINAL_ARGO_SELF_HEAL=""
ARGO_SELF_HEAL_PATCHED="0"
GENERATOR_SCALED="0"

require() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 1; }; }
require kubectl
require helm
require diff

mkdir -p "${WORKDIR}"

REPLAY_BASE_TABLES=(
  "bronze_commerce_events"
  "quarantine_commerce_events"
  "silver_order_events"
  "silver_order_state"
  "silver_payments"
  "silver_shipments"
  "silver_refunds"
  "gold_order_metrics_minute"
  "gold_order_funnel_daily"
  "gold_payment_failure_rate_hourly"
  "gold_revenue_refund_daily"
)

replay_table_name() {
  local base_table="$1"
  echo "${CATALOG_SCHEMA}.${base_table}${REPLAY_TABLE_SUFFIX}"
}

trino_csv() {
  local sql="$1"
  kubectl -n "${APP_NAMESPACE}" exec "deploy/${TRINO_DEPLOYMENT}" -- \
    trino --output-format CSV_HEADER_UNQUOTED --execute "${sql}"
}

trino_scalar() {
  local sql="$1"
  local result
  result="$(trino_csv "${sql}" | tail -n +2 | sed '/^$/d' | head -n 1 || true)"
  printf '%s\n' "${result}"
}

table_exists() {
  local fully_qualified_table="$1"
  local catalog schema table_name
  catalog="$(echo "${fully_qualified_table}" | cut -d'.' -f1)"
  schema="$(echo "${fully_qualified_table}" | cut -d'.' -f2)"
  table_name="$(echo "${fully_qualified_table}" | cut -d'.' -f3)"

  local result
  result="$(trino_scalar "SELECT count(*) FROM ${catalog}.information_schema.tables WHERE table_schema = '${schema}' AND table_name = '${table_name}'")"
  [[ "${result:-0}" == "1" ]]
}

sparkapp_state() {
  kubectl -n "${APP_NAMESPACE}" get sparkapplication "${REPLAY_APP_NAME}" -o jsonpath='{.status.applicationState.state}' 2>/dev/null || true
}

sparkapp_driver_pod() {
  kubectl -n "${APP_NAMESPACE}" get sparkapplication "${REPLAY_APP_NAME}" -o jsonpath='{.status.driverInfo.podName}' 2>/dev/null || true
}

delete_replay_app() {
  kubectl -n "${APP_NAMESPACE}" delete sparkapplication "${REPLAY_APP_NAME}" --ignore-not-found >/dev/null 2>&1 || true

  for _ in $(seq 1 60); do
    if ! kubectl -n "${APP_NAMESPACE}" get sparkapplication "${REPLAY_APP_NAME}" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done

  echo "Timed out waiting for replay SparkApplication deletion: ${REPLAY_APP_NAME}" >&2
  return 1
}

drop_replay_tables() {
  local base_table
  for base_table in "${REPLAY_BASE_TABLES[@]}"; do
    trino_csv "DROP TABLE IF EXISTS $(replay_table_name "${base_table}")" >/dev/null
  done
}

patch_argocd_self_heal() {
  if ! kubectl -n "${ARGOCD_NAMESPACE}" get application "${ARGOCD_APP_NAME}" >/dev/null 2>&1; then
    echo "Missing Argo CD Application ${ARGOCD_NAMESPACE}/${ARGOCD_APP_NAME}" >&2
    exit 1
  fi

  ORIGINAL_ARGO_SELF_HEAL="$(kubectl -n "${ARGOCD_NAMESPACE}" get application "${ARGOCD_APP_NAME}" -o jsonpath='{.spec.syncPolicy.automated.selfHeal}' 2>/dev/null || true)"
  kubectl -n "${ARGOCD_NAMESPACE}" patch application "${ARGOCD_APP_NAME}" --type merge \
    -p '{"spec":{"syncPolicy":{"automated":{"selfHeal":false}}}}' >/dev/null
  ARGO_SELF_HEAL_PATCHED="1"
}

restore_argocd_self_heal() {
  if [[ "${ARGO_SELF_HEAL_PATCHED}" != "1" ]]; then
    return
  fi

  local desired="${ORIGINAL_ARGO_SELF_HEAL:-true}"
  kubectl -n "${ARGOCD_NAMESPACE}" patch application "${ARGOCD_APP_NAME}" --type merge \
    -p "{\"spec\":{\"syncPolicy\":{\"automated\":{\"selfHeal\":${desired}}}}}" >/dev/null || true
}

freeze_generator() {
  if ! kubectl -n "${APP_NAMESPACE}" get deployment "${GENERATOR_DEPLOYMENT}" >/dev/null 2>&1; then
    echo "Missing generator deployment ${APP_NAMESPACE}/${GENERATOR_DEPLOYMENT}" >&2
    exit 1
  fi

  ORIGINAL_GENERATOR_REPLICAS="$(kubectl -n "${APP_NAMESPACE}" get deployment "${GENERATOR_DEPLOYMENT}" -o jsonpath='{.spec.replicas}')"
  patch_argocd_self_heal

  echo "Scaling generator to 0 replicas..."
  kubectl -n "${APP_NAMESPACE}" scale deployment "${GENERATOR_DEPLOYMENT}" --replicas=0 >/dev/null
  GENERATOR_SCALED="1"

  for _ in $(seq 1 60); do
    local ready
    ready="$(kubectl -n "${APP_NAMESPACE}" get deployment "${GENERATOR_DEPLOYMENT}" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)"
    ready="${ready:-0}"
    if [[ "${ready}" == "0" ]]; then
      break
    fi
    sleep 2
  done

  sleep "${GENERATOR_FREEZE_WAIT_SECONDS}"
}

restore_generator() {
  if [[ "${GENERATOR_SCALED}" != "1" ]]; then
    restore_argocd_self_heal
    return
  fi

  local replicas="${ORIGINAL_GENERATOR_REPLICAS:-1}"
  echo "Restoring generator replicas to ${replicas}..."
  kubectl -n "${APP_NAMESPACE}" scale deployment "${GENERATOR_DEPLOYMENT}" --replicas="${replicas}" >/dev/null || true

  if [[ "${replicas}" != "0" ]]; then
    kubectl -n "${APP_NAMESPACE}" rollout status "deployment/${GENERATOR_DEPLOYMENT}" --timeout=180s >/dev/null || true
  fi

  restore_argocd_self_heal
}

render_replay_values() {
  local checkpoint_location="$1"

  cat > "${VALUES_FILE}" <<EOF
generator:
  enabled: false

metrics:
  podMonitor:
    enabled: false

grafanaDashboard:
  enabled: false

generatorGrafanaDashboard:
  enabled: false

prometheusRule:
  enabled: false

generatorPrometheusRule:
  enabled: false

sparkApplication:
  driver:
    labels:
      streaming-query: ${REPLAY_DRIVER_LABEL}
  executor:
    labels:
      streaming-query: ${REPLAY_DRIVER_LABEL}
  arguments:
    - --kafka-bootstrap-servers
    - streaming-kafka.apps.svc.cluster.local:9092
    - --kafka-topic
    - commerce.order.lifecycle.v1,commerce.payment.events.v1,commerce.inventory.events.v1,commerce.shipment.events.v1,commerce.refund.events.v1,commerce.risk.events.v1,commerce.generator.technical.v1
    - --starting-offsets
    - ${REPLAY_STARTING_OFFSETS}
    - --window-duration
    - 1 minute
    - --watermark-delay
    - 2 minutes
    - --checkpoint-location
    - ${checkpoint_location}
    - --bronze-table
    - $(replay_table_name "bronze_commerce_events")
    - --quarantine-table
    - $(replay_table_name "quarantine_commerce_events")
    - --silver-events-table
    - $(replay_table_name "silver_order_events")
    - --silver-order-state-table
    - $(replay_table_name "silver_order_state")
    - --silver-payments-table
    - $(replay_table_name "silver_payments")
    - --silver-shipments-table
    - $(replay_table_name "silver_shipments")
    - --silver-refunds-table
    - $(replay_table_name "silver_refunds")
    - --gold-table
    - $(replay_table_name "gold_order_metrics_minute")
    - --gold-funnel-table
    - $(replay_table_name "gold_order_funnel_daily")
    - --gold-payment-failure-table
    - $(replay_table_name "gold_payment_failure_rate_hourly")
    - --gold-revenue-refund-table
    - $(replay_table_name "gold_revenue_refund_daily")
    - --query-name
    - ${REPLAY_QUERY_NAME}
    - --trigger-processing-time
    - 10 seconds
    - --metrics-port
    - "8090"
EOF
}

apply_replay_app() {
  local checkpoint_location="$1"
  render_replay_values "${checkpoint_location}"

  helm template "${REPLAY_APP_NAME}" "${REPO_ROOT}/charts/streaming-pipeline" \
    --namespace "${APP_NAMESPACE}" \
    -f "${REPO_ROOT}/values/common/streaming-pipeline.yaml" \
    -f "${REPO_ROOT}/values/dev/streaming-pipeline.yaml" \
    -f "${VALUES_FILE}" \
    | kubectl apply -n "${APP_NAMESPACE}" -f - >/dev/null
}

wait_for_replay_running() {
  local deadline=$((SECONDS + REPLAY_WAIT_TIMEOUT_SECONDS))

  while (( SECONDS < deadline )); do
    local state
    state="$(sparkapp_state)"
    echo "Replay SparkApplication state: ${state:-unknown}"

    case "${state}" in
      RUNNING)
        return 0
        ;;
      FAILED|FAILING|SUBMISSION_FAILED)
        echo "Replay SparkApplication failed with state=${state}" >&2
        return 1
        ;;
    esac

    sleep 5
  done

  echo "Timed out waiting for replay SparkApplication to start" >&2
  return 1
}

wait_for_replay_catchup() {
  local target_max_event_time="$1"
  local previous_count=""
  local stable_polls=0
  local deadline=$((SECONDS + REPLAY_WAIT_TIMEOUT_SECONDS))
  local replay_silver_table
  replay_silver_table="$(replay_table_name "silver_order_events")"

  while (( SECONDS < deadline )); do
    local state replay_max replay_count
    state="$(sparkapp_state)"

    if table_exists "${replay_silver_table}"; then
      replay_max="$(trino_scalar "SELECT CAST(max(event_time) AS VARCHAR) FROM ${replay_silver_table}")"
      replay_count="$(trino_scalar "SELECT count(*) FROM ${replay_silver_table}")"
      replay_count="${replay_count:-0}"
    else
      replay_max=""
      replay_count="0"
    fi

    if [[ "${replay_count}" == "${previous_count}" ]]; then
      stable_polls=$((stable_polls + 1))
    else
      stable_polls=0
    fi
    previous_count="${replay_count}"

    echo "Replay progress: state=${state:-unknown} replay_max=${replay_max:-null} target_max=${target_max_event_time} replay_count=${replay_count} stable=${stable_polls}/${REPLAY_STABLE_POLLS}"

    case "${state}" in
      FAILED|FAILING|SUBMISSION_FAILED)
        echo "Replay SparkApplication failed with state=${state}" >&2
        return 1
        ;;
    esac

    if [[ -n "${replay_max}" && "${replay_max}" == "${target_max_event_time}" && "${stable_polls}" -ge "${REPLAY_STABLE_POLLS}" ]]; then
      return 0
    fi

    sleep "${REPLAY_POLL_SECONDS}"
  done

  echo "Timed out waiting for replay catch-up" >&2
  return 1
}

snapshot_to_file() {
  local sql="$1"
  local output_file="$2"
  trino_csv "${sql}" > "${output_file}"
}

capture_pass_snapshots() {
  local pass_name="$1"
  local duplicate_file="${WORKDIR}/${pass_name}-duplicates.csv"

  snapshot_to_file \
    "SELECT event_type, count(*) AS events FROM $(replay_table_name "silver_order_events") GROUP BY 1 ORDER BY 1" \
    "${WORKDIR}/${pass_name}-silver-events.csv"

  snapshot_to_file \
    "SELECT order_status, count(*) AS orders FROM $(replay_table_name "silver_order_state") GROUP BY 1 ORDER BY 1" \
    "${WORKDIR}/${pass_name}-order-state.csv"

  snapshot_to_file \
    "SELECT payment_status, count(*) AS payments FROM $(replay_table_name "silver_payments") GROUP BY 1 ORDER BY 1" \
    "${WORKDIR}/${pass_name}-payments.csv"

  snapshot_to_file \
    "SELECT shipment_status, count(*) AS shipments FROM $(replay_table_name "silver_shipments") GROUP BY 1 ORDER BY 1" \
    "${WORKDIR}/${pass_name}-shipments.csv"

  snapshot_to_file \
    "SELECT refund_status, count(*) AS refunds FROM $(replay_table_name "silver_refunds") GROUP BY 1 ORDER BY 1" \
    "${WORKDIR}/${pass_name}-refunds.csv"

  snapshot_to_file \
    "SELECT quarantine_reason, count(*) AS rows FROM $(replay_table_name "quarantine_commerce_events") GROUP BY 1 ORDER BY 1" \
    "${WORKDIR}/${pass_name}-quarantine.csv"

  snapshot_to_file \
    "SELECT window_start, region, channel, customer_segment, orders_created, payment_authorized, payment_failed, gross_revenue, payment_failure_rate FROM $(replay_table_name "gold_order_metrics_minute") ORDER BY 1,2,3,4" \
    "${WORKDIR}/${pass_name}-gold-minute.csv"

  snapshot_to_file \
    "SELECT business_date, region, channel, customer_segment, orders_created, orders_validated, payment_authorized, payment_failed, inventory_reserved, inventory_shortage, shipments_created, shipments_delayed, orders_cancelled, refund_requested, refund_completed, suspicious_orders, gross_revenue FROM $(replay_table_name "gold_order_funnel_daily") ORDER BY 1,2,3,4" \
    "${WORKDIR}/${pass_name}-gold-funnel.csv"

  snapshot_to_file \
    "SELECT window_start, region, channel, customer_segment, payment_authorized, payment_failed, payment_failure_rate FROM $(replay_table_name "gold_payment_failure_rate_hourly") ORDER BY 1,2,3,4" \
    "${WORKDIR}/${pass_name}-gold-payment-failure.csv"

  snapshot_to_file \
    "SELECT business_date, region, channel, customer_segment, gross_revenue, refunds_requested_amount, refunds_completed_amount, net_revenue, refund_requested_count, refund_completed_count FROM $(replay_table_name "gold_revenue_refund_daily") ORDER BY 1,2,3,4" \
    "${WORKDIR}/${pass_name}-gold-revenue-refund.csv"

  snapshot_to_file \
    "SELECT event_id, count(*) AS duplicates FROM $(replay_table_name "silver_order_events") GROUP BY 1 HAVING count(*) > 1 ORDER BY 1" \
    "${duplicate_file}"

  if [[ "$(wc -l < "${duplicate_file}")" -gt 1 ]]; then
    echo "Found duplicate event_id rows in $(replay_table_name "silver_order_events")" >&2
    cat "${duplicate_file}" >&2
    exit 1
  fi
}

compare_pass_snapshots() {
  local pass_one="$1"
  local pass_two="$2"
  local snapshot

  for snapshot in \
    silver-events.csv \
    order-state.csv \
    payments.csv \
    shipments.csv \
    refunds.csv \
    quarantine.csv \
    gold-minute.csv \
    gold-funnel.csv \
    gold-payment-failure.csv \
    gold-revenue-refund.csv; do
    echo "Comparing ${snapshot}..."
    diff -u "${WORKDIR}/${pass_one}-${snapshot}" "${WORKDIR}/${pass_two}-${snapshot}"
  done
}

cleanup() {
  local exit_code=$?
  set +e

  if [[ "${exit_code}" -ne 0 && "${KEEP_FAILED_REPLAY_APP}" == "1" ]]; then
    echo "Keeping replay SparkApplication for debugging because KEEP_FAILED_REPLAY_APP=1"
  else
    delete_replay_app >/dev/null 2>&1 || true
  fi

  if [[ "${DROP_REPLAY_TABLES_ON_EXIT}" == "1" ]]; then
    drop_replay_tables >/dev/null 2>&1 || true
  fi

  restore_generator

  echo
  echo "Artifacts directory:"
  echo "  ${WORKDIR}"

  exit "${exit_code}"
}
trap cleanup EXIT

echo "Working directory: ${WORKDIR}"
echo "Replay app name:   ${REPLAY_APP_NAME}"
echo "Replay suffix:     ${REPLAY_TABLE_SUFFIX}"

delete_replay_app >/dev/null 2>&1 || true
freeze_generator
drop_replay_tables

TARGET_MAX_EVENT_TIME="$(trino_scalar "SELECT CAST(max(event_time) AS VARCHAR) FROM ${SOURCE_SILVER_EVENTS_TABLE}")"
if [[ -z "${TARGET_MAX_EVENT_TIME}" ]]; then
  echo "Source table ${SOURCE_SILVER_EVENTS_TABLE} returned empty max(event_time). Aborting." >&2
  exit 1
fi

echo "Frozen source max(event_time): ${TARGET_MAX_EVENT_TIME}"

for pass in 1 2; do
  CHECKPOINT_LOCATION="s3a://streaming-lake/checkpoints/commerce-events-replay-$(date +%Y%m%d-%H%M%S)-pass${pass}"

  echo
  echo "=== Replay pass ${pass} ==="
  echo "Checkpoint: ${CHECKPOINT_LOCATION}"

  apply_replay_app "${CHECKPOINT_LOCATION}"
  wait_for_replay_running

  DRIVER_POD="$(sparkapp_driver_pod)"
  if [[ -n "${DRIVER_POD}" ]]; then
    echo "Replay driver pod: ${DRIVER_POD}"
  fi

  wait_for_replay_catchup "${TARGET_MAX_EVENT_TIME}"
  capture_pass_snapshots "pass${pass}"
  delete_replay_app
done

compare_pass_snapshots "pass1" "pass2"

echo
echo "Replay idempotency test passed."
echo "Key outputs:"
echo "  - pass1 vs pass2 snapshots are identical"
echo "  - no duplicate event_id rows in $(replay_table_name "silver_order_events")"
echo "  - generator restored to original replica count"
