from __future__ import annotations

import uuid
from datetime import datetime, timezone


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def isoformat(value: datetime) -> str:
    return value.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def deterministic_id(prefix: str, run_id: str, sequence: int, name: str) -> str:
    value = uuid.uuid5(uuid.NAMESPACE_URL, f"{run_id}:{sequence}:{name}")
    return f"{prefix}-{value}"


def build_event(
    *,
    event_type: str,
    event_version: int,
    schema_ref: str,
    producer: str,
    environment: str,
    run_id: str,
    trace_id: str,
    partition_key: str,
    sequence: int,
    payload: dict[str, object],
    event_time: datetime | None = None,
    order_id: str | None = None,
    customer_id: str | None = None,
    session_id: str | None = None,
    payment_id: str | None = None,
) -> dict[str, object]:
    timestamp = event_time or utc_now()
    event: dict[str, object] = {
        "event_id": deterministic_id("evt", run_id, sequence, event_type),
        "event_type": event_type,
        "event_version": event_version,
        "event_time": isoformat(timestamp),
        "producer": producer,
        "environment": environment,
        "run_id": run_id,
        "trace_id": trace_id,
        "schema_ref": schema_ref,
        "partition_key": partition_key,
        "idempotency_key": f"{partition_key}:{event_type}:{event_version}",
        "payload": payload,
    }
    if order_id is not None:
        event["order_id"] = order_id
    if customer_id is not None:
        event["customer_id"] = customer_id
    if session_id is not None:
        event["session_id"] = session_id
    if payment_id is not None:
        event["payment_id"] = payment_id
    return event
