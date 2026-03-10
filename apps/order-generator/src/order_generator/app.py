from __future__ import annotations

import signal
import time
from collections import Counter

from .config import AppConfig, load_config
from .envelope import build_event
from .observability import HealthState, JsonLogger, Metrics, start_health_server
from .publisher import KafkaPublisher, PublishError
from .state_machine import LifecycleBatch, PlannedEvent, OrderLifecycleSimulator
from .validation import SchemaValidationError, SchemaValidator


RUNNING = True


def _handle_signal(signum: int, _frame: object) -> None:
    global RUNNING
    RUNNING = False


def emit_technical_event(
    *,
    config: AppConfig,
    validator: SchemaValidator,
    publisher: KafkaPublisher,
    logger: JsonLogger,
    metrics: Metrics,
    event_type: str,
    sequence: int,
    payload: dict[str, object],
    trace_id: str,
    order_id: str | None = None,
    customer_id: str | None = None,
    payment_id: str | None = None,
) -> None:
    schema_ref = f"schemas/technical/{event_type}.v1.json"
    technical_event = build_event(
        event_type=event_type,
        event_version=1,
        schema_ref=schema_ref,
        producer=config.producer_service,
        environment=config.environment,
        run_id=config.run_id,
        trace_id=trace_id,
        partition_key=order_id or config.run_id,
        sequence=sequence,
        order_id=order_id,
        customer_id=customer_id,
        payment_id=payment_id,
        payload=payload,
    )
    try:
        validator.validate_event(technical_event)
        latency = publisher.publish(
            topic=config.topics.technical_events,
            key=str(technical_event["partition_key"]),
            event=technical_event,
        )
        metrics.record_publish_success(
            event_type=event_type,
            topic=config.topics.technical_events,
            latency_seconds=latency,
        )
        logger.log(
            "INFO",
            "Technical event emitted",
            component="technical",
            event_type=event_type,
            kafka_topic=config.topics.technical_events,
            trace_id=trace_id,
            order_id=order_id,
            customer_id=customer_id,
            payment_id=payment_id,
            latency_ms=round(latency * 1000, 2),
            run_id=config.run_id,
            status="published",
        )
    except Exception as exc:
        logger.log(
            "ERROR",
            "Failed to emit technical event",
            component="technical",
            event_type=event_type,
            trace_id=trace_id,
            order_id=order_id,
            customer_id=customer_id,
            payment_id=payment_id,
            run_id=config.run_id,
            error_class=exc.__class__.__name__,
            detail=str(exc),
        )


def process_planned_event(
    *,
    config: AppConfig,
    planned_event: PlannedEvent,
    validator: SchemaValidator,
    publisher: KafkaPublisher,
    logger: JsonLogger,
    metrics: Metrics,
    sequence: int,
) -> bool:
    event = planned_event.event
    event_type = str(event["event_type"])
    trace_id = str(event["trace_id"])
    order_id = event.get("order_id")
    customer_id = event.get("customer_id")
    payment_id = event.get("payment_id")

    generation_started = time.monotonic()
    try:
        validator.validate_event(event)
    except SchemaValidationError as exc:
        metrics.record_schema_failure(event_type)
        logger.log(
            "ERROR",
            "Schema validation failed",
            component="validation",
            event_type=event_type,
            schema_ref=exc.schema_ref,
            validation_errors=exc.errors,
            trace_id=trace_id,
            order_id=order_id,
            customer_id=customer_id,
            payment_id=payment_id,
            run_id=config.run_id,
        )
        emit_technical_event(
            config=config,
            validator=validator,
            publisher=publisher,
            logger=logger,
            metrics=metrics,
            event_type="schema_validation_failed",
            sequence=sequence,
            trace_id=trace_id,
            order_id=str(order_id) if order_id else None,
            customer_id=str(customer_id) if customer_id else None,
            payment_id=str(payment_id) if payment_id else None,
            payload={
                "failed_event_type": event_type,
                "schema_ref": exc.schema_ref,
                "validation_errors": exc.errors,
            },
        )
        return False

    metrics.record_generation_duration(event_type, time.monotonic() - generation_started)

    try:
        latency = publisher.publish(
            topic=planned_event.topic,
            key=str(event["partition_key"]),
            event=event,
        )
    except PublishError as exc:
        metrics.record_publish_failure(
            event_type=event_type,
            topic=exc.topic,
            error_class=exc.error_class,
        )
        logger.log(
            "ERROR",
            "Kafka publish failed",
            component="publisher",
            event_type=event_type,
            kafka_topic=exc.topic,
            trace_id=trace_id,
            order_id=order_id,
            customer_id=customer_id,
            payment_id=payment_id,
            run_id=config.run_id,
            error_class=exc.error_class,
            detail=exc.detail,
            status="retry_exhausted",
        )
        emit_technical_event(
            config=config,
            validator=validator,
            publisher=publisher,
            logger=logger,
            metrics=metrics,
            event_type="retry_exhausted",
            sequence=sequence + 1,
            trace_id=trace_id,
            order_id=str(order_id) if order_id else None,
            customer_id=str(customer_id) if customer_id else None,
            payment_id=str(payment_id) if payment_id else None,
            payload={
                "failed_event_type": event_type,
                "topic": exc.topic,
                "error_class": exc.error_class,
                "detail": exc.detail,
                "retry_count": config.kafka.manual_retries,
            },
        )
        return False

    metrics.record_publish_success(event_type=event_type, topic=planned_event.topic, latency_seconds=latency)
    payload = event["payload"]
    log_level = planned_event.log_level
    if event_type == "payment_failed":
        metrics.record_payment_failure(str(payload["failure_reason_group"]))
    logger.log(
        log_level,
        "Business event emitted",
        component=planned_event.component,
        event_type=event_type,
        event_version=event["event_version"],
        kafka_topic=planned_event.topic,
        trace_id=trace_id,
        order_id=order_id,
        customer_id=customer_id,
        session_id=event.get("session_id"),
        payment_id=payment_id,
        run_id=config.run_id,
        status="published",
        latency_ms=round(latency * 1000, 2),
        reason_code=payload.get("failure_reason_code"),
        region=payload.get("region"),
        channel=payload.get("channel"),
        customer_segment=payload.get("customer_segment"),
        amount=payload.get("grand_total", payload.get("amount")),
    )
    return True


