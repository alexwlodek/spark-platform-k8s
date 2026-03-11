from __future__ import annotations

import json
import sys
import threading
import time
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, HTTPServer
from typing import Any

from prometheus_client import Counter, Gauge, Histogram, Info, start_http_server


ORDERS_CREATED_TOTAL = Counter(
    "order_generator_orders_created_total",
    "Total number of order_created events generated",
)
ORDER_AMOUNT_USD = Histogram(
    "order_generator_order_amount_usd",
    "Distribution of generated order values in USD",
    buckets=(10, 25, 50, 75, 100, 150, 250, 400, 600, 900, 1500),
)
EVENTS_PUBLISHED_TOTAL = Counter(
    "order_generator_events_published_total",
    "Published events by event type, topic, and result",
    ["event_type", "topic", "result"],
)
PUBLISH_LATENCY_SECONDS = Histogram(
    "order_generator_publish_latency_seconds",
    "Kafka publish latency by topic",
    ["topic"],
    buckets=(0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2, 5, 10),
)
PUBLISH_FAILURES_TOTAL = Counter(
    "order_generator_publish_failures_total",
    "Kafka publish failures by topic and error class",
    ["topic", "error_class"],
)
PAYMENT_FAILURES_TOTAL = Counter(
    "order_generator_payment_failures_total",
    "Payment failures grouped by failure reason",
    ["reason_group"],
)
INVENTORY_SHORTAGES_TOTAL = Counter(
    "order_generator_inventory_shortages_total",
    "Inventory shortages grouped by region",
    ["region"],
)
SHIPMENTS_DELAYED_TOTAL = Counter(
    "order_generator_shipments_delayed_total",
    "Shipment delays grouped by carrier and region",
    ["carrier", "region"],
)
REFUNDS_COMPLETED_TOTAL = Counter(
    "order_generator_refunds_completed_total",
    "Completed refunds grouped by reason code",
    ["reason_code"],
)
SUSPICIOUS_ORDERS_TOTAL = Counter(
    "order_generator_suspicious_orders_total",
    "Suspicious orders grouped by action",
    ["action"],
)
ORDERS_CANCELLED_TOTAL = Counter(
    "order_generator_orders_cancelled_total",
    "Cancelled orders grouped by lifecycle stage",
    ["stage"],
)
SCHEMA_VALIDATION_FAILURES_TOTAL = Counter(
    "order_generator_schema_validation_failures_total",
    "Schema validation failures by event type",
    ["event_type"],
)
MALFORMED_EVENTS_TOTAL = Counter(
    "order_generator_malformed_events_total",
    "Malformed events grouped by reason",
    ["reason"],
)
GENERATION_DURATION_SECONDS = Histogram(
    "order_generator_generation_duration_seconds",
    "Duration to generate one business event",
    ["event_type"],
    buckets=(0.0005, 0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25),
)
ACTIVE_SESSIONS = Gauge(
    "order_generator_active_sessions",
    "Approximate active sessions represented in the recent workload",
)
BACKPRESSURE_DEPTH = Gauge(
    "order_generator_backpressure_depth",
    "Positive values indicate the generator is slower than its configured interval",
)
LAST_SUCCESSFUL_PUBLISH_TIMESTAMP_SECONDS = Gauge(
    "order_generator_last_successful_publish_timestamp_seconds",
    "Unix timestamp of the last successful Kafka publish",
)
RUN_INFO = Info(
    "order_generator_run",
    "Static metadata about the current generator process",
)


class JsonLogger:
    LEVELS = {"DEBUG": 10, "INFO": 20, "WARN": 30, "ERROR": 40}

    def __init__(self, *, service: str, environment: str, log_level: str):
        self.service = service
        self.environment = environment
        self.threshold = self.LEVELS.get(log_level.upper(), 20)

    def log(self, level: str, message: str, **fields: Any) -> None:
        normalized_level = level.upper()
        if self.LEVELS.get(normalized_level, 20) < self.threshold:
            return

        payload: dict[str, Any] = {
            "ts": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
            "level": normalized_level,
            "service": self.service,
            "environment": self.environment,
            "message": message,
        }
        payload.update({key: value for key, value in fields.items() if value is not None})
        print(json.dumps(payload, separators=(",", ":")), file=sys.stdout, flush=True)


