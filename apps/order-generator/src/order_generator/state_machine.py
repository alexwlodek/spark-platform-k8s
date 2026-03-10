from __future__ import annotations

import random
from collections import deque
from dataclasses import dataclass
from datetime import timedelta

from .config import AppConfig
from .envelope import build_event, deterministic_id, utc_now
from .reference_data import (
    CAMPAIGNS_BY_CHANNEL,
    CHANNEL_WEIGHTS_BY_SEGMENT,
    DEVICE_WEIGHTS_BY_CHANNEL,
    PAYMENT_METHODS_BY_SEGMENT,
    PRODUCT_CATALOG,
    Customer,
    build_customers,
    weighted_choice,
)


@dataclass(slots=True)
class PlannedEvent:
    topic: str
    component: str
    log_level: str
    event: dict[str, object]


@dataclass(slots=True)
class LifecycleBatch:
    events: list[PlannedEvent]
    active_sessions: int
    order_amount: float


class OrderLifecycleSimulator:
    def __init__(self, config: AppConfig):
        self.config = config
        self.randomizer = random.Random(config.seed)
        self.customers = build_customers(config.seed)
        self.products = PRODUCT_CATALOG
        self.sequence = 0
        self.recent_sessions: deque[str] = deque(maxlen=256)

    def simulate_order_lifecycle(self) -> LifecycleBatch:
        self.sequence += 1
        sequence = self.sequence
        customer = self.randomizer.choice(self.customers)
        trace_id = deterministic_id("trc", self.config.run_id, sequence, "trace")
        order_id = f"ord-{sequence:06d}"
        session_id = deterministic_id("ses", self.config.run_id, sequence, "session")
        payment_id = f"pay-{sequence:06d}"

        channel = weighted_choice(self.randomizer, CHANNEL_WEIGHTS_BY_SEGMENT[customer.segment])
        device_type = weighted_choice(self.randomizer, DEVICE_WEIGHTS_BY_CHANNEL[channel])
        campaign_id = self.randomizer.choice(CAMPAIGNS_BY_CHANNEL[channel])
        payment_method = self._pick_payment_method(customer)
        items, subtotal = self._build_order_items()
        discount_total = round(subtotal * self._discount_rate(customer.segment, channel), 2)
        discounted_subtotal = max(subtotal - discount_total, 1.0)
        tax_total = round(discounted_subtotal * self._tax_rate(customer.region), 2)
        shipping_total = round(self._shipping_cost(channel, subtotal), 2)
        grand_total = round(discounted_subtotal + tax_total + shipping_total, 2)
        created_at = utc_now()
        validated_at = created_at + timedelta(milliseconds=self.randomizer.randint(20, 180))
        paid_at = validated_at + timedelta(milliseconds=self.randomizer.randint(40, 320))

        self.recent_sessions.append(session_id)

        order_created = build_event(
            event_type="order_created",
            event_version=1,
            schema_ref="schemas/business/order_created.v1.json",
            producer=self.config.producer_service,
            environment=self.config.environment,
            run_id=self.config.run_id,
            trace_id=trace_id,
            partition_key=order_id,
            sequence=sequence * 10 + 1,
            event_time=created_at,
            order_id=order_id,
            customer_id=customer.customer_id,
            session_id=session_id,
            payload={
                "channel": channel,
                "device_type": device_type,
                "campaign_id": campaign_id,
                "region": customer.region,
                "country": customer.country,
                "currency": "USD",
                "customer_segment": customer.segment,
                "customer_tenure_days": customer.tenure_days,
                "items": items,
                "subtotal": round(subtotal, 2),
                "discount_total": discount_total,
                "tax_total": tax_total,
                "shipping_total": shipping_total,
                "grand_total": grand_total,
            },
        )

        order_validated = build_event(
            event_type="order_validated",
            event_version=1,
            schema_ref="schemas/business/order_validated.v1.json",
            producer=self.config.producer_service,
            environment=self.config.environment,
            run_id=self.config.run_id,
            trace_id=trace_id,
            partition_key=order_id,
            sequence=sequence * 10 + 2,
            event_time=validated_at,
            order_id=order_id,
            customer_id=customer.customer_id,
            session_id=session_id,
            payload={
                "channel": channel,
                "region": customer.region,
                "currency": "USD",
                "customer_segment": customer.segment,
                "validation_status": "validated",
                "rule_results": [
                    {"rule_code": "amount_within_bounds", "passed": True},
                    {"rule_code": "region_supported", "passed": True},
                    {"rule_code": "items_present", "passed": True},
                ],
                "validated_grand_total": grand_total,
            },
        )

        payment_failed, reason_code, reason_group = self._payment_outcome(customer)
        payment_event_type = "payment_failed" if payment_failed else "payment_authorized"
        payment_schema = f"schemas/business/{payment_event_type}.v1.json"
        payment_payload: dict[str, object] = {
            "amount": grand_total,
            "currency": "USD",
            "payment_method": payment_method,
            "provider": self._payment_provider(payment_method),
            "attempt_no": 1,
            "channel": channel,
            "region": customer.region,
            "customer_segment": customer.segment,
        }
        if payment_failed:
            payment_payload.update(
                {
                    "failure_reason_code": reason_code,
                    "failure_reason_group": reason_group,
                    "is_retryable": reason_group in {"issuer_decline", "transient"},
                }
            )
        else:
            payment_payload["auth_code"] = deterministic_id("auth", self.config.run_id, sequence, "payment")[-8:]

        payment_event = build_event(
            event_type=payment_event_type,
            event_version=1,
            schema_ref=payment_schema,
            producer=self.config.producer_service,
            environment=self.config.environment,
            run_id=self.config.run_id,
            trace_id=trace_id,
            partition_key=order_id,
            sequence=sequence * 10 + 3,
            event_time=paid_at,
            order_id=order_id,
            customer_id=customer.customer_id,
            session_id=session_id,
            payment_id=payment_id,
            payload=payment_payload,
        )

        events = [
            PlannedEvent(
                topic=self.config.topics.order_lifecycle,
                component="orders",
                log_level="INFO",
                event=order_created,
            ),
            PlannedEvent(
                topic=self.config.topics.order_lifecycle,
                component="orders",
                log_level="INFO",
                event=order_validated,
            ),
            PlannedEvent(
                topic=self.config.topics.payment_events,
                component="payments",
                log_level="WARN" if payment_failed else "INFO",
                event=payment_event,
            ),
        ]
        return LifecycleBatch(
            events=events,
            active_sessions=len(set(self.recent_sessions)),
            order_amount=grand_total,
        )

    def _build_order_items(self) -> tuple[list[dict[str, object]], float]:
        attempts = 0
        while True:
            attempts += 1
            items: list[dict[str, object]] = []
            subtotal = 0.0
            items_count = self.randomizer.randint(self.config.min_items, self.config.max_items)
            weighted_products = tuple((product, product.popularity_weight) for product in self.products)
            for _index in range(items_count):
                product = weighted_choice(self.randomizer, weighted_products)
                qty = 1 if self.randomizer.random() < 0.78 else self.randomizer.randint(2, 3)
                subtotal += product.base_price * qty
                items.append(
                    {
                        "sku": product.sku,
                        "category": product.category,
                        "brand": product.brand,
                        "qty": qty,
                        "unit_price": product.base_price,
                        "inventory_class": product.inventory_class,
                        "seasonality_tag": product.seasonality_tag,
                    }
                )
            if self.config.min_amount <= subtotal <= self.config.max_amount:
                return items, subtotal
            if attempts >= 8:
                return items, subtotal

    def _pick_payment_method(self, customer: Customer) -> str:
        preferred_bias = 0.55
        methods = []
        for method, weight in PAYMENT_METHODS_BY_SEGMENT[customer.segment]:
            adjusted_weight = weight + preferred_bias if method == customer.preferred_payment_method else weight
            methods.append((method, adjusted_weight))
        return weighted_choice(self.randomizer, tuple(methods))

    def _payment_outcome(self, customer: Customer) -> tuple[bool, str | None, str | None]:
        risk_multiplier = {"low": 0.7, "medium": 1.0, "high": 1.5}[customer.risk_profile]
        failure_rate = min(self.config.payment_failure_rate * risk_multiplier, 0.85)
        if self.randomizer.random() >= failure_rate:
            return False, None, None

        failures = (
            ("insufficient_funds", "issuer_decline", 0.36),
            ("3ds_timeout", "transient", 0.18),
            ("suspected_fraud", "risk", 0.16),
            ("avs_mismatch", "issuer_decline", 0.14),
            ("processor_timeout", "transient", 0.16),
        )
        options = tuple(((code, group), weight) for code, group, weight in failures)
        reason_code, reason_group = weighted_choice(self.randomizer, options)
        return True, reason_code, reason_group

    def _discount_rate(self, segment: str, channel: str) -> float:
        segment_discount = {"new": 0.04, "loyal": 0.07, "vip": 0.09, "bargain": 0.12}[segment]
        channel_bonus = {"web": 0.02, "mobile": 0.01, "marketplace": 0.00, "b2b": 0.03}[channel]
        return min(segment_discount + channel_bonus, 0.18)

    def _tax_rate(self, region: str) -> float:
        return {"eu-central-1": 0.19, "eu-west-1": 0.21, "us-west-2": 0.08}.get(region, 0.1)

    def _shipping_cost(self, channel: str, subtotal: float) -> float:
        if subtotal >= 150:
            return 0.0
        return {"web": 6.99, "mobile": 4.99, "marketplace": 7.99, "b2b": 9.99}[channel]

    def _payment_provider(self, payment_method: str) -> str:
        return {
            "card": "adyen-sim",
            "paypal": "paypal-sim",
            "wallet": "wallet-sim",
            "buy_now_pay_later": "bnpl-sim",
            "invoice": "erp-sim",
        }[payment_method]