def main() -> None:
    global RUNNING
    signal.signal(signal.SIGTERM, _handle_signal)
    signal.signal(signal.SIGINT, _handle_signal)

    config = load_config()
    logger = JsonLogger(
        service=config.producer_service,
        environment=config.environment,
        log_level=config.log_level,
    )
    metrics = Metrics(config.metrics_port)
    metrics.start(
        environment=config.environment,
        scenario_profile=config.scenario_profile,
        failure_profile=config.failure_profile,
    )
    health_state = HealthState()
    start_health_server(config.health_port, health_state)
    validator = SchemaValidator(config.schema_root)
    publisher = KafkaPublisher(config.kafka)
    simulator = OrderLifecycleSimulator(config)
    health_state.mark_ready()

    event_counts: Counter[str] = Counter()
    publish_failures = 0
    successful_events = 0
    technical_sequence = 1_000_000
    interval = 1.0 / config.order_rate_per_second
    last_backpressure_emit = 0.0

    logger.log(
        "INFO",
        "Order generator started",
        component="runtime",
        run_id=config.run_id,
        seed=config.seed,
        scenario_profile=config.scenario_profile,
        failure_profile=config.failure_profile,
        order_rate_per_second=config.order_rate_per_second,
        order_lifecycle_topic=config.topics.order_lifecycle,
        payment_events_topic=config.topics.payment_events,
        technical_events_topic=config.topics.technical_events,
        metrics_port=config.metrics_port,
        health_port=config.health_port,
    )

    while RUNNING:
        cycle_started = time.monotonic()
        batch: LifecycleBatch = simulator.simulate_order_lifecycle()
        metrics.record_order_created(batch.order_amount, batch.active_sessions)
        for planned_event in batch.events:
            technical_sequence += 10
            success = process_planned_event(
                config=config,
                planned_event=planned_event,
                validator=validator,
                publisher=publisher,
                logger=logger,
                metrics=metrics,
                sequence=technical_sequence,
            )
            if success:
                successful_events += 1
                event_counts[str(planned_event.event["event_type"])] += 1
            else:
                publish_failures += 1

        if successful_events and successful_events % config.emit_summary_every_n == 0:
            logger.log(
                "INFO",
                "Generator summary",
                component="runtime",
                run_id=config.run_id,
                published_events=successful_events,
                event_counts=dict(event_counts),
                publish_failures=publish_failures,
                active_sessions=batch.active_sessions,
            )

        elapsed = time.monotonic() - cycle_started
        blocked_seconds = max(elapsed - interval, 0.0)
        if blocked_seconds > 0:
            metrics.record_backpressure(blocked_seconds)
            now = time.monotonic()
            if now - last_backpressure_emit >= 30:
                technical_sequence += 10
                emit_technical_event(
                    config=config,
                    validator=validator,
                    publisher=publisher,
                    logger=logger,
                    metrics=metrics,
                    event_type="generator_backpressure",
                    sequence=technical_sequence,
                    trace_id=config.run_id,
                    payload={
                        "blocked_seconds": round(blocked_seconds, 6),
                        "target_interval_seconds": round(interval, 6),
                        "queue_depth": 1,
                    },
                )
                last_backpressure_emit = now
        else:
            metrics.clear_backpressure()

        sleep_for = interval - elapsed
        if sleep_for > 0:
            time.sleep(sleep_for)

    health_state.stop()
    publisher.close()
    logger.log(
        "INFO",
        "Order generator stopped",
        component="runtime",
        run_id=config.run_id,
        published_events=successful_events,
        event_counts=dict(event_counts),
        publish_failures=publish_failures,
    )
