# Demo Runbook

## Co pokazać

1. Generator publikuje pełny lifecycle zamówienia do topiców order, payment, inventory, shipment, refund i risk.
2. Kibana filtruje logi po `order_id`, `trace_id`, `shipment_id`, `refund_id` i `event_type`.
3. Grafana pokazuje throughput, publish latency, payment failures, inventory shortages i shipment delays.
4. Spark zapisuje Bronze raw events, quarantine dla broken payloadów oraz Silver state tables.
5. Gold ma teraz osobne tabele dla minute metrics, funnel daily, payment failure hourly i revenue/refund daily.
6. Metabase może czytać nie tylko prosty minute KPI, ale też daily funnel i revenue/refund.
7. Jeden `trace_id` pokazuje kompletną historię: create -> validate -> pay -> reserve -> ship -> delay/refund/cancel.

## Przydatne pola do drilldown

- `order_id`
- `trace_id`
- `payment_id`
- `reservation_id`
- `shipment_id`
- `refund_id`
- `signal_id`
- `run_id`

## Faza 3: szybkie zapytania kontrolne

```sql
SHOW TABLES FROM iceberg_nessie.streaming;

SELECT count(*) FROM iceberg_nessie.streaming.bronze_commerce_events;
SELECT count(*) FROM iceberg_nessie.streaming.quarantine_commerce_events;
SELECT event_type, count(*) FROM iceberg_nessie.streaming.silver_order_events GROUP BY 1 ORDER BY 2 DESC;

SELECT order_status, count(*) FROM iceberg_nessie.streaming.silver_order_state GROUP BY 1 ORDER BY 2 DESC;
SELECT payment_status, count(*) FROM iceberg_nessie.streaming.silver_payments GROUP BY 1 ORDER BY 2 DESC;
SELECT shipment_status, count(*) FROM iceberg_nessie.streaming.silver_shipments GROUP BY 1 ORDER BY 2 DESC;
SELECT refund_status, count(*) FROM iceberg_nessie.streaming.silver_refunds GROUP BY 1 ORDER BY 2 DESC;

SELECT * FROM iceberg_nessie.streaming.gold_order_funnel_daily ORDER BY business_date DESC LIMIT 20;
SELECT * FROM iceberg_nessie.streaming.gold_payment_failure_rate_hourly ORDER BY window_start DESC LIMIT 20;
SELECT * FROM iceberg_nessie.streaming.gold_revenue_refund_daily ORDER BY business_date DESC LIMIT 20;
```

## Replay / backfill

- Domyślnie job używa `--starting-offsets latest`.
- Jeśli chcesz backfill po wdrożeniu fazy 3, ustaw tymczasowo `--starting-offsets earliest` i zmień `--checkpoint-location` na nową ścieżkę wersjonowaną, np. `.../commerce-events-v3-backfill`.
- Bronze jest deduplikowany po `topic + partition + offset`, a `silver_order_events` po `event_id`, więc replay jest bezpieczniejszy niż wcześniej.
