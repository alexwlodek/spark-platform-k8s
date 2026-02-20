# Logging Smoke Drill (EFK)

This drill verifies that logs from namespace `apps` are collected by Fluent Bit
and indexed in Elasticsearch.

## Run

```bash
tests/observability/logging-smoke/run.sh
```

## Verify

```bash
tests/observability/logging-smoke/verify.sh
```

`verify.sh` uses Elasticsearch API and succeeds when at least one log line with
the drill marker is indexed.

Useful env vars:

- `LOGGING_NAMESPACE` (default: `logging`)
- `ELASTICSEARCH_SERVICE` (default: `elasticsearch-master`)
- `ELASTICSEARCH_LOCAL_PORT` (default: `19200`)
- `ELASTICSEARCH_URL` (if set, port-forward is skipped)

## Cleanup

```bash
tests/observability/logging-smoke/cleanup.sh
```
