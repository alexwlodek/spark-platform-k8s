# Demo Runbook

## Co pokazać

1. Generator publikuje lifecycle zamówień i payments do osobnych topiców Kafka.
2. Kibana filtruje logi po `order_id`, `trace_id` i `event_type`.
3. Grafana pokazuje throughput, publish latency, payment failures i schema failures.
4. Spark zapisuje Bronze raw events oraz Gold KPI.
5. Metabase może policzyć payment failure rate według `region`, `channel` i `customer_segment`.

## Przydatne pola do drilldown

- `order_id`
- `trace_id`
- `payment_id`
- `run_id`
