from __future__ import annotations

import random
from dataclasses import dataclass
from typing import TypeVar


@dataclass(frozen=True, slots=True)
class Customer:
    customer_id: str
    segment: str
    country: str
    region: str
    tenure_days: int
    risk_profile: str
    preferred_payment_method: str


@dataclass(frozen=True, slots=True)
class Product:
    sku: str
    category: str
    brand: str
    base_price: float
    margin_pct: float
    inventory_class: str
    seasonality_tag: str
    popularity_weight: float


PRODUCT_CATALOG: tuple[Product, ...] = (
    Product("sku-headphones-01", "audio", "AcoustiCo", 79.99, 0.34, "fast", "always_on", 1.0),
    Product("sku-speaker-02", "audio", "AcoustiCo", 129.99, 0.32, "medium", "always_on", 0.8),
    Product("sku-cable-07", "accessories", "CableLab", 9.99, 0.52, "fast", "always_on", 1.2),
    Product("sku-mouse-04", "peripherals", "ClickHouse", 39.99, 0.41, "fast", "always_on", 1.0),
    Product("sku-keyboard-03", "peripherals", "ClickHouse", 89.99, 0.36, "medium", "always_on", 0.9),
    Product("sku-monitor-08", "display", "VisionMax", 249.99, 0.25, "slow", "promo", 0.5),
    Product("sku-laptop-09", "computers", "Orbit", 899.99, 0.18, "slow", "launch", 0.25),
    Product("sku-webcam-05", "peripherals", "VisionMax", 59.99, 0.39, "fast", "always_on", 0.7),
    Product("sku-dock-11", "accessories", "Orbit", 149.99, 0.28, "medium", "b2b", 0.45),
    Product("sku-ssd-12", "components", "FlashCore", 119.99, 0.31, "medium", "always_on", 0.65),
    Product("sku-router-13", "network", "NetForge", 159.99, 0.24, "slow", "always_on", 0.35),
    Product("sku-chair-14", "workspace", "ErgoPoint", 229.99, 0.27, "slow", "always_on", 0.18),
)


SEGMENTS = ("new", "loyal", "vip", "bargain")
COUNTRIES_BY_REGION = {
    "eu-central-1": ("DE", "PL", "CZ"),
    "eu-west-1": ("IE", "FR", "ES"),
    "us-west-2": ("US", "CA"),
}
SEGMENT_WEIGHTS = (0.34, 0.36, 0.08, 0.22)
RISK_BY_SEGMENT = {
    "new": ("medium", "high"),
    "loyal": ("low", "medium"),
    "vip": ("low",),
    "bargain": ("medium", "high"),
}
PAYMENT_METHODS_BY_SEGMENT = {
    "new": (("card", 0.65), ("paypal", 0.25), ("buy_now_pay_later", 0.10)),
    "loyal": (("card", 0.60), ("wallet", 0.25), ("paypal", 0.15)),
    "vip": (("card", 0.55), ("invoice", 0.20), ("wallet", 0.25)),
    "bargain": (("card", 0.45), ("paypal", 0.35), ("buy_now_pay_later", 0.20)),
}
CHANNEL_WEIGHTS_BY_SEGMENT = {
    "new": (("web", 0.45), ("mobile", 0.35), ("marketplace", 0.20)),
    "loyal": (("mobile", 0.45), ("web", 0.45), ("marketplace", 0.10)),
    "vip": (("mobile", 0.55), ("web", 0.35), ("b2b", 0.10)),
    "bargain": (("web", 0.50), ("marketplace", 0.35), ("mobile", 0.15)),
}
DEVICE_WEIGHTS_BY_CHANNEL = {
    "web": (("desktop", 0.70), ("tablet", 0.10), ("mobile_web", 0.20)),
    "mobile": (("ios", 0.45), ("android", 0.55)),
    "marketplace": (("marketplace_app", 0.75), ("mobile_web", 0.25)),
    "b2b": (("desktop", 0.90), ("tablet", 0.10)),
}
CAMPAIGNS_BY_CHANNEL = {
    "web": ("direct", "seo", "spring_sale"),
    "mobile": ("push", "retargeting", "loyalty"),
    "marketplace": ("marketplace_featured", "coupon", "sponsored"),
    "b2b": ("account_manager", "renewal", "upsell"),
}
WAREHOUSES_BY_REGION = {
    "eu-central-1": ("waw-1", "fra-1"),
    "eu-west-1": ("dub-1", "par-1"),
    "us-west-2": ("pdx-1", "sea-1"),
}
CARRIERS_BY_REGION = {
    "eu-central-1": (("dhl", 0.45), ("inpost", 0.35), ("dpd", 0.20)),
    "eu-west-1": (("dhl", 0.35), ("chronopost", 0.25), ("ups", 0.40)),
    "us-west-2": (("ups", 0.42), ("fedex", 0.38), ("usps", 0.20)),
}
SERVICE_LEVELS_BY_CHANNEL = {
    "web": (("standard", 0.70), ("express", 0.30)),
    "mobile": (("standard", 0.62), ("express", 0.38)),
    "marketplace": (("standard", 0.82), ("priority", 0.18)),
    "b2b": (("scheduled", 0.55), ("express", 0.45)),
}
SHORTAGE_REASONS = (
    ("stockout", 0.46),
    ("warehouse_rebalance", 0.24),
    ("oversell_protection", 0.18),
    ("damaged_stock", 0.12),
)
SHIPMENT_DELAY_REASONS = (
    ("weather", 0.18),
    ("carrier_capacity", 0.31),
    ("address_verification", 0.12),
    ("linehaul_disruption", 0.23),
    ("customs_review", 0.16),
)
REFUND_REASONS = (
    ("inventory_shortage", 0.34),
    ("shipment_delay_compensation", 0.24),
    ("customer_return", 0.22),
    ("carrier_damage", 0.12),
    ("fraud_review_release", 0.08),
)
FRAUD_RULES = (
    "velocity_spike",
    "high_risk_region",
    "avs_name_mismatch",
    "device_reuse",
    "amount_outlier",
)

T = TypeVar("T")


def weighted_choice(randomizer: random.Random, choices: tuple[tuple[T, float], ...]) -> T:
    values = [value for value, _weight in choices]
    weights = [weight for _value, weight in choices]
    return randomizer.choices(values, weights=weights, k=1)[0]


def build_customers(seed: int, count: int = 400) -> list[Customer]:
    randomizer = random.Random(seed + 101)
    customers: list[Customer] = []
    for index in range(1, count + 1):
        segment = randomizer.choices(SEGMENTS, weights=SEGMENT_WEIGHTS, k=1)[0]
        region = randomizer.choices(tuple(COUNTRIES_BY_REGION.keys()), weights=(0.42, 0.24, 0.34), k=1)[0]
        country = randomizer.choice(COUNTRIES_BY_REGION[region])
        risk_profile = randomizer.choice(RISK_BY_SEGMENT[segment])
        preferred_payment_method = weighted_choice(randomizer, PAYMENT_METHODS_BY_SEGMENT[segment])
        customers.append(
            Customer(
                customer_id=f"cust-{index:05d}",
                segment=segment,
                country=country,
                region=region,
                tenure_days=randomizer.randint(7, 1400),
                risk_profile=risk_profile,
                preferred_payment_method=preferred_payment_method,
            )
        )
    return customers
