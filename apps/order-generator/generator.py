from __future__ import annotations

import json
import os
import random
import signal
import time
import uuid
from datetime import datetime, timezone

from kafka import KafkaProducer


RUNNING = True


def _handle_signal(signum: int, _frame: object) -> None:
    global RUNNING
    RUNNING = False
    print(f"[order-generator] received signal={signum}, stopping")


def env_float(name: str, default: float) -> float:
    value = os.getenv(name)
    if value is None:
        return default
    return float(value)


def make_event(min_amount: float, max_amount: float) -> dict[str, object]:
    amount = round(random.uniform(min_amount, max_amount), 2)
    items = random.randint(1, 5)
    return {
        "event_id": str(uuid.uuid4()),
        "event_time": datetime.now(timezone.utc).isoformat(),
        "order_id": f"ord-{random.randint(100000, 999999)}",
        "customer_id": f"cust-{random.randint(1, 5000)}",
        "items": items,
        "amount": amount,
        "currency": "USD",
        "region": random.choice(["us-east-1", "us-west-2", "eu-west-1"]),
    }


def main() -> None:
    signal.signal(signal.SIGTERM, _handle_signal)
    signal.signal(signal.SIGINT, _handle_signal)

    bootstrap_servers = os.getenv("KAFKA_BOOTSTRAP_SERVERS", "streaming-kafka.apps.svc.cluster.local:9092")
    topic = os.getenv("KAFKA_TOPIC", "orders")
    acks = os.getenv("KAFKA_ACKS", "1")
    compression_type = os.getenv("KAFKA_COMPRESSION_TYPE", "none")
    rate = max(env_float("ORDER_RATE_PER_SECOND", 20.0), 0.1)
    min_amount = env_float("ORDER_MIN_AMOUNT", 10.0)
    max_amount = env_float("ORDER_MAX_AMOUNT", 500.0)

    producer = KafkaProducer(
        bootstrap_servers=[s.strip() for s in bootstrap_servers.split(",") if s.strip()],
        acks=acks,
        compression_type=compression_type if compression_type != "none" else None,
        linger_ms=10,
        retries=20,
        value_serializer=lambda payload: json.dumps(payload).encode("utf-8"),
    )

    interval = 1.0 / rate
    sent = 0
    print(
        "[order-generator] started "
        f"topic={topic} bootstrap_servers={bootstrap_servers} rate={rate:.2f}/s amount={min_amount}-{max_amount}"
    )

    while RUNNING:
        started = time.time()
        event = make_event(min_amount, max_amount)
        producer.send(topic, event)
        sent += 1

        if sent % 100 == 0:
            print(f"[order-generator] sent={sent} last_order={event['order_id']} amount={event['amount']}")

        sleep_for = interval - (time.time() - started)
        if sleep_for > 0:
            time.sleep(sleep_for)

    producer.flush(timeout=10)
    producer.close()
    print(f"[order-generator] shutdown complete sent_total={sent}")


if __name__ == "__main__":
    main()
