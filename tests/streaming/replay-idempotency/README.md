# Replay Idempotency Test

Ten test weryfikuje punkt 9 dla fazy 3:

- zatrzymuje `order-generator`
- uruchamia dwa replaye `earliest` do tabel z sufiksem `_replay`
- używa nowego checkpointu dla każdego przebiegu
- porównuje snapshoty `pass1` vs `pass2`
- sprawdza, czy `silver_order_events_replay` nie ma duplikatów po `event_id`
- przywraca generator i usuwa tymczasowy `SparkApplication`

## Run

```bash
tests/streaming/replay-idempotency/run.sh
```

## Wymagania

- działający DEV cluster
- wdrożony `streaming-pipeline`
- działający Trino deployment `bi-trino`
- `kubectl` i `helm`

## Najważniejsze env vars

- `APP_NAMESPACE` domyślnie `apps`
- `ARGOCD_NAMESPACE` domyślnie `argocd`
- `ARGOCD_APP_NAME` domyślnie `streaming-pipeline`
- `TRINO_DEPLOYMENT` domyślnie `bi-trino`
- `GENERATOR_DEPLOYMENT` domyślnie `streaming-pipeline-generator`
- `REPLAY_WAIT_TIMEOUT_SECONDS` domyślnie `900`
- `REPLAY_POLL_SECONDS` domyślnie `15`
- `REPLAY_STABLE_POLLS` domyślnie `3`
- `DROP_REPLAY_TABLES_ON_EXIT` domyślnie `0`
- `KEEP_FAILED_REPLAY_APP` domyślnie `0`

## Co zostaje po teście

- katalog roboczy w `/tmp/replay-idempotency.*` z CSV snapshotami
- tabele `_replay` zostają domyślnie w Iceberg do inspekcji

Jeśli chcesz je automatycznie usuwać po zakończeniu testu:

```bash
DROP_REPLAY_TABLES_ON_EXIT=1 tests/streaming/replay-idempotency/run.sh
```