class Metrics:
    def __init__(self, port: int):
        self.port = port

    def start(self, *, environment: str, scenario_profile: str, failure_profile: str) -> None:
        start_http_server(self.port)
        RUN_INFO.info(
            {
                "environment": environment,
                "scenario_profile": scenario_profile,
                "failure_profile": failure_profile,
            }
        )

    def record_order_created(self, order_amount: float, active_sessions: int) -> None:
        ORDERS_CREATED_TOTAL.inc()
        ORDER_AMOUNT_USD.observe(order_amount)
        ACTIVE_SESSIONS.set(active_sessions)

    def record_publish_success(self, *, event_type: str, topic: str, latency_seconds: float) -> None:
        EVENTS_PUBLISHED_TOTAL.labels(event_type=event_type, topic=topic, result="success").inc()
        PUBLISH_LATENCY_SECONDS.labels(topic=topic).observe(latency_seconds)
        LAST_SUCCESSFUL_PUBLISH_TIMESTAMP_SECONDS.set(time.time())

    def record_publish_failure(self, *, event_type: str, topic: str, error_class: str) -> None:
        EVENTS_PUBLISHED_TOTAL.labels(event_type=event_type, topic=topic, result="failure").inc()
        PUBLISH_FAILURES_TOTAL.labels(topic=topic, error_class=error_class).inc()

    def record_payment_failure(self, reason_group: str) -> None:
        PAYMENT_FAILURES_TOTAL.labels(reason_group=reason_group).inc()

    def record_inventory_shortage(self, region: str) -> None:
        INVENTORY_SHORTAGES_TOTAL.labels(region=region or "unknown").inc()

    def record_shipment_delay(self, carrier: str, region: str) -> None:
        SHIPMENTS_DELAYED_TOTAL.labels(carrier=carrier or "unknown", region=region or "unknown").inc()

    def record_refund_completed(self, reason_code: str) -> None:
        REFUNDS_COMPLETED_TOTAL.labels(reason_code=reason_code or "unknown").inc()

    def record_suspicious_order(self, action: str) -> None:
        SUSPICIOUS_ORDERS_TOTAL.labels(action=action or "unknown").inc()

    def record_order_cancelled(self, stage: str) -> None:
        ORDERS_CANCELLED_TOTAL.labels(stage=stage or "unknown").inc()

    def record_schema_failure(self, event_type: str) -> None:
        SCHEMA_VALIDATION_FAILURES_TOTAL.labels(event_type=event_type).inc()

    def record_malformed_event(self, reason: str) -> None:
        MALFORMED_EVENTS_TOTAL.labels(reason=reason).inc()

    def record_generation_duration(self, event_type: str, duration_seconds: float) -> None:
        GENERATION_DURATION_SECONDS.labels(event_type=event_type).observe(duration_seconds)

    def record_backpressure(self, blocked_seconds: float) -> None:
        BACKPRESSURE_DEPTH.set(blocked_seconds)

    def clear_backpressure(self) -> None:
        BACKPRESSURE_DEPTH.set(0.0)


class HealthState:
    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._live = True
        self._ready = False

    def mark_ready(self) -> None:
        with self._lock:
            self._ready = True

    def mark_not_ready(self) -> None:
        with self._lock:
            self._ready = False

    def stop(self) -> None:
        with self._lock:
            self._live = False
            self._ready = False

    def snapshot(self) -> tuple[bool, bool]:
        with self._lock:
            return self._live, self._ready


def start_health_server(port: int, state: HealthState) -> None:
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self) -> None:  # noqa: N802
            live, ready = state.snapshot()
            if self.path == "/healthz":
                self.send_response(200 if live else 503)
                self.end_headers()
                self.wfile.write(b"ok" if live else b"stopping")
                return

            if self.path == "/readyz":
                self.send_response(200 if ready else 503)
                self.end_headers()
                self.wfile.write(b"ready" if ready else b"not-ready")
                return

            self.send_response(404)
            self.end_headers()

        def log_message(self, _format: str, *_args: object) -> None:
            return

    server = HTTPServer(("0.0.0.0", port), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
