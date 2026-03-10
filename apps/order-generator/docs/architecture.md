# Order Generator Architecture

`order-generator` jest teraz deterministyczno-losowym producentem business events dla ścieżki:

`order-generator -> Kafka -> Spark Structured Streaming -> Iceberg/Nessie -> Trino -> Metabase`

Najważniejsze elementy:

- canonical event envelope dla business i technical events
- JSON Schema w repo jako source of truth dla kontraktów
- structured JSON logs na stdout pod Fluent Bit / Elasticsearch / Kibana
- Prometheus metrics oraz `/healthz` i `/readyz`
- osobne topiki dla order lifecycle, payments i technical events
- Spark job zapisujący Bronze raw events oraz Gold KPI dla revenue i payment failure rate

MVP obejmuje:

- `order_created`
- `order_validated`
- `payment_authorized`
- `payment_failed`
- `schema_validation_failed`
- `retry_exhausted`
- `generator_backpressure`
