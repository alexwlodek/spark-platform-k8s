# Order Generator Architecture

`order-generator` jest teraz deterministyczno-losowym producentem business events dla ścieżki:

`order-generator -> Kafka -> Spark Structured Streaming -> Iceberg/Nessie -> Trino -> Metabase`

Najważniejsze elementy:

- canonical event envelope dla business i technical events
- JSON Schema w repo jako source of truth dla kontraktów
- structured JSON logs na stdout pod Fluent Bit / Elasticsearch / Kibana
- Prometheus metrics oraz `/healthz` i `/readyz`
- osobne topiki dla order lifecycle, payments, inventory, shipments, refunds, risk i technical events
- Spark job zapisujący Bronze raw events oraz Gold KPI dla revenue i payment failure rate

Faza 2 obejmuje:

- `order_created`
- `order_validated`
- `payment_authorized`
- `payment_failed`
- `inventory_reserved`
- `inventory_shortage`
- `shipment_created`
- `shipment_delayed`
- `order_cancelled`
- `refund_requested`
- `refund_completed`
- `suspicious_order_flagged`
- `schema_validation_failed`
- `malformed_event_generated`
- `retry_exhausted`
- `generator_backpressure`
