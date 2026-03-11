# Event Catalog

## Topics

- `commerce.order.lifecycle.v1`
- `commerce.payment.events.v1`
- `commerce.inventory.events.v1`
- `commerce.shipment.events.v1`
- `commerce.refund.events.v1`
- `commerce.risk.events.v1`
- `commerce.generator.technical.v1`

## Business events

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

## Technical events

- `malformed_event_generated`
- `schema_validation_failed`
- `retry_exhausted`
- `generator_backpressure`

## Correlation keys

- `order_id`: główny business key
- `trace_id`: pełen lifecycle pojedynczego zamówienia
- `run_id`: jeden przebieg generatora
- `payment_id`: identyfikator sub-flow płatności
- `reservation_id`: identyfikator rezerwacji inventory
- `shipment_id`: identyfikator wysyłki
- `refund_id`: identyfikator refundu
- `signal_id`: identyfikator sygnału fraudowego
