from __future__ import annotations

import os
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path


def env_str(name: str, default: str) -> str:
    value = os.getenv(name)
    if value is None:
        return default
    return value.strip() or default


def env_int(name: str, default: int) -> int:
    value = os.getenv(name)
    if value is None:
        return default
    return int(value)


def env_float(name: str, default: float) -> float:
    value = os.getenv(name)
    if value is None:
        return default
    return float(value)


@dataclass(frozen=True)
class TopicsConfig:
    order_lifecycle: str
    payment_events: str
    technical_events: str


@dataclass(frozen=True)
class KafkaConfig:
    bootstrap_servers: str
    acks: str
    compression_type: str
    publish_timeout_seconds: float
    manual_retries: int
    manual_retry_backoff_seconds: float


@dataclass(frozen=True)
class AppConfig:
    environment: str
    producer_service: str
    run_id: str
    seed: int
    scenario_profile: str
    log_level: str
    metrics_port: int
    health_port: int
    emit_summary_every_n: int
    order_rate_per_second: float
    min_amount: float
    max_amount: float
    min_items: int
    max_items: int
    payment_failure_rate: float
    failure_profile: str
    kafka: KafkaConfig
    topics: TopicsConfig
    schema_root: Path


DEFAULT_FAILURE_RATES = {
    "balanced": 0.12,
    "peak": 0.18,
    "unhappy": 0.24,
}


def default_schema_root() -> Path:
    return Path(__file__).resolve().parents[2] / "schemas"


def load_config() -> AppConfig:
    seed = env_int("SEED", 42)
    run_id = env_str(
        "RUN_ID",
        f"run-{datetime.now(timezone.utc):%Y%m%d-%H%M%S}-seed{seed}",
    )
    scenario_profile = env_str("SCENARIO_PROFILE", "balanced")
    failure_profile = env_str("FAILURE_PROFILE", scenario_profile)
    default_failure_rate = DEFAULT_FAILURE_RATES.get(failure_profile, DEFAULT_FAILURE_RATES["balanced"])

    return AppConfig(
        environment=env_str("ENVIRONMENT", "dev"),
        producer_service=env_str("PRODUCER_SERVICE", "order-generator"),
        run_id=run_id,
        seed=seed,
        scenario_profile=scenario_profile,
        log_level=env_str("LOG_LEVEL", "INFO"),
        metrics_port=env_int("METRICS_PORT", 9108),
        health_port=env_int("HEALTH_PORT", 8081),
        emit_summary_every_n=max(env_int("EMIT_SUMMARY_EVERY_N", 25), 1),
        order_rate_per_second=max(env_float("ORDER_RATE_PER_SECOND", 20.0), 0.1),
        min_amount=max(env_float("ORDER_MIN_AMOUNT", 10.0), 1.0),
        max_amount=max(env_float("ORDER_MAX_AMOUNT", 500.0), 5.0),
        min_items=max(env_int("ORDER_MIN_ITEMS", 1), 1),
        max_items=max(env_int("ORDER_MAX_ITEMS", 4), 1),
        payment_failure_rate=min(max(env_float("PAYMENT_FAILURE_RATE", default_failure_rate), 0.0), 0.95),
        failure_profile=failure_profile,
        kafka=KafkaConfig(
            bootstrap_servers=env_str(
                "KAFKA_BOOTSTRAP_SERVERS",
                "streaming-kafka.apps.svc.cluster.local:9092",
            ),
            acks=env_str("KAFKA_ACKS", "all"),
            compression_type=env_str("KAFKA_COMPRESSION_TYPE", "none"),
            publish_timeout_seconds=max(env_float("KAFKA_PUBLISH_TIMEOUT_SECONDS", 10.0), 1.0),
            manual_retries=max(env_int("KAFKA_MANUAL_RETRIES", 3), 1),
            manual_retry_backoff_seconds=max(env_float("KAFKA_RETRY_BACKOFF_SECONDS", 1.0), 0.1),
        ),
        topics=TopicsConfig(
            order_lifecycle=env_str("TOPIC_ORDER_LIFECYCLE", env_str("KAFKA_TOPIC", "commerce.order.lifecycle.v1")),
            payment_events=env_str("TOPIC_PAYMENT_EVENTS", "commerce.payment.events.v1"),
            technical_events=env_str("TOPIC_TECHNICAL_EVENTS", "commerce.generator.technical.v1"),
        ),
        schema_root=Path(env_str("SCHEMA_ROOT", str(default_schema_root()))),
    )
