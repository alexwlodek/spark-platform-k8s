from __future__ import annotations

import random
from collections import deque
from dataclasses import dataclass
from datetime import datetime, timedelta

from .config import AppConfig
from .envelope import build_event, deterministic_id, isoformat, utc_now
from .reference_data import (
    CAMPAIGNS_BY_CHANNEL,
    CARRIERS_BY_REGION,
    CHANNEL_WEIGHTS_BY_SEGMENT,
    DEVICE_WEIGHTS_BY_CHANNEL,
    FRAUD_RULES,
    PAYMENT_METHODS_BY_SEGMENT,
    PRODUCT_CATALOG,
    REFUND_REASONS,
    SERVICE_LEVELS_BY_CHANNEL,
    SHIPMENT_DELAY_REASONS,
    SHORTAGE_REASONS,
    WAREHOUSES_BY_REGION,
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


@dataclass(slots=True)
class FraudDecision:
    flagged: bool
    risk_score: float
    rules_triggered: list[str]
    action: str | None
    review_status: str | None


@dataclass(slots=True)
class InventoryDecision:
    shortage: bool
    reservation_id: str
    warehouse_id: str
    requested_qty: int
    reserved_qty: int
    stock_after: int
    shortage_reason_code: str | None
    missing_items: list[dict[str, object]]


@dataclass(slots=True)
class ShipmentDecision:
    shipment_id: str
    carrier: str
    service_level: str
    promised_delivery_at: datetime
    estimated_delivery_at: datetime
    delayed: bool
    delay_reason_code: str | None
    delayed_minutes: int


@dataclass(slots=True)
class RefundDecision:
    refund_requested: bool
    refund_id: str
    reason_code: str
    refund_type: str
    requested_amount: float
    approved_amount: float
    refund_method: str


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
        reservation_id = f"res-{sequence:06d}"
        shipment_id = f"shp-{sequence:06d}"
        refund_id = f"rfd-{sequence:06d}"
        signal_id = f"sig-{sequence:06d}"

        channel = weighted_choice(self.randomizer, CHANNEL_WEIGHTS_BY_SEGMENT[customer.segment])
        device_type = weighted_choice(self.randomizer, DEVICE_WEIGHTS_BY_CHANNEL[channel])
        campaign_id = self.randomizer.choice(CAMPAIGNS_BY_CHANNEL[channel])
        payment_method = self._pick_payment_method(customer)
        items, subtotal = self._build_order_items()
        total_qty = sum(int(item["qty"]) for item in items)
        discount_total = round(subtotal * self._discount_rate(customer.segment, channel), 2)
        discounted_subtotal = max(subtotal - discount_total, 1.0)
        tax_total = round(discounted_subtotal * self._tax_rate(customer.region), 2)
        shipping_total = round(self._shipping_cost(channel, subtotal), 2)
        grand_total = round(discounted_subtotal + tax_total + shipping_total, 2)
        created_at = utc_now()
        validated_at = created_at + timedelta(milliseconds=self.randomizer.randint(20, 180))
        risk_at = validated_at + timedelta(milliseconds=self.randomizer.randint(10, 80))
        paid_at = risk_at + timedelta(milliseconds=self.randomizer.randint(40, 320))
        inventory_at = paid_at + timedelta(milliseconds=self.randomizer.randint(25, 140))
        shipped_at = inventory_at + timedelta(milliseconds=self.randomizer.randint(180, 600))

        self.recent_sessions.append(session_id)

        events: list[PlannedEvent] = [
            PlannedEvent(
                topic=self.config.topics.order_lifecycle,
                component="orders",
                log_level="INFO",
                event=build_event(
                    event_type="order_created",
                    event_version=1,
                    schema_ref="schemas/business/order_created.v1.json",
                    producer=self.config.producer_service,
                    environment=self.config.environment,
                    run_id=self.config.run_id,
                    trace_id=trace_id,
                    partition_key=order_id,
                    sequence=sequence * 20 + 1,
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
                ),
            ),
            PlannedEvent(
                topic=self.config.topics.order_lifecycle,
                component="orders",
                log_level="INFO",
                event=build_event(
                    event_type="order_validated",
                    event_version=1,
                    schema_ref="schemas/business/order_validated.v1.json",
                    producer=self.config.producer_service,
                    environment=self.config.environment,
                    run_id=self.config.run_id,
                    trace_id=trace_id,
                    partition_key=order_id,
                    sequence=sequence * 20 + 2,
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
                ),
            ),
        ]

        fraud = self._fraud_outcome(
            customer=customer,
            channel=channel,
            order_amount=grand_total,
            total_qty=total_qty,
        )
        if fraud.flagged:
            events.append(
                PlannedEvent(
                    topic=self.config.topics.risk_events,
                    component="fraud",
                    log_level="WARN",
                    event=build_event(
                        event_type="suspicious_order_flagged",
                        event_version=1,
                        schema_ref="schemas/business/suspicious_order_flagged.v1.json",
                        producer=self.config.producer_service,
                        environment=self.config.environment,
                        run_id=self.config.run_id,
                        trace_id=trace_id,
                        partition_key=order_id,
                        sequence=sequence * 20 + 3,
                        event_time=risk_at,
                        order_id=order_id,
                        customer_id=customer.customer_id,
                        session_id=session_id,
                        signal_id=signal_id,
                        payload={
                            "risk_score": fraud.risk_score,
                            "rules_triggered": fraud.rules_triggered,
                            "action": fraud.action,
                            "review_status": fraud.review_status,
                            "channel": channel,
                            "region": customer.region,
                            "customer_segment": customer.segment,
                        },
                    ),
                )
            )

        if fraud.action == "block_order":
            events.append(
                self._order_cancelled_event(
                    trace_id=trace_id,
                    sequence=sequence * 20 + 4,
                    event_time=risk_at + timedelta(milliseconds=25),
                    order_id=order_id,
                    customer_id=customer.customer_id,
                    session_id=session_id,
                    cancellation_reason_code="fraud_blocked",
                    cancelled_stage="validation",
                    reason_detail="risk_engine_block",
                )
            )
            return LifecycleBatch(events=events, active_sessions=len(set(self.recent_sessions)), order_amount=grand_total)

        payment_failed, reason_code, reason_group = self._payment_outcome(customer, fraud)
        payment_event_type = "payment_failed" if payment_failed else "payment_authorized"
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

        events.append(
            PlannedEvent(
                topic=self.config.topics.payment_events,
                component="payments",
                log_level="WARN" if payment_failed else "INFO",
                event=build_event(
                    event_type=payment_event_type,
                    event_version=1,
                    schema_ref=f"schemas/business/{payment_event_type}.v1.json",
                    producer=self.config.producer_service,
                    environment=self.config.environment,
                    run_id=self.config.run_id,
                    trace_id=trace_id,
                    partition_key=order_id,
                    sequence=sequence * 20 + 5,
                    event_time=paid_at,
                    order_id=order_id,
                    customer_id=customer.customer_id,
                    session_id=session_id,
                    payment_id=payment_id,
                    payload=payment_payload,
                ),
            )
        )

        if payment_failed:
            events.append(
                self._order_cancelled_event(
                    trace_id=trace_id,
                    sequence=sequence * 20 + 6,
                    event_time=paid_at + timedelta(milliseconds=30),
                    order_id=order_id,
                    customer_id=customer.customer_id,
                    session_id=session_id,
                    cancellation_reason_code=str(reason_code or "payment_failed"),
                    cancelled_stage="payment",
                    reason_detail=str(reason_group or "authorization_failed"),
                )
            )
            return LifecycleBatch(events=events, active_sessions=len(set(self.recent_sessions)), order_amount=grand_total)

        inventory = self._inventory_outcome(
            items=items,
            region=customer.region,
            reservation_id=reservation_id,
        )
        if inventory.shortage:
            events.append(
                PlannedEvent(
                    topic=self.config.topics.inventory_events,
                    component="inventory",
                    log_level="WARN",
                    event=build_event(
                        event_type="inventory_shortage",
                        event_version=1,
                        schema_ref="schemas/business/inventory_shortage.v1.json",
                        producer=self.config.producer_service,
                        environment=self.config.environment,
                        run_id=self.config.run_id,
                        trace_id=trace_id,
                        partition_key=order_id,
                        sequence=sequence * 20 + 7,
                        event_time=inventory_at,
                        order_id=order_id,
                        customer_id=customer.customer_id,
                        session_id=session_id,
                        payment_id=payment_id,
                        reservation_id=reservation_id,
                        payload={
                            "warehouse_id": inventory.warehouse_id,
                            "requested_qty": inventory.requested_qty,
                            "reserved_qty": inventory.reserved_qty,
                            "stock_after": inventory.stock_after,
                            "shortage_reason_code": inventory.shortage_reason_code,
                            "missing_items": inventory.missing_items,
                            "region": customer.region,
                        },
                    ),
                )
            )
            events.append(
                self._order_cancelled_event(
                    trace_id=trace_id,
                    sequence=sequence * 20 + 8,
                    event_time=inventory_at + timedelta(milliseconds=25),
                    order_id=order_id,
                    customer_id=customer.customer_id,
                    session_id=session_id,
                    payment_id=payment_id,
                    cancellation_reason_code="inventory_shortage",
                    cancelled_stage="inventory",
                    reason_detail=str(inventory.shortage_reason_code or "stockout"),
                )
            )
            refund = self._refund_outcome(
                payment_method=payment_method,
                order_amount=grand_total,
                due_to_shortage=True,
                due_to_delay=False,
                refund_id=refund_id,
            )
            events.extend(
                self._refund_events(
                    refund=refund,
                    trace_id=trace_id,
                    order_id=order_id,
                    customer_id=customer.customer_id,
                    session_id=session_id,
                    payment_id=payment_id,
                    sequence_base=sequence * 20 + 9,
                    requested_at=inventory_at + timedelta(seconds=2),
                )
            )
            return LifecycleBatch(events=events, active_sessions=len(set(self.recent_sessions)), order_amount=grand_total)

        events.append(
            PlannedEvent(
                topic=self.config.topics.inventory_events,
                component="inventory",
                log_level="INFO",
                event=build_event(
                    event_type="inventory_reserved",
                    event_version=1,
                    schema_ref="schemas/business/inventory_reserved.v1.json",
                    producer=self.config.producer_service,
                    environment=self.config.environment,
                    run_id=self.config.run_id,
                    trace_id=trace_id,
                    partition_key=order_id,
                    sequence=sequence * 20 + 7,
                    event_time=inventory_at,
                    order_id=order_id,
                    customer_id=customer.customer_id,
                    session_id=session_id,
                    payment_id=payment_id,
                    reservation_id=reservation_id,
                    payload={
                        "warehouse_id": inventory.warehouse_id,
                        "requested_qty": inventory.requested_qty,
                        "reserved_qty": inventory.reserved_qty,
                        "stock_after": inventory.stock_after,
                        "reservation_status": "reserved",
                        "sku_count": len(items),
                        "region": customer.region,
                    },
                ),
            )
        )

        shipment = self._shipment_outcome(
            channel=channel,
            region=customer.region,
            shipment_id=shipment_id,
            base_time=shipped_at,
        )
        events.append(
            PlannedEvent(
                topic=self.config.topics.shipment_events,
                component="shipping",
                log_level="INFO",
                event=build_event(
                    event_type="shipment_created",
                    event_version=1,
                    schema_ref="schemas/business/shipment_created.v1.json",
                    producer=self.config.producer_service,
                    environment=self.config.environment,
                    run_id=self.config.run_id,
                    trace_id=trace_id,
                    partition_key=order_id,
                    sequence=sequence * 20 + 8,
                    event_time=shipped_at,
                    order_id=order_id,
                    customer_id=customer.customer_id,
                    session_id=session_id,
                    payment_id=payment_id,
                    shipment_id=shipment_id,
                    payload={
                        "carrier": shipment.carrier,
                        "service_level": shipment.service_level,
                        "shipment_status": "created",
                        "promised_delivery_at": isoformat(shipment.promised_delivery_at),
                        "estimated_delivery_at": isoformat(shipment.estimated_delivery_at),
                        "region": customer.region,
                    },
                ),
            )
        )

        if shipment.delayed:
            delayed_at = shipped_at + timedelta(minutes=5)
            events.append(
                PlannedEvent(
                    topic=self.config.topics.shipment_events,
                    component="shipping",
                    log_level="WARN",
                    event=build_event(
                        event_type="shipment_delayed",
                        event_version=1,
                        schema_ref="schemas/business/shipment_delayed.v1.json",
                        producer=self.config.producer_service,
                        environment=self.config.environment,
                        run_id=self.config.run_id,
                        trace_id=trace_id,
                        partition_key=order_id,
                        sequence=sequence * 20 + 9,
                        event_time=delayed_at,
                        order_id=order_id,
                        customer_id=customer.customer_id,
                        session_id=session_id,
                        payment_id=payment_id,
                        shipment_id=shipment_id,
                        payload={
                            "carrier": shipment.carrier,
                            "service_level": shipment.service_level,
                            "delay_reason_code": shipment.delay_reason_code,
                            "delayed_minutes": shipment.delayed_minutes,
                            "promised_delivery_at": isoformat(shipment.promised_delivery_at),
                            "updated_estimated_delivery_at": isoformat(shipment.estimated_delivery_at),
                            "region": customer.region,
                        },
                    ),
                )
            )

        refund = self._refund_outcome(
            payment_method=payment_method,
            order_amount=grand_total,
            due_to_shortage=False,
            due_to_delay=shipment.delayed,
            refund_id=refund_id,
        )
        if refund.refund_requested:
            refund_requested_at = shipment.estimated_delivery_at + timedelta(minutes=15)
            events.extend(
                self._refund_events(
                    refund=refund,
                    trace_id=trace_id,
                    order_id=order_id,
                    customer_id=customer.customer_id,
                    session_id=session_id,
                    payment_id=payment_id,
                    sequence_base=sequence * 20 + 10,
                    requested_at=refund_requested_at,
                )
            )

        return LifecycleBatch(events=events, active_sessions=len(set(self.recent_sessions)), order_amount=grand_total)

    def _order_cancelled_event(
        self,
        *,
        trace_id: str,
        sequence: int,
        event_time: datetime,
        order_id: str,
        customer_id: str,
        session_id: str,
        cancellation_reason_code: str,
        cancelled_stage: str,
        reason_detail: str,
        payment_id: str | None = None,
    ) -> PlannedEvent:
        return PlannedEvent(
            topic=self.config.topics.order_lifecycle,
            component="orders",
            log_level="WARN",
            event=build_event(
                event_type="order_cancelled",
                event_version=1,
                schema_ref="schemas/business/order_cancelled.v1.json",
                producer=self.config.producer_service,
                environment=self.config.environment,
                run_id=self.config.run_id,
                trace_id=trace_id,
                partition_key=order_id,
                sequence=sequence,
                event_time=event_time,
                order_id=order_id,
                customer_id=customer_id,
                session_id=session_id,
                payment_id=payment_id,
                payload={
                    "cancellation_reason_code": cancellation_reason_code,
                    "cancelled_stage": cancelled_stage,
                    "reason_detail": reason_detail,
                    "cancellation_source": "system",
                    "customer_notified": True,
                },
            ),
        )

    def _refund_events(
        self,
        *,
        refund: RefundDecision,
        trace_id: str,
        order_id: str,
        customer_id: str,
        session_id: str,
        payment_id: str,
        sequence_base: int,
        requested_at: datetime,
    ) -> list[PlannedEvent]:
        completed_at = requested_at + timedelta(minutes=self.randomizer.randint(2, 30))
        requested_event = PlannedEvent(
            topic=self.config.topics.refund_events,
            component="refunds",
            log_level="INFO",
            event=build_event(
                event_type="refund_requested",
                event_version=1,
                schema_ref="schemas/business/refund_requested.v1.json",
                producer=self.config.producer_service,
                environment=self.config.environment,
                run_id=self.config.run_id,
                trace_id=trace_id,
                partition_key=order_id,
                sequence=sequence_base,
                event_time=requested_at,
                order_id=order_id,
                customer_id=customer_id,
                session_id=session_id,
                payment_id=payment_id,
                refund_id=refund.refund_id,
                payload={
                    "reason_code": refund.reason_code,
                    "requested_amount": refund.requested_amount,
                    "currency": "USD",
                    "refund_type": refund.refund_type,
                    "requested_at": isoformat(requested_at),
                },
            ),
        )
        completed_event = PlannedEvent(
            topic=self.config.topics.refund_events,
            component="refunds",
            log_level="INFO",
            event=build_event(
                event_type="refund_completed",
                event_version=1,
                schema_ref="schemas/business/refund_completed.v1.json",
                producer=self.config.producer_service,
                environment=self.config.environment,
                run_id=self.config.run_id,
                trace_id=trace_id,
                partition_key=order_id,
                sequence=sequence_base + 1,
                event_time=completed_at,
                order_id=order_id,
                customer_id=customer_id,
                session_id=session_id,
                payment_id=payment_id,
                refund_id=refund.refund_id,
                payload={
                    "reason_code": refund.reason_code,
                    "approved_amount": refund.approved_amount,
                    "currency": "USD",
                    "refund_method": refund.refund_method,
                    "refund_type": refund.refund_type,
                    "completed_at": isoformat(completed_at),
                    "status": "completed",
                },
            ),
        )
        return [requested_event, completed_event]

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

    def _payment_outcome(self, customer: Customer, fraud: FraudDecision) -> tuple[bool, str | None, str | None]:
        risk_multiplier = {"low": 0.7, "medium": 1.0, "high": 1.5}[customer.risk_profile]
        review_multiplier = 1.2 if fraud.action == "manual_review" else 1.0
        failure_rate = min(self.config.payment_failure_rate * risk_multiplier * review_multiplier, 0.9)
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

    def _fraud_outcome(
        self,
        *,
        customer: Customer,
        channel: str,
        order_amount: float,
        total_qty: int,
    ) -> FraudDecision:
        base_score = {"low": 0.18, "medium": 0.42, "high": 0.66}[customer.risk_profile]
        if channel == "marketplace":
            base_score += 0.08
        if order_amount >= 350:
            base_score += 0.08
        if total_qty >= 4:
            base_score += 0.04
        base_score += self.randomizer.uniform(-0.06, 0.12)
        risk_score = round(min(max(base_score, 0.01), 0.99), 4)
        flagged = risk_score >= 0.68 or self.randomizer.random() < self.config.suspicious_order_rate
        if not flagged:
            return FraudDecision(False, risk_score, [], None, None)

        rules: list[str] = []
        if customer.risk_profile == "high":
            rules.append("high_risk_region")
        if order_amount >= 350:
            rules.append("amount_outlier")
        if channel in {"marketplace", "mobile"}:
            rules.append("device_reuse")
        if customer.segment == "new":
            rules.append("velocity_spike")
        if not rules:
            rules.append(self.randomizer.choice(FRAUD_RULES))

        if risk_score >= 0.85:
            action = "block_order"
            review_status = "closed_blocked"
        elif risk_score >= 0.72:
            action = "manual_review"
            review_status = "pending_review"
        else:
            action = "allow_with_watch"
            review_status = "watchlist"
        return FraudDecision(True, risk_score, sorted(set(rules)), action, review_status)

    def _inventory_outcome(
        self,
        *,
        items: list[dict[str, object]],
        region: str,
        reservation_id: str,
    ) -> InventoryDecision:
        requested_qty = sum(int(item["qty"]) for item in items)
        weighted_shortage_rate = self.config.inventory_shortage_rate
        if any(item["inventory_class"] == "slow" for item in items):
            weighted_shortage_rate += 0.04
        shortage = self.randomizer.random() < min(weighted_shortage_rate, 0.9)
        warehouse_id = self.randomizer.choice(WAREHOUSES_BY_REGION[region])

        if not shortage:
            return InventoryDecision(
                shortage=False,
                reservation_id=reservation_id,
                warehouse_id=warehouse_id,
                requested_qty=requested_qty,
                reserved_qty=requested_qty,
                stock_after=self.randomizer.randint(12, 140),
                shortage_reason_code=None,
                missing_items=[],
            )

        shortage_reason_code = weighted_choice(self.randomizer, SHORTAGE_REASONS)
        shortage_lines = self.randomizer.sample(items, k=min(len(items), self.randomizer.randint(1, 2)))
        missing_items: list[dict[str, object]] = []
        missing_total = 0
        for item in shortage_lines:
            missing_qty = min(int(item["qty"]), self.randomizer.randint(1, int(item["qty"])))
            missing_total += missing_qty
            missing_items.append(
                {
                    "sku": item["sku"],
                    "requested_qty": int(item["qty"]),
                    "missing_qty": missing_qty,
                }
            )
        reserved_qty = max(requested_qty - missing_total, 0)
        return InventoryDecision(
            shortage=True,
            reservation_id=reservation_id,
            warehouse_id=warehouse_id,
            requested_qty=requested_qty,
            reserved_qty=reserved_qty,
            stock_after=self.randomizer.randint(0, 3),
            shortage_reason_code=shortage_reason_code,
            missing_items=missing_items,
        )

    def _shipment_outcome(
        self,
        *,
        channel: str,
        region: str,
        shipment_id: str,
        base_time: datetime,
    ) -> ShipmentDecision:
        carrier = weighted_choice(self.randomizer, CARRIERS_BY_REGION[region])
        service_level = weighted_choice(self.randomizer, SERVICE_LEVELS_BY_CHANNEL[channel])
        transit_days = {"standard": 3, "express": 1, "priority": 2, "scheduled": 4}[service_level]
        promised_delivery_at = base_time + timedelta(days=transit_days)
        delay_bias = 0.03 if service_level == "standard" else 0.0
        delayed = self.randomizer.random() < min(self.config.shipment_delay_rate + delay_bias, 0.9)
        if delayed:
            delayed_minutes = self.randomizer.randint(45, 960)
            delay_reason_code = weighted_choice(self.randomizer, SHIPMENT_DELAY_REASONS)
            estimated_delivery_at = promised_delivery_at + timedelta(minutes=delayed_minutes)
        else:
            delayed_minutes = 0
            delay_reason_code = None
            estimated_delivery_at = promised_delivery_at
        return ShipmentDecision(
            shipment_id=shipment_id,
            carrier=carrier,
            service_level=service_level,
            promised_delivery_at=promised_delivery_at,
            estimated_delivery_at=estimated_delivery_at,
            delayed=delayed,
            delay_reason_code=delay_reason_code,
            delayed_minutes=delayed_minutes,
        )

    def _refund_outcome(
        self,
        *,
        payment_method: str,
        order_amount: float,
        due_to_shortage: bool,
        due_to_delay: bool,
        refund_id: str,
    ) -> RefundDecision:
        if due_to_shortage:
            reason_code = "inventory_shortage"
            requested_amount = approved_amount = round(order_amount, 2)
            refund_type = "full"
            return RefundDecision(True, refund_id, reason_code, refund_type, requested_amount, approved_amount, payment_method)

        if due_to_delay:
            should_refund = self.randomizer.random() < max(self.config.refund_rate, 0.4)
        else:
            should_refund = self.randomizer.random() < self.config.refund_rate
        if not should_refund:
            return RefundDecision(False, refund_id, "", "", 0.0, 0.0, payment_method)

        reason_code = "shipment_delay_compensation" if due_to_delay else weighted_choice(self.randomizer, REFUND_REASONS)
        if reason_code == "shipment_delay_compensation":
            requested_amount = round(max(order_amount * self.randomizer.uniform(0.08, 0.22), 5.0), 2)
            refund_type = "partial"
        elif reason_code == "inventory_shortage":
            requested_amount = round(order_amount, 2)
            refund_type = "full"
        else:
            requested_amount = round(max(order_amount * self.randomizer.uniform(0.15, 0.65), 8.0), 2)
            refund_type = "partial" if requested_amount < order_amount else "full"
        approved_amount = round(min(requested_amount, order_amount), 2)
        return RefundDecision(True, refund_id, reason_code, refund_type, requested_amount, approved_amount, payment_method)

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
