#!/usr/bin/env bash
set -euo pipefail

SPARK_HOME="${SPARK_HOME:-/opt/spark}"

case "${1:-}" in
  driver)
    shift
    exec "${SPARK_HOME}/bin/spark-submit" "$@"
    ;;
  executor)
    shift
    exec "${SPARK_HOME}/bin/spark-class" org.apache.spark.scheduler.cluster.k8s.KubernetesExecutorBackend "$@"
    ;;
  "")
    exec "${SPARK_HOME}/bin/spark-submit" --version
    ;;
  *)
    exec "$@"
    ;;
esac
