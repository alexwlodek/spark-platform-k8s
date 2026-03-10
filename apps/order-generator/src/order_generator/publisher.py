from __future__ import annotations

import json
import time

from kafka import KafkaProducer
from kafka.errors import KafkaError, KafkaTimeoutError, NoBrokersAvailable

from .config import KafkaConfig


class PublishError(Exception):
    def __init__(self, *, topic: str, event_type: str, error_class: str, detail: str):
        self.topic = topic
        self.event_type = event_type
        self.error_class = error_class
        self.detail = detail
        super().__init__(f"{topic} {event_type} {error_class}: {detail}")


class KafkaPublisher:
    def __init__(self, config: KafkaConfig):
        self.config = config
        self._producer = self._build_producer()

    def _build_producer(self) -> KafkaProducer:
        normalized_acks: int | str
        if self.config.acks.strip().lower() == "all":
            normalized_acks = "all"
        else:
            normalized_acks = int(self.config.acks)

        return KafkaProducer(
            bootstrap_servers=[item.strip() for item in self.config.bootstrap_servers.split(",") if item.strip()],
            acks=normalized_acks,
            compression_type=self.config.compression_type if self.config.compression_type != "none" else None,
            linger_ms=10,
            retries=50,
            retry_backoff_ms=500,
            max_block_ms=10000,
            request_timeout_ms=30000,
            value_serializer=lambda payload: json.dumps(payload, separators=(",", ":")).encode("utf-8"),
            key_serializer=lambda key: key.encode("utf-8"),
        )

    def publish(self, *, topic: str, key: str, event: dict[str, object]) -> float:
        last_error: Exception | None = None
        for attempt in range(1, self.config.manual_retries + 1):
            started = time.monotonic()
            try:
                future = self._producer.send(
                    topic,
                    key=key,
                    value=event,
                    headers=[
                        ("event_type", str(event["event_type"]).encode("utf-8")),
                        ("event_version", str(event["event_version"]).encode("utf-8")),
                    ],
                )
                future.get(timeout=self.config.publish_timeout_seconds)
                return time.monotonic() - started
            except (KafkaTimeoutError, NoBrokersAvailable, KafkaError) as exc:
                last_error = exc
                self._replace_producer()
                if attempt < self.config.manual_retries:
                    time.sleep(self.config.manual_retry_backoff_seconds)

        error = last_error or RuntimeError("Kafka publish failed")
        raise PublishError(
            topic=topic,
            event_type=str(event["event_type"]),
            error_class=error.__class__.__name__,
            detail=str(error),
        )

    def _replace_producer(self) -> None:
        try:
            self._producer.close(timeout=2)
        except Exception:
            pass
        self._producer = self._build_producer()

    def close(self) -> None:
        self._producer.flush(timeout=10)
        self._producer.close(timeout=10)
