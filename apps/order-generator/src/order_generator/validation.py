from __future__ import annotations

import json
from pathlib import Path

from jsonschema import Draft202012Validator


class SchemaValidationError(Exception):
    def __init__(self, schema_ref: str, errors: list[str]):
        self.schema_ref = schema_ref
        self.errors = errors
        super().__init__(f"{schema_ref}: {'; '.join(errors)}")


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
