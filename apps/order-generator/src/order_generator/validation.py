from __future__ import annotations

import json
from pathlib import Path

from jsonschema import Draft202012Validator


class SchemaValidationError(Exception):
    def __init__(self, schema_ref: str, errors: list[str]):
        self.schema_ref = schema_ref
        self.errors = errors
        super().__init__(f"{schema_ref}: {'; '.join(errors)}")


class DomainValidationError(Exception):
    def __init__(self, event_type: str, errors: list[str]):
        self.event_type = event_type
        self.errors = errors
        super().__init__(f"{event_type}: {'; '.join(errors)}")


class SchemaValidator:
    def __init__(self, schema_root: Path):
        self.schema_root = schema_root
        self._cache: dict[str, Draft202012Validator] = {}

    def _resolve_ref(self, schema_ref: str) -> str:
        normalized = schema_ref.lstrip("/")
        if normalized.startswith("schemas/"):
            return normalized[len("schemas/") :]
        return normalized

    def _load(self, schema_ref: str) -> Draft202012Validator:
        normalized = self._resolve_ref(schema_ref)
        if normalized not in self._cache:
            path = self.schema_root / normalized
            schema = json.loads(path.read_text(encoding="utf-8"))
            self._cache[normalized] = Draft202012Validator(
                schema,
                format_checker=Draft202012Validator.FORMAT_CHECKER,
            )
        return self._cache[normalized]

    def validate_event(self, event: dict[str, object]) -> None:
        self._validate("envelope/envelope.v1.json", event)
        schema_ref = str(event["schema_ref"])
        self._validate(schema_ref, event)
        self.validate_domain(event)

    def _validate(self, schema_ref: str, event: dict[str, object]) -> None:
        validator = self._load(schema_ref)
        errors = sorted(validator.iter_errors(event), key=lambda item: list(item.path))
        if not errors:
            return
        normalized_errors = []
        for error in errors:
            location = ".".join(str(part) for part in error.absolute_path) or "$"
            normalized_errors.append(f"{location}: {error.message}")
        raise SchemaValidationError(schema_ref=schema_ref, errors=normalized_errors)

    def validate_domain(self, event: dict[str, object]) -> None:
        event_type = str(event["event_type"])
        payload = event.get("payload", {})
        if not isinstance(payload, dict):
            raise DomainValidationError(event_type=event_type, errors=["payload must be an object"])

        errors: list[str] = []
        if event_type == "order_created":
            items = payload.get("items", [])
            if not isinstance(items, list) or not items:
                errors.append("payload.items must contain at least one item")
            grand_total = payload.get("grand_total")
            if not isinstance(grand_total, (int, float)) or grand_total <= 0:
                errors.append("payload.grand_total must be > 0")
        elif event_type in {"payment_authorized", "payment_failed"}:
            amount = payload.get("amount")
            if not isinstance(amount, (int, float)) or amount <= 0:
                errors.append("payload.amount must be > 0")
        elif event_type == "inventory_reserved":
            if int(payload.get("requested_qty", 0)) < int(payload.get("reserved_qty", 0)):
                errors.append("payload.reserved_qty cannot exceed payload.requested_qty")
        elif event_type == "inventory_shortage":
            missing_items = payload.get("missing_items", [])
            if not isinstance(missing_items, list) or not missing_items:
                errors.append("payload.missing_items must contain at least one item")
        elif event_type == "shipment_delayed":
            delayed_minutes = payload.get("delayed_minutes")
            if not isinstance(delayed_minutes, int) or delayed_minutes <= 0:
                errors.append("payload.delayed_minutes must be > 0")
        elif event_type in {"refund_requested", "refund_completed"}:
            requested_amount = payload.get("requested_amount", payload.get("approved_amount"))
            if not isinstance(requested_amount, (int, float)) or requested_amount <= 0:
                errors.append("refund amount must be > 0")
        elif event_type == "suspicious_order_flagged":
            risk_score = payload.get("risk_score")
            if not isinstance(risk_score, (int, float)) or risk_score < 0 or risk_score > 1:
                errors.append("payload.risk_score must be between 0 and 1")

        if errors:
            raise DomainValidationError(event_type=event_type, errors=errors)
