# Bad Image Drill (Spark + Prometheus)

This drill deploys a SparkApplication with an invalid image tag and a dedicated
Prometheus alert rule. It is designed for alerting practice in DEV.

Resources created by the drill:

- `SparkApplication/apps/drill-bad-image`
- `PrometheusRule/apps/spark-drill-alerts`

The alert rule fires when the drill pod is in `ImagePullBackOff` for at least
2 minutes.

## Run

```bash
tests/observability/bad-image-drill/run.sh
```

## Verify

```bash
tests/observability/bad-image-drill/verify.sh
```

`verify.sh` auto-starts a local port-forward to Prometheus by default.

Useful env vars:

- `MONITORING_NAMESPACE` (default: `monitoring`)
- `PROMETHEUS_SERVICE` (default: `kube-prometheus-stack-prometheus`)
- `PROMETHEUS_LOCAL_PORT` (default: `19090`)
- `PROMETHEUS_URL` (if set, port-forward is skipped)

## Cleanup

```bash
tests/observability/bad-image-drill/cleanup.sh
```

## Notes

- The drill uses namespace `apps` because `spark-operator` is configured for
  that namespace.
- This drill does not change Argo CD application manifests.
