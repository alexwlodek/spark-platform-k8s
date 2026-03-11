# Demo Runbook

## Co pokazać

1. Generator publikuje pełny lifecycle zamówienia do topiców order, payment, inventory, shipment, refund i risk.
2. Kibana filtruje logi po `order_id`, `trace_id`, `shipment_id`, `refund_id` i `event_type`.
3. Grafana pokazuje throughput, publish latency, payment failures, inventory shortages i shipment delays.
4. Spark zapisuje Bronze raw events oraz dalej liczy Gold KPI na orders/payments.
5. Metabase nadal może policzyć payment failure rate według `region`, `channel` i `customer_segment`.
6. Jeden `trace_id` pokazuje kompletną historię: create -> validate -> pay -> reserve -> ship -> delay/refund/cancel.

## Przydatne pola do drilldown

- `order_id`
- `trace_id`
- `payment_id`
- `reservation_id`
- `shipment_id`
- `refund_id`
- `signal_id`
- `run_id`
