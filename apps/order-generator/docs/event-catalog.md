# Event Catalog

## Topics

- `commerce.order.lifecycle.v1`
- `commerce.payment.events.v1`
- `commerce.generator.technical.v1`

## Business events

- `order_created`
- `order_validated`
- `payment_authorized`
- `payment_failed`

## Technical events

- `schema_validation_failed`
- `retry_exhausted`
- `generator_backpressure`

## Correlation keys

- `order_id`: główny business key
- `trace_id`: pełen lifecycle pojedynczego zamówienia
- `run_id`: jeden przebieg generatora
- `payment_id`: identyfikator sub-flow płatności
