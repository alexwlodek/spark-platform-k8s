from __future__ import annotations

import argparse
from datetime import datetime, timezone

from prometheus_client import Counter, Gauge, start_http_server
from pyspark.sql import DataFrame, SparkSession
from pyspark.sql.functions import col, coalesce, current_timestamp, expr, get_json_object, lit, to_timestamp

INPUT_ROWS_PER_SECOND = Gauge(
    "streaming_input_rows_per_second",
    "Structured Streaming input rows per second",
    ["query"],
)
PROCESSED_ROWS_PER_SECOND = Gauge(
    "streaming_processed_rows_per_second",
    "Structured Streaming processed rows per second",
    ["query"],
)
BATCH_DURATION_MS = Gauge(
    "streaming_batch_duration_milliseconds",
    "Structured Streaming batch duration in milliseconds",
    ["query"],
)
QUERY_LAG_SECONDS = Gauge(
    "streaming_query_lag_seconds",
    "Approximate event-time lag in seconds",
    ["query"],
)
FAILURE_COUNT = Counter(
    "streaming_failure_count_total",
    "Total number of Structured Streaming failures",
    ["query"],
)
PARSE_FAILURE_COUNT = Counter(
    "streaming_parse_failure_count_total",
    "Total number of streaming records with parsing failures",
    ["query"],
)
QUARANTINE_ROW_COUNT = Counter(
    "streaming_quarantine_row_count_total",
    "Total number of rows routed to quarantine",
    ["query", "reason"],
)
TABLE_WRITE_ROW_COUNT = Counter(
    "streaming_table_write_row_count_total",
    "Total number of rows written or merged into analytical tables",
    ["query", "layer", "table"],
)

TECHNICAL_EVENT_TYPES = (
    "generator_backpressure",
    "malformed_event_generated",
    "retry_exhausted",
    "schema_validation_failed",
)
MINUTE_METRIC_EVENT_TYPES = ("order_created", "payment_authorized", "payment_failed")
FUNNEL_EVENT_TYPES = (
    "order_created",
    "order_validated",
    "payment_authorized",
    "payment_failed",
    "inventory_reserved",
    "inventory_shortage",
    "shipment_created",
    "shipment_delayed",
    "order_cancelled",
    "refund_requested",
    "refund_completed",
    "suspicious_order_flagged",
)
TS_ZERO = "TIMESTAMP '1970-01-01 00:00:00'"

BRONZE_COLUMNS = [
    "topic",
    "kafka_key",
    "kafka_partition",
    "kafka_offset",
    "kafka_timestamp",
    "raw_json",
    "event_id",
    "event_type",
    "event_version",
    "event_time",
    "producer",
    "environment",
    "run_id",
    "trace_id",
    "schema_ref",
    "partition_key",
    "order_id",
    "customer_id",
    "session_id",
    "payment_id",
    "payload_json",
    "parse_status",
    "amount",
    "channel",
    "region",
    "customer_segment",
    "payment_status",
    "payment_failure_reason_group",
    "ingested_at",
]
QUARANTINE_COLUMNS = [
    "topic",
    "kafka_key",
    "kafka_partition",
    "kafka_offset",
    "kafka_timestamp",
    "raw_json",
    "event_id",
    "event_type",
    "event_time",
    "run_id",
    "trace_id",
    "order_id",
    "payment_id",
    "shipment_id",
    "refund_id",
    "signal_id",
    "parse_status",
    "quarantine_reason",
    "validation_errors_json",
    "payload_json",
    "ingested_at",
]
SILVER_EVENT_COLUMNS = [
    "event_id",
    "event_type",
    "event_version",
    "event_time",
    "producer",
    "environment",
    "run_id",
    "trace_id",
    "schema_ref",
    "topic",
    "kafka_key",
    "kafka_partition",
    "kafka_offset",
    "kafka_timestamp",
    "partition_key",
    "order_id",
    "customer_id",
    "session_id",
    "payment_id",
    "reservation_id",
    "shipment_id",
    "refund_id",
    "signal_id",
    "payload_json",
    "amount",
    "gross_amount",
    "requested_amount",
    "approved_amount",
    "currency",
    "channel",
    "region",
    "customer_segment",
    "payment_status",
    "payment_failure_reason_code",
    "payment_failure_reason_group",
    "payment_method",
    "provider",
    "attempt_no",
    "inventory_status",
    "shortage_reason_code",
    "shipment_status",
    "carrier",
    "service_level",
    "delay_reason_code",
    "delayed_minutes",
    "promised_delivery_at",
    "refund_status",
    "refund_reason_code",
    "risk_score",
    "risk_action",
    "cancellation_reason_code",
    "cancelled_stage",
    "ingested_at",
]
ORDER_STATE_COLUMNS = [
    "order_id",
    "customer_id",
    "customer_segment",
    "session_id",
    "region",
    "channel",
    "currency",
    "gross_amount",
    "order_status",
    "latest_event_type",
    "first_event_time",
    "last_event_time",
    "created_at",
    "validated_at",
    "payment_status",
    "payment_at",
    "payment_failure_reason_group",
    "inventory_status",
    "inventory_at",
    "inventory_shortage_reason_code",
    "shipment_status",
    "shipment_at",
    "carrier",
    "service_level",
    "shipment_delay_reason_code",
    "refund_status",
    "refund_at",
    "refund_reason_code",
    "suspicious_order",
    "risk_signal_at",
    "risk_action",
    "risk_score",
    "cancelled_at",
    "cancellation_reason_code",
    "cancellation_stage",
    "run_id",
    "updated_at",
]
PAYMENT_COLUMNS = [
    "payment_id",
    "order_id",
    "customer_id",
    "customer_segment",
    "region",
    "channel",
    "currency",
    "amount",
    "payment_method",
    "provider",
    "attempt_no",
    "payment_status",
    "failure_reason_code",
    "failure_reason_group",
    "authorized_at",
    "failed_at",
    "last_event_time",
    "run_id",
    "updated_at",
]
SHIPMENT_COLUMNS = [
    "shipment_id",
    "order_id",
    "customer_id",
    "customer_segment",
    "region",
    "channel",
    "carrier",
    "service_level",
    "shipment_status",
    "delay_reason_code",
    "delayed_minutes",
    "promised_delivery_at",
    "created_at",
    "delayed_at",
    "last_event_time",
    "run_id",
    "updated_at",
]
REFUND_COLUMNS = [
    "refund_id",
    "order_id",
    "payment_id",
    "customer_id",
    "customer_segment",
    "region",
    "channel",
    "currency",
    "requested_amount",
    "approved_amount",
    "refund_reason_code",
    "refund_status",
    "requested_at",
    "completed_at",
    "last_event_time",
    "run_id",
    "updated_at",
]
MINUTE_GOLD_COLUMNS = [
    "window_start",
    "window_end",
    "region",
    "channel",
    "customer_segment",
    "orders_created",
    "payment_authorized",
    "payment_failed",
    "gross_revenue",
    "payment_failure_rate",
    "batch_id",
    "processed_at",
]
FUNNEL_GOLD_COLUMNS = [
    "business_date",
    "region",
    "channel",
    "customer_segment",
    "orders_created",
    "orders_validated",
    "payment_authorized",
    "payment_failed",
    "inventory_reserved",
    "inventory_shortage",
    "shipments_created",
    "shipments_delayed",
    "orders_cancelled",
    "refund_requested",
    "refund_completed",
    "suspicious_orders",
    "gross_revenue",
    "batch_id",
    "processed_at",
]
PAYMENT_FAILURE_GOLD_COLUMNS = [
    "window_start",
    "window_end",
    "region",
    "channel",
    "customer_segment",
    "payment_authorized",
    "payment_failed",
    "payment_failure_rate",
    "batch_id",
    "processed_at",
]
REVENUE_REFUND_GOLD_COLUMNS = [
    "business_date",
    "region",
    "channel",
    "customer_segment",
    "gross_revenue",
    "refunds_requested_amount",
    "refunds_completed_amount",
    "net_revenue",
    "refund_requested_count",
    "refund_completed_count",
    "batch_id",
    "processed_at",
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Commerce Structured Streaming job")
    parser.add_argument("--kafka-bootstrap-servers", default="streaming-kafka.apps.svc.cluster.local:9092")
    parser.add_argument(
        "--kafka-topic",
        default="commerce.order.lifecycle.v1,commerce.payment.events.v1,commerce.generator.technical.v1",
    )
    parser.add_argument("--starting-offsets", default="latest")
    parser.add_argument("--window-duration", default="1 minute")
    parser.add_argument("--watermark-delay", default="2 minutes")
    parser.add_argument("--checkpoint-location", required=True)
    parser.add_argument("--bronze-table", default="iceberg_nessie.streaming.bronze_commerce_events")
    parser.add_argument("--quarantine-table", default="iceberg_nessie.streaming.quarantine_commerce_events")
    parser.add_argument("--silver-events-table", default="iceberg_nessie.streaming.silver_order_events")
    parser.add_argument("--silver-order-state-table", default="iceberg_nessie.streaming.silver_order_state")
    parser.add_argument("--silver-payments-table", default="iceberg_nessie.streaming.silver_payments")
    parser.add_argument("--silver-shipments-table", default="iceberg_nessie.streaming.silver_shipments")
    parser.add_argument("--silver-refunds-table", default="iceberg_nessie.streaming.silver_refunds")
    parser.add_argument("--gold-table", default="iceberg_nessie.streaming.gold_order_metrics_minute")
    parser.add_argument("--gold-funnel-table", default="iceberg_nessie.streaming.gold_order_funnel_daily")
    parser.add_argument(
        "--gold-payment-failure-table",
        default="iceberg_nessie.streaming.gold_payment_failure_rate_hourly",
    )
    parser.add_argument("--gold-revenue-refund-table", default="iceberg_nessie.streaming.gold_revenue_refund_daily")
    parser.add_argument("--output-path", default=None)
    parser.add_argument("--output-table", default=None)
    parser.add_argument("--query-name", default="commerce_events_streaming")
    parser.add_argument("--trigger-processing-time", default="10 seconds")
    parser.add_argument("--metrics-port", type=int, default=8090)
    return parser.parse_args()


def parse_event_time(value: str | None) -> datetime | None:
    if not value:
        return None

    normalized = value.replace("Z", "+00:00")
    try:
        return datetime.fromisoformat(normalized).astimezone(timezone.utc)
    except ValueError:
        return None


def update_stream_metrics(query_name: str, progress: dict[str, object] | None) -> None:
    if not progress:
        return

    input_rows = float(progress.get("inputRowsPerSecond", 0.0))
    processed_rows = float(progress.get("processedRowsPerSecond", 0.0))

    duration_ms_value = 0.0
    duration_ms = progress.get("durationMs")
    if isinstance(duration_ms, dict):
        trigger_execution = duration_ms.get("triggerExecution")
        if trigger_execution is not None:
            duration_ms_value = float(trigger_execution)

    event_time = progress.get("eventTime")
    lag_seconds = 0.0
    if isinstance(event_time, dict):
        max_event_time = parse_event_time(event_time.get("max"))
        if max_event_time is not None:
            lag_seconds = max((datetime.now(timezone.utc) - max_event_time).total_seconds(), 0.0)

    INPUT_ROWS_PER_SECOND.labels(query=query_name).set(input_rows)
    PROCESSED_ROWS_PER_SECOND.labels(query=query_name).set(processed_rows)
    BATCH_DURATION_MS.labels(query=query_name).set(duration_ms_value)
    QUERY_LAG_SECONDS.labels(query=query_name).set(lag_seconds)


def table_label(table_name: str) -> str:
    return table_name.split(".")[-1]


def record_table_write(query_name: str, layer: str, table_name: str, row_count: int) -> None:
    if row_count <= 0:
        return
    TABLE_WRITE_ROW_COUNT.labels(query=query_name, layer=layer, table=table_label(table_name)).inc(float(row_count))


def collect_distinct_values(df: DataFrame, column_name: str) -> list[str]:
    return [
        row[column_name]
        for row in df.select(column_name).where(col(column_name).isNotNull()).distinct().collect()
        if row[column_name] is not None
    ]


def collect_distinct_expression(df: DataFrame, expression: str, alias: str = "value") -> list[str]:
    return [
        row[alias]
        for row in df.selectExpr(f"{expression} AS {alias}").where(f"{alias} IS NOT NULL").distinct().collect()
        if row[alias] is not None
    ]


def latest_value_sql(column_name: str) -> str:
    return f"max_by({column_name}, CASE WHEN {column_name} IS NOT NULL THEN event_time ELSE {TS_ZERO} END)"


def ensure_schema(spark: SparkSession, table_name: str) -> None:
    parts = table_name.split(".")
    if len(parts) >= 2:
        schema_name = ".".join(parts[:-1])
        spark.sql(f"CREATE SCHEMA IF NOT EXISTS {schema_name}")


def ensure_bronze_table(spark: SparkSession, table_name: str) -> None:
    ensure_schema(spark, table_name)
    spark.sql(
        f"""
        CREATE TABLE IF NOT EXISTS {table_name} (
          topic STRING,
          kafka_key STRING,
          kafka_partition INT,
          kafka_offset BIGINT,
          kafka_timestamp TIMESTAMP,
          raw_json STRING,
          event_id STRING,
          event_type STRING,
          event_version INT,
          event_time TIMESTAMP,
          producer STRING,
          environment STRING,
          run_id STRING,
          trace_id STRING,
          schema_ref STRING,
          partition_key STRING,
          order_id STRING,
          customer_id STRING,
          session_id STRING,
          payment_id STRING,
          payload_json STRING,
          parse_status STRING,
          amount DOUBLE,
          channel STRING,
          region STRING,
          customer_segment STRING,
          payment_status STRING,
          payment_failure_reason_group STRING,
          ingested_at TIMESTAMP
        ) USING iceberg
        PARTITIONED BY (days(event_time), event_type)
        """
    )


def ensure_quarantine_table(spark: SparkSession, table_name: str) -> None:
    ensure_schema(spark, table_name)
    spark.sql(
        f"""
        CREATE TABLE IF NOT EXISTS {table_name} (
          topic STRING,
          kafka_key STRING,
          kafka_partition INT,
          kafka_offset BIGINT,
          kafka_timestamp TIMESTAMP,
          raw_json STRING,
          event_id STRING,
          event_type STRING,
          event_time TIMESTAMP,
          run_id STRING,
          trace_id STRING,
          order_id STRING,
          payment_id STRING,
          shipment_id STRING,
          refund_id STRING,
          signal_id STRING,
          parse_status STRING,
          quarantine_reason STRING,
          validation_errors_json STRING,
          payload_json STRING,
          ingested_at TIMESTAMP
        ) USING iceberg
        PARTITIONED BY (days(kafka_timestamp), quarantine_reason)
        """
    )


def ensure_silver_events_table(spark: SparkSession, table_name: str) -> None:
    ensure_schema(spark, table_name)
    spark.sql(
        f"""
        CREATE TABLE IF NOT EXISTS {table_name} (
          event_id STRING,
          event_type STRING,
          event_version INT,
          event_time TIMESTAMP,
          producer STRING,
          environment STRING,
          run_id STRING,
          trace_id STRING,
          schema_ref STRING,
          topic STRING,
          kafka_key STRING,
          kafka_partition INT,
          kafka_offset BIGINT,
          kafka_timestamp TIMESTAMP,
          partition_key STRING,
          order_id STRING,
          customer_id STRING,
          session_id STRING,
          payment_id STRING,
          reservation_id STRING,
          shipment_id STRING,
          refund_id STRING,
          signal_id STRING,
          payload_json STRING,
          amount DOUBLE,
          gross_amount DOUBLE,
          requested_amount DOUBLE,
          approved_amount DOUBLE,
          currency STRING,
          channel STRING,
          region STRING,
          customer_segment STRING,
          payment_status STRING,
          payment_failure_reason_code STRING,
          payment_failure_reason_group STRING,
          payment_method STRING,
          provider STRING,
          attempt_no INT,
          inventory_status STRING,
          shortage_reason_code STRING,
          shipment_status STRING,
          carrier STRING,
          service_level STRING,
          delay_reason_code STRING,
          delayed_minutes INT,
          promised_delivery_at TIMESTAMP,
          refund_status STRING,
          refund_reason_code STRING,
          risk_score DOUBLE,
          risk_action STRING,
          cancellation_reason_code STRING,
          cancelled_stage STRING,
          ingested_at TIMESTAMP
        ) USING iceberg
        PARTITIONED BY (days(event_time), event_type)
        """
    )


def ensure_silver_order_state_table(spark: SparkSession, table_name: str) -> None:
    ensure_schema(spark, table_name)
    spark.sql(
        f"""
        CREATE TABLE IF NOT EXISTS {table_name} (
          order_id STRING,
          customer_id STRING,
          customer_segment STRING,
          session_id STRING,
          region STRING,
          channel STRING,
          currency STRING,
          gross_amount DOUBLE,
          order_status STRING,
          latest_event_type STRING,
          first_event_time TIMESTAMP,
          last_event_time TIMESTAMP,
          created_at TIMESTAMP,
          validated_at TIMESTAMP,
          payment_status STRING,
          payment_at TIMESTAMP,
          payment_failure_reason_group STRING,
          inventory_status STRING,
          inventory_at TIMESTAMP,
          inventory_shortage_reason_code STRING,
          shipment_status STRING,
          shipment_at TIMESTAMP,
          carrier STRING,
          service_level STRING,
          shipment_delay_reason_code STRING,
          refund_status STRING,
          refund_at TIMESTAMP,
          refund_reason_code STRING,
          suspicious_order BOOLEAN,
          risk_signal_at TIMESTAMP,
          risk_action STRING,
          risk_score DOUBLE,
          cancelled_at TIMESTAMP,
          cancellation_reason_code STRING,
          cancellation_stage STRING,
          run_id STRING,
          updated_at TIMESTAMP
        ) USING iceberg
        PARTITIONED BY (days(last_event_time), region)
        """
    )


def ensure_silver_payments_table(spark: SparkSession, table_name: str) -> None:
    ensure_schema(spark, table_name)
    spark.sql(
        f"""
        CREATE TABLE IF NOT EXISTS {table_name} (
          payment_id STRING,
          order_id STRING,
          customer_id STRING,
          customer_segment STRING,
          region STRING,
          channel STRING,
          currency STRING,
          amount DOUBLE,
          payment_method STRING,
          provider STRING,
          attempt_no INT,
          payment_status STRING,
          failure_reason_code STRING,
          failure_reason_group STRING,
          authorized_at TIMESTAMP,
          failed_at TIMESTAMP,
          last_event_time TIMESTAMP,
          run_id STRING,
          updated_at TIMESTAMP
        ) USING iceberg
        PARTITIONED BY (days(last_event_time), region)
        """
    )


def ensure_silver_shipments_table(spark: SparkSession, table_name: str) -> None:
    ensure_schema(spark, table_name)
    spark.sql(
        f"""
        CREATE TABLE IF NOT EXISTS {table_name} (
          shipment_id STRING,
          order_id STRING,
          customer_id STRING,
          customer_segment STRING,
          region STRING,
          channel STRING,
          carrier STRING,
          service_level STRING,
          shipment_status STRING,
          delay_reason_code STRING,
          delayed_minutes INT,
          promised_delivery_at TIMESTAMP,
          created_at TIMESTAMP,
          delayed_at TIMESTAMP,
          last_event_time TIMESTAMP,
          run_id STRING,
          updated_at TIMESTAMP
        ) USING iceberg
        PARTITIONED BY (days(last_event_time), region)
        """
    )


def ensure_silver_refunds_table(spark: SparkSession, table_name: str) -> None:
    ensure_schema(spark, table_name)
    spark.sql(
        f"""
        CREATE TABLE IF NOT EXISTS {table_name} (
          refund_id STRING,
          order_id STRING,
          payment_id STRING,
          customer_id STRING,
          customer_segment STRING,
          region STRING,
          channel STRING,
          currency STRING,
          requested_amount DOUBLE,
          approved_amount DOUBLE,
          refund_reason_code STRING,
          refund_status STRING,
          requested_at TIMESTAMP,
          completed_at TIMESTAMP,
          last_event_time TIMESTAMP,
          run_id STRING,
          updated_at TIMESTAMP
        ) USING iceberg
        PARTITIONED BY (days(last_event_time), region)
        """
    )


def ensure_gold_table(spark: SparkSession, table_name: str) -> None:
    ensure_schema(spark, table_name)
    spark.sql(
        f"""
        CREATE TABLE IF NOT EXISTS {table_name} (
          window_start TIMESTAMP,
          window_end TIMESTAMP,
          region STRING,
          channel STRING,
          customer_segment STRING,
          orders_created BIGINT,
          payment_authorized BIGINT,
          payment_failed BIGINT,
          gross_revenue DOUBLE,
          payment_failure_rate DOUBLE,
          batch_id BIGINT,
          processed_at TIMESTAMP
        ) USING iceberg
        PARTITIONED BY (days(window_start), region)
        """
    )


def ensure_gold_funnel_table(spark: SparkSession, table_name: str) -> None:
    ensure_schema(spark, table_name)
    spark.sql(
        f"""
        CREATE TABLE IF NOT EXISTS {table_name} (
          business_date DATE,
          region STRING,
          channel STRING,
          customer_segment STRING,
          orders_created BIGINT,
          orders_validated BIGINT,
          payment_authorized BIGINT,
          payment_failed BIGINT,
          inventory_reserved BIGINT,
          inventory_shortage BIGINT,
          shipments_created BIGINT,
          shipments_delayed BIGINT,
          orders_cancelled BIGINT,
          refund_requested BIGINT,
          refund_completed BIGINT,
          suspicious_orders BIGINT,
          gross_revenue DOUBLE,
          batch_id BIGINT,
          processed_at TIMESTAMP
        ) USING iceberg
        PARTITIONED BY (business_date, region)
        """
    )


def ensure_gold_payment_failure_table(spark: SparkSession, table_name: str) -> None:
    ensure_schema(spark, table_name)
    spark.sql(
        f"""
        CREATE TABLE IF NOT EXISTS {table_name} (
          window_start TIMESTAMP,
          window_end TIMESTAMP,
          region STRING,
          channel STRING,
          customer_segment STRING,
          payment_authorized BIGINT,
          payment_failed BIGINT,
          payment_failure_rate DOUBLE,
          batch_id BIGINT,
          processed_at TIMESTAMP
        ) USING iceberg
        PARTITIONED BY (days(window_start), region)
        """
    )


def ensure_gold_revenue_refund_table(spark: SparkSession, table_name: str) -> None:
    ensure_schema(spark, table_name)
    spark.sql(
        f"""
        CREATE TABLE IF NOT EXISTS {table_name} (
          business_date DATE,
          region STRING,
          channel STRING,
          customer_segment STRING,
          gross_revenue DOUBLE,
          refunds_requested_amount DOUBLE,
          refunds_completed_amount DOUBLE,
          net_revenue DOUBLE,
          refund_requested_count BIGINT,
          refund_completed_count BIGINT,
          batch_id BIGINT,
          processed_at TIMESTAMP
        ) USING iceberg
        PARTITIONED BY (business_date, region)
        """
    )


def build_parsed_stream(source: DataFrame) -> DataFrame:
    raw = source.selectExpr(
        "topic",
        "CAST(key AS STRING) AS kafka_key",
        "CAST(value AS STRING) AS raw_json",
        "partition AS kafka_partition",
        "offset AS kafka_offset",
        "timestamp AS kafka_timestamp",
    )

    parsed = (
        raw.withColumn("event_id", get_json_object(col("raw_json"), "$.event_id"))
        .withColumn("event_type", get_json_object(col("raw_json"), "$.event_type"))
        .withColumn("event_version", get_json_object(col("raw_json"), "$.event_version").cast("int"))
        .withColumn("event_time", to_timestamp(get_json_object(col("raw_json"), "$.event_time")))
        .withColumn("producer", get_json_object(col("raw_json"), "$.producer"))
        .withColumn("environment", get_json_object(col("raw_json"), "$.environment"))
        .withColumn("run_id", get_json_object(col("raw_json"), "$.run_id"))
        .withColumn("trace_id", get_json_object(col("raw_json"), "$.trace_id"))
        .withColumn("schema_ref", get_json_object(col("raw_json"), "$.schema_ref"))
        .withColumn("partition_key", get_json_object(col("raw_json"), "$.partition_key"))
        .withColumn("order_id", get_json_object(col("raw_json"), "$.order_id"))
        .withColumn("customer_id", get_json_object(col("raw_json"), "$.customer_id"))
        .withColumn("session_id", get_json_object(col("raw_json"), "$.session_id"))
        .withColumn("payment_id", get_json_object(col("raw_json"), "$.payment_id"))
        .withColumn("reservation_id", get_json_object(col("raw_json"), "$.reservation_id"))
        .withColumn("shipment_id", get_json_object(col("raw_json"), "$.shipment_id"))
        .withColumn("refund_id", get_json_object(col("raw_json"), "$.refund_id"))
        .withColumn("signal_id", get_json_object(col("raw_json"), "$.signal_id"))
        .withColumn("payload_json", get_json_object(col("raw_json"), "$.payload"))
        .withColumn("currency", get_json_object(col("raw_json"), "$.payload.currency"))
        .withColumn("channel", get_json_object(col("raw_json"), "$.payload.channel"))
        .withColumn("region", get_json_object(col("raw_json"), "$.payload.region"))
        .withColumn("customer_segment", get_json_object(col("raw_json"), "$.payload.customer_segment"))
        .withColumn("gross_amount", get_json_object(col("raw_json"), "$.payload.grand_total").cast("double"))
        .withColumn("base_amount", get_json_object(col("raw_json"), "$.payload.amount").cast("double"))
        .withColumn("requested_amount", get_json_object(col("raw_json"), "$.payload.requested_amount").cast("double"))
        .withColumn("approved_amount", get_json_object(col("raw_json"), "$.payload.approved_amount").cast("double"))
        .withColumn("amount", coalesce(col("gross_amount"), col("base_amount"), col("requested_amount"), col("approved_amount")))
        .withColumn(
            "payment_status",
            expr(
                """
                CASE
                  WHEN event_type = 'payment_authorized' THEN 'authorized'
                  WHEN event_type = 'payment_failed' THEN 'failed'
                  ELSE NULL
                END
                """
            ),
        )
        .withColumn("payment_failure_reason_code", get_json_object(col("raw_json"), "$.payload.failure_reason_code"))
        .withColumn("payment_failure_reason_group", get_json_object(col("raw_json"), "$.payload.failure_reason_group"))
        .withColumn("payment_method", get_json_object(col("raw_json"), "$.payload.payment_method"))
        .withColumn("provider", get_json_object(col("raw_json"), "$.payload.provider"))
        .withColumn("attempt_no", get_json_object(col("raw_json"), "$.payload.attempt_no").cast("int"))
        .withColumn(
            "inventory_status",
            expr(
                """
                CASE
                  WHEN event_type = 'inventory_reserved' THEN 'reserved'
                  WHEN event_type = 'inventory_shortage' THEN 'shortage'
                  ELSE NULL
                END
                """
            ),
        )
        .withColumn("shortage_reason_code", get_json_object(col("raw_json"), "$.payload.shortage_reason_code"))
        .withColumn(
            "shipment_status",
            expr(
                """
                CASE
                  WHEN event_type = 'shipment_created' THEN 'created'
                  WHEN event_type = 'shipment_delayed' THEN 'delayed'
                  ELSE NULL
                END
                """
            ),
        )
        .withColumn("carrier", get_json_object(col("raw_json"), "$.payload.carrier"))
        .withColumn("service_level", get_json_object(col("raw_json"), "$.payload.service_level"))
        .withColumn("delay_reason_code", get_json_object(col("raw_json"), "$.payload.delay_reason_code"))
        .withColumn("delayed_minutes", get_json_object(col("raw_json"), "$.payload.delayed_minutes").cast("int"))
        .withColumn("promised_delivery_at", to_timestamp(get_json_object(col("raw_json"), "$.payload.promised_delivery_at")))
        .withColumn(
            "refund_status",
            expr(
                """
                CASE
                  WHEN event_type = 'refund_requested' THEN 'requested'
                  WHEN event_type = 'refund_completed' THEN 'completed'
                  ELSE NULL
                END
                """
            ),
        )
        .withColumn("refund_reason_code", get_json_object(col("raw_json"), "$.payload.reason_code"))
        .withColumn("risk_score", get_json_object(col("raw_json"), "$.payload.risk_score").cast("double"))
        .withColumn("risk_action", get_json_object(col("raw_json"), "$.payload.action"))
        .withColumn("cancellation_reason_code", get_json_object(col("raw_json"), "$.payload.cancellation_reason_code"))
        .withColumn("cancelled_stage", get_json_object(col("raw_json"), "$.payload.cancelled_stage"))
        .withColumn("validation_errors_json", get_json_object(col("raw_json"), "$.payload.validation_errors"))
        .withColumn(
            "parse_status",
            expr(
                """
                CASE
                  WHEN event_id IS NOT NULL AND event_type IS NOT NULL AND event_time IS NOT NULL THEN 'parsed'
                  ELSE 'invalid'
                END
                """
            ),
        )
        .withColumn(
            "quarantine_reason",
            expr(
                """
                CASE
                  WHEN parse_status <> 'parsed' THEN 'parse_invalid'
                  WHEN event_type = 'schema_validation_failed' THEN 'schema_validation_failed'
                  WHEN event_type = 'malformed_event_generated' THEN 'malformed_event_generated'
                  ELSE NULL
                END
                """
            ),
        )
        .drop("base_amount")
    )
    return parsed


def merge_insert_only(
    spark: SparkSession,
    df: DataFrame,
    table_name: str,
    key_condition: str,
    columns: list[str],
    temp_view: str,
) -> int:
    materialized = df.persist()
    row_count = materialized.count()
    if row_count == 0:
        materialized.unpersist()
        return 0

    materialized.createOrReplaceTempView(temp_view)
    column_list = ", ".join(columns)
    value_list = ", ".join(f"s.{column_name}" for column_name in columns)
    spark.sql(
        f"""
        MERGE INTO {table_name} AS t
        USING {temp_view} AS s
        ON {key_condition}
        WHEN NOT MATCHED THEN INSERT ({column_list})
        VALUES ({value_list})
        """
    )
    materialized.unpersist()
    return row_count


def merge_overwrite_rows(
    spark: SparkSession,
    df: DataFrame,
    table_name: str,
    key_condition: str,
    columns: list[str],
    temp_view: str,
) -> int:
    materialized = df.persist()
    row_count = materialized.count()
    if row_count == 0:
        materialized.unpersist()
        return 0

    materialized.createOrReplaceTempView(temp_view)
    assignments = ", ".join(f"t.{column_name} = s.{column_name}" for column_name in columns)
    column_list = ", ".join(columns)
    value_list = ", ".join(f"s.{column_name}" for column_name in columns)
    spark.sql(
        f"""
        MERGE INTO {table_name} AS t
        USING {temp_view} AS s
        ON {key_condition}
        WHEN MATCHED THEN UPDATE SET {assignments}
        WHEN NOT MATCHED THEN INSERT ({column_list})
        VALUES ({value_list})
        """
    )
    materialized.unpersist()
    return row_count


def build_quarantine_source(batch_df: DataFrame) -> DataFrame:
    return batch_df.filter(col("quarantine_reason").isNotNull()).select(*QUARANTINE_COLUMNS)


def build_silver_event_source(batch_df: DataFrame) -> DataFrame:
    return batch_df.filter(
        (col("parse_status") == "parsed")
        & col("event_time").isNotNull()
        & (~col("event_type").isin(*TECHNICAL_EVENT_TYPES))
    ).select(*SILVER_EVENT_COLUMNS)


def build_order_state_source(spark: SparkSession, silver_events_table: str, order_ids: list[str]) -> DataFrame | None:
    if not order_ids:
        return None

    scope = spark.table(silver_events_table).filter(col("order_id").isin(order_ids))
    scope.createOrReplaceTempView("silver_order_state_scope")
    return spark.sql(
        f"""
        SELECT
          order_id,
          {latest_value_sql("customer_id")} AS customer_id,
          {latest_value_sql("customer_segment")} AS customer_segment,
          {latest_value_sql("session_id")} AS session_id,
          {latest_value_sql("region")} AS region,
          {latest_value_sql("channel")} AS channel,
          {latest_value_sql("currency")} AS currency,
          {latest_value_sql("gross_amount")} AS gross_amount,
          CASE
            WHEN MAX(CASE WHEN event_type = 'order_cancelled' THEN 1 ELSE 0 END) > 0 THEN 'cancelled'
            WHEN MAX(CASE WHEN event_type = 'refund_completed' THEN 1 ELSE 0 END) > 0 THEN 'refunded'
            WHEN MAX(CASE WHEN event_type = 'refund_requested' THEN 1 ELSE 0 END) > 0 THEN 'refund_requested'
            WHEN MAX(CASE WHEN event_type = 'shipment_delayed' THEN 1 ELSE 0 END) > 0 THEN 'shipment_delayed'
            WHEN MAX(CASE WHEN event_type = 'shipment_created' THEN 1 ELSE 0 END) > 0 THEN 'shipment_created'
            WHEN MAX(CASE WHEN event_type = 'inventory_shortage' THEN 1 ELSE 0 END) > 0 THEN 'inventory_shortage'
            WHEN MAX(CASE WHEN event_type = 'inventory_reserved' THEN 1 ELSE 0 END) > 0 THEN 'inventory_reserved'
            WHEN MAX(CASE WHEN event_type = 'payment_failed' THEN 1 ELSE 0 END) > 0 THEN 'payment_failed'
            WHEN MAX(CASE WHEN event_type = 'payment_authorized' THEN 1 ELSE 0 END) > 0 THEN 'payment_authorized'
            WHEN MAX(CASE WHEN event_type = 'order_validated' THEN 1 ELSE 0 END) > 0 THEN 'validated'
            WHEN MAX(CASE WHEN event_type = 'order_created' THEN 1 ELSE 0 END) > 0 THEN 'created'
            ELSE 'unknown'
          END AS order_status,
          max_by(event_type, event_time) AS latest_event_type,
          MIN(event_time) AS first_event_time,
          MAX(event_time) AS last_event_time,
          MAX(CASE WHEN event_type = 'order_created' THEN event_time END) AS created_at,
          MAX(CASE WHEN event_type = 'order_validated' THEN event_time END) AS validated_at,
          {latest_value_sql("payment_status")} AS payment_status,
          MAX(CASE WHEN event_type IN ('payment_authorized', 'payment_failed') THEN event_time END) AS payment_at,
          {latest_value_sql("payment_failure_reason_group")} AS payment_failure_reason_group,
          {latest_value_sql("inventory_status")} AS inventory_status,
          MAX(CASE WHEN event_type IN ('inventory_reserved', 'inventory_shortage') THEN event_time END) AS inventory_at,
          {latest_value_sql("shortage_reason_code")} AS inventory_shortage_reason_code,
          {latest_value_sql("shipment_status")} AS shipment_status,
          MAX(CASE WHEN event_type IN ('shipment_created', 'shipment_delayed') THEN event_time END) AS shipment_at,
          {latest_value_sql("carrier")} AS carrier,
          {latest_value_sql("service_level")} AS service_level,
          {latest_value_sql("delay_reason_code")} AS shipment_delay_reason_code,
          {latest_value_sql("refund_status")} AS refund_status,
          MAX(CASE WHEN event_type IN ('refund_requested', 'refund_completed') THEN event_time END) AS refund_at,
          {latest_value_sql("refund_reason_code")} AS refund_reason_code,
          MAX(CASE WHEN event_type = 'suspicious_order_flagged' THEN 1 ELSE 0 END) = 1 AS suspicious_order,
          MAX(CASE WHEN event_type = 'suspicious_order_flagged' THEN event_time END) AS risk_signal_at,
          {latest_value_sql("risk_action")} AS risk_action,
          {latest_value_sql("risk_score")} AS risk_score,
          MAX(CASE WHEN event_type = 'order_cancelled' THEN event_time END) AS cancelled_at,
          {latest_value_sql("cancellation_reason_code")} AS cancellation_reason_code,
          {latest_value_sql("cancelled_stage")} AS cancellation_stage,
          {latest_value_sql("run_id")} AS run_id,
          current_timestamp() AS updated_at
        FROM silver_order_state_scope
        GROUP BY order_id
        """
    )


def build_payment_state_source(spark: SparkSession, silver_events_table: str, payment_ids: list[str]) -> DataFrame | None:
    if not payment_ids:
        return None

    scope = spark.table(silver_events_table).filter(col("payment_id").isin(payment_ids))
    scope.createOrReplaceTempView("silver_payment_scope")
    return spark.sql(
        f"""
        SELECT
          payment_id,
          {latest_value_sql("order_id")} AS order_id,
          {latest_value_sql("customer_id")} AS customer_id,
          {latest_value_sql("customer_segment")} AS customer_segment,
          {latest_value_sql("region")} AS region,
          {latest_value_sql("channel")} AS channel,
          {latest_value_sql("currency")} AS currency,
          {latest_value_sql("amount")} AS amount,
          {latest_value_sql("payment_method")} AS payment_method,
          {latest_value_sql("provider")} AS provider,
          {latest_value_sql("attempt_no")} AS attempt_no,
          {latest_value_sql("payment_status")} AS payment_status,
          {latest_value_sql("payment_failure_reason_code")} AS failure_reason_code,
          {latest_value_sql("payment_failure_reason_group")} AS failure_reason_group,
          MAX(CASE WHEN event_type = 'payment_authorized' THEN event_time END) AS authorized_at,
          MAX(CASE WHEN event_type = 'payment_failed' THEN event_time END) AS failed_at,
          MAX(event_time) AS last_event_time,
          {latest_value_sql("run_id")} AS run_id,
          current_timestamp() AS updated_at
        FROM silver_payment_scope
        GROUP BY payment_id
        """
    )


def build_shipment_state_source(spark: SparkSession, silver_events_table: str, shipment_ids: list[str]) -> DataFrame | None:
    if not shipment_ids:
        return None

    scope = spark.table(silver_events_table).filter(col("shipment_id").isin(shipment_ids))
    scope.createOrReplaceTempView("silver_shipment_scope")
    return spark.sql(
        f"""
        SELECT
          shipment_id,
          {latest_value_sql("order_id")} AS order_id,
          {latest_value_sql("customer_id")} AS customer_id,
          {latest_value_sql("customer_segment")} AS customer_segment,
          {latest_value_sql("region")} AS region,
          {latest_value_sql("channel")} AS channel,
          {latest_value_sql("carrier")} AS carrier,
          {latest_value_sql("service_level")} AS service_level,
          {latest_value_sql("shipment_status")} AS shipment_status,
          {latest_value_sql("delay_reason_code")} AS delay_reason_code,
          {latest_value_sql("delayed_minutes")} AS delayed_minutes,
          {latest_value_sql("promised_delivery_at")} AS promised_delivery_at,
          MAX(CASE WHEN event_type = 'shipment_created' THEN event_time END) AS created_at,
          MAX(CASE WHEN event_type = 'shipment_delayed' THEN event_time END) AS delayed_at,
          MAX(event_time) AS last_event_time,
          {latest_value_sql("run_id")} AS run_id,
          current_timestamp() AS updated_at
        FROM silver_shipment_scope
        GROUP BY shipment_id
        """
    )


def build_refund_state_source(spark: SparkSession, silver_events_table: str, refund_ids: list[str]) -> DataFrame | None:
    if not refund_ids:
        return None

    scope = spark.table(silver_events_table).filter(col("refund_id").isin(refund_ids))
    scope.createOrReplaceTempView("silver_refund_scope")
    return spark.sql(
        f"""
        SELECT
          refund_id,
          {latest_value_sql("order_id")} AS order_id,
          {latest_value_sql("payment_id")} AS payment_id,
          {latest_value_sql("customer_id")} AS customer_id,
          {latest_value_sql("customer_segment")} AS customer_segment,
          {latest_value_sql("region")} AS region,
          {latest_value_sql("channel")} AS channel,
          {latest_value_sql("currency")} AS currency,
          {latest_value_sql("requested_amount")} AS requested_amount,
          {latest_value_sql("approved_amount")} AS approved_amount,
          {latest_value_sql("refund_reason_code")} AS refund_reason_code,
          {latest_value_sql("refund_status")} AS refund_status,
          MAX(CASE WHEN event_type = 'refund_requested' THEN event_time END) AS requested_at,
          MAX(CASE WHEN event_type = 'refund_completed' THEN event_time END) AS completed_at,
          MAX(event_time) AS last_event_time,
          {latest_value_sql("run_id")} AS run_id,
          current_timestamp() AS updated_at
        FROM silver_refund_scope
        GROUP BY refund_id
        """
    )


def build_minute_gold_source(
    spark: SparkSession,
    silver_events_table: str,
    minute_keys: list[str],
    batch_id: int,
) -> DataFrame | None:
    if not minute_keys:
        return None

    scope = (
        spark.table(silver_events_table)
        .filter(col("event_type").isin(*MINUTE_METRIC_EVENT_TYPES))
        .withColumn("minute_key", expr("CAST(date_trunc('minute', event_time) AS STRING)"))
        .filter(col("minute_key").isin(minute_keys))
    )
    scope.createOrReplaceTempView("gold_minute_scope")
    return spark.sql(
        f"""
        SELECT
          date_trunc('minute', event_time) AS window_start,
          date_trunc('minute', event_time) + INTERVAL 1 MINUTE AS window_end,
          region,
          channel,
          customer_segment,
          SUM(CASE WHEN event_type = 'order_created' THEN 1 ELSE 0 END) AS orders_created,
          SUM(CASE WHEN event_type = 'payment_authorized' THEN 1 ELSE 0 END) AS payment_authorized,
          SUM(CASE WHEN event_type = 'payment_failed' THEN 1 ELSE 0 END) AS payment_failed,
          ROUND(SUM(CASE WHEN event_type = 'order_created' THEN gross_amount ELSE 0.0 END), 2) AS gross_revenue,
          CASE
            WHEN SUM(CASE WHEN event_type IN ('payment_authorized', 'payment_failed') THEN 1 ELSE 0 END) > 0
              THEN ROUND(
                SUM(CASE WHEN event_type = 'payment_failed' THEN 1 ELSE 0 END) /
                SUM(CASE WHEN event_type IN ('payment_authorized', 'payment_failed') THEN 1 ELSE 0 END),
                4
              )
            ELSE 0.0
          END AS payment_failure_rate,
          CAST({batch_id} AS BIGINT) AS batch_id,
          current_timestamp() AS processed_at
        FROM gold_minute_scope
        GROUP BY date_trunc('minute', event_time), region, channel, customer_segment
        """
    )


def build_funnel_gold_source(
    spark: SparkSession,
    silver_events_table: str,
    business_dates: list[str],
    batch_id: int,
) -> DataFrame | None:
    if not business_dates:
        return None

    scope = (
        spark.table(silver_events_table)
        .filter(col("event_type").isin(*FUNNEL_EVENT_TYPES))
        .withColumn("business_date_key", expr("CAST(to_date(event_time) AS STRING)"))
        .filter(col("business_date_key").isin(business_dates))
    )
    scope.createOrReplaceTempView("gold_funnel_scope")
    return spark.sql(
        f"""
        SELECT
          to_date(event_time) AS business_date,
          region,
          channel,
          customer_segment,
          SUM(CASE WHEN event_type = 'order_created' THEN 1 ELSE 0 END) AS orders_created,
          SUM(CASE WHEN event_type = 'order_validated' THEN 1 ELSE 0 END) AS orders_validated,
          SUM(CASE WHEN event_type = 'payment_authorized' THEN 1 ELSE 0 END) AS payment_authorized,
          SUM(CASE WHEN event_type = 'payment_failed' THEN 1 ELSE 0 END) AS payment_failed,
          SUM(CASE WHEN event_type = 'inventory_reserved' THEN 1 ELSE 0 END) AS inventory_reserved,
          SUM(CASE WHEN event_type = 'inventory_shortage' THEN 1 ELSE 0 END) AS inventory_shortage,
          SUM(CASE WHEN event_type = 'shipment_created' THEN 1 ELSE 0 END) AS shipments_created,
          SUM(CASE WHEN event_type = 'shipment_delayed' THEN 1 ELSE 0 END) AS shipments_delayed,
          SUM(CASE WHEN event_type = 'order_cancelled' THEN 1 ELSE 0 END) AS orders_cancelled,
          SUM(CASE WHEN event_type = 'refund_requested' THEN 1 ELSE 0 END) AS refund_requested,
          SUM(CASE WHEN event_type = 'refund_completed' THEN 1 ELSE 0 END) AS refund_completed,
          SUM(CASE WHEN event_type = 'suspicious_order_flagged' THEN 1 ELSE 0 END) AS suspicious_orders,
          ROUND(SUM(CASE WHEN event_type = 'order_created' THEN gross_amount ELSE 0.0 END), 2) AS gross_revenue,
          CAST({batch_id} AS BIGINT) AS batch_id,
          current_timestamp() AS processed_at
        FROM gold_funnel_scope
        GROUP BY to_date(event_time), region, channel, customer_segment
        """
    )


def build_payment_failure_gold_source(
    spark: SparkSession,
    silver_events_table: str,
    hour_keys: list[str],
    batch_id: int,
) -> DataFrame | None:
    if not hour_keys:
        return None

    scope = (
        spark.table(silver_events_table)
        .filter(col("event_type").isin("payment_authorized", "payment_failed"))
        .withColumn("hour_key", expr("CAST(date_trunc('hour', event_time) AS STRING)"))
        .filter(col("hour_key").isin(hour_keys))
    )
    scope.createOrReplaceTempView("gold_payment_failure_scope")
    return spark.sql(
        f"""
        SELECT
          date_trunc('hour', event_time) AS window_start,
          date_trunc('hour', event_time) + INTERVAL 1 HOUR AS window_end,
          region,
          channel,
          customer_segment,
          SUM(CASE WHEN event_type = 'payment_authorized' THEN 1 ELSE 0 END) AS payment_authorized,
          SUM(CASE WHEN event_type = 'payment_failed' THEN 1 ELSE 0 END) AS payment_failed,
          CASE
            WHEN SUM(CASE WHEN event_type IN ('payment_authorized', 'payment_failed') THEN 1 ELSE 0 END) > 0
              THEN ROUND(
                SUM(CASE WHEN event_type = 'payment_failed' THEN 1 ELSE 0 END) /
                SUM(CASE WHEN event_type IN ('payment_authorized', 'payment_failed') THEN 1 ELSE 0 END),
                4
              )
            ELSE 0.0
          END AS payment_failure_rate,
          CAST({batch_id} AS BIGINT) AS batch_id,
          current_timestamp() AS processed_at
        FROM gold_payment_failure_scope
        GROUP BY date_trunc('hour', event_time), region, channel, customer_segment
        """
    )


def build_revenue_refund_gold_source(
    spark: SparkSession,
    silver_events_table: str,
    business_dates: list[str],
    batch_id: int,
) -> DataFrame | None:
    if not business_dates:
        return None

    scope = (
        spark.table(silver_events_table)
        .filter(col("event_type").isin("order_created", "refund_requested", "refund_completed"))
        .withColumn("business_date_key", expr("CAST(to_date(event_time) AS STRING)"))
        .filter(col("business_date_key").isin(business_dates))
    )
    scope.createOrReplaceTempView("gold_revenue_refund_scope")
    return spark.sql(
        f"""
        SELECT
          to_date(event_time) AS business_date,
          region,
          channel,
          customer_segment,
          ROUND(SUM(CASE WHEN event_type = 'order_created' THEN gross_amount ELSE 0.0 END), 2) AS gross_revenue,
          ROUND(SUM(CASE WHEN event_type = 'refund_requested' THEN requested_amount ELSE 0.0 END), 2) AS refunds_requested_amount,
          ROUND(SUM(CASE WHEN event_type = 'refund_completed' THEN approved_amount ELSE 0.0 END), 2) AS refunds_completed_amount,
          ROUND(
            SUM(CASE WHEN event_type = 'order_created' THEN gross_amount ELSE 0.0 END) -
            SUM(CASE WHEN event_type = 'refund_completed' THEN approved_amount ELSE 0.0 END),
            2
          ) AS net_revenue,
          SUM(CASE WHEN event_type = 'refund_requested' THEN 1 ELSE 0 END) AS refund_requested_count,
          SUM(CASE WHEN event_type = 'refund_completed' THEN 1 ELSE 0 END) AS refund_completed_count,
          CAST({batch_id} AS BIGINT) AS batch_id,
          current_timestamp() AS processed_at
        FROM gold_revenue_refund_scope
        GROUP BY to_date(event_time), region, channel, customer_segment
        """
    )


def write_batch_to_tables(query_name: str, tables: dict[str, str]):
    def _write(df: DataFrame, batch_id: int) -> None:
        if df.rdd.isEmpty():
            return

        spark = df.sparkSession
        materialized = df.withColumn("ingested_at", current_timestamp()).persist()

        invalid_count = materialized.filter(col("parse_status") != "parsed").count()
        if invalid_count:
            PARSE_FAILURE_COUNT.labels(query=query_name).inc(float(invalid_count))

        bronze_rows = merge_insert_only(
            spark,
            materialized.select(*BRONZE_COLUMNS),
            tables["bronze"],
            "t.topic = s.topic AND t.kafka_partition = s.kafka_partition AND t.kafka_offset = s.kafka_offset",
            BRONZE_COLUMNS,
            "bronze_batch_source",
        )
        record_table_write(query_name, "bronze", tables["bronze"], bronze_rows)

        quarantine_source = build_quarantine_source(materialized)
        quarantine_rows = merge_insert_only(
            spark,
            quarantine_source,
            tables["quarantine"],
            "t.topic = s.topic AND t.kafka_partition = s.kafka_partition AND t.kafka_offset = s.kafka_offset",
            QUARANTINE_COLUMNS,
            "quarantine_batch_source",
        )
        record_table_write(query_name, "quarantine", tables["quarantine"], quarantine_rows)
        for row in quarantine_source.select("quarantine_reason").where(col("quarantine_reason").isNotNull()).groupBy("quarantine_reason").count().collect():
            QUARANTINE_ROW_COUNT.labels(query=query_name, reason=row["quarantine_reason"]).inc(float(row["count"]))

        silver_event_source = build_silver_event_source(materialized)
        silver_event_rows = merge_insert_only(
            spark,
            silver_event_source,
            tables["silver_events"],
            "t.event_id = s.event_id",
            SILVER_EVENT_COLUMNS,
            "silver_event_batch_source",
        )
        record_table_write(query_name, "silver", tables["silver_events"], silver_event_rows)

        business_events = materialized.filter(
            (col("parse_status") == "parsed")
            & col("event_time").isNotNull()
            & (~col("event_type").isin(*TECHNICAL_EVENT_TYPES))
        )

        order_ids = collect_distinct_values(business_events, "order_id")
        payment_ids = collect_distinct_values(business_events, "payment_id")
        shipment_ids = collect_distinct_values(business_events, "shipment_id")
        refund_ids = collect_distinct_values(business_events, "refund_id")

        order_state_source = build_order_state_source(spark, tables["silver_events"], order_ids)
        if order_state_source is not None:
            rows = merge_overwrite_rows(
                spark,
                order_state_source,
                tables["silver_order_state"],
                "t.order_id = s.order_id",
                ORDER_STATE_COLUMNS,
                "silver_order_state_merge_source",
            )
            record_table_write(query_name, "silver", tables["silver_order_state"], rows)

        payment_state_source = build_payment_state_source(spark, tables["silver_events"], payment_ids)
        if payment_state_source is not None:
            rows = merge_overwrite_rows(
                spark,
                payment_state_source,
                tables["silver_payments"],
                "t.payment_id = s.payment_id",
                PAYMENT_COLUMNS,
                "silver_payment_merge_source",
            )
            record_table_write(query_name, "silver", tables["silver_payments"], rows)

        shipment_state_source = build_shipment_state_source(spark, tables["silver_events"], shipment_ids)
        if shipment_state_source is not None:
            rows = merge_overwrite_rows(
                spark,
                shipment_state_source,
                tables["silver_shipments"],
                "t.shipment_id = s.shipment_id",
                SHIPMENT_COLUMNS,
                "silver_shipment_merge_source",
            )
            record_table_write(query_name, "silver", tables["silver_shipments"], rows)

        refund_state_source = build_refund_state_source(spark, tables["silver_events"], refund_ids)
        if refund_state_source is not None:
            rows = merge_overwrite_rows(
                spark,
                refund_state_source,
                tables["silver_refunds"],
                "t.refund_id = s.refund_id",
                REFUND_COLUMNS,
                "silver_refund_merge_source",
            )
            record_table_write(query_name, "silver", tables["silver_refunds"], rows)

        minute_keys = collect_distinct_expression(
            business_events.filter(col("event_type").isin(*MINUTE_METRIC_EVENT_TYPES)),
            "CAST(date_trunc('minute', event_time) AS STRING)",
            "window_key",
        )
        minute_gold_source = build_minute_gold_source(spark, tables["silver_events"], minute_keys, batch_id)
        if minute_gold_source is not None:
            rows = merge_overwrite_rows(
                spark,
                minute_gold_source,
                tables["gold_minute"],
                "t.window_start = s.window_start AND t.region <=> s.region AND t.channel <=> s.channel AND t.customer_segment <=> s.customer_segment",
                MINUTE_GOLD_COLUMNS,
                "gold_minute_merge_source",
            )
            record_table_write(query_name, "gold", tables["gold_minute"], rows)

        business_dates = collect_distinct_expression(
            business_events.filter(col("event_type").isin(*FUNNEL_EVENT_TYPES, "order_created", "refund_requested", "refund_completed")),
            "CAST(to_date(event_time) AS STRING)",
            "business_date_key",
        )
        funnel_gold_source = build_funnel_gold_source(spark, tables["silver_events"], business_dates, batch_id)
        if funnel_gold_source is not None:
            rows = merge_overwrite_rows(
                spark,
                funnel_gold_source,
                tables["gold_funnel"],
                "t.business_date = s.business_date AND t.region <=> s.region AND t.channel <=> s.channel AND t.customer_segment <=> s.customer_segment",
                FUNNEL_GOLD_COLUMNS,
                "gold_funnel_merge_source",
            )
            record_table_write(query_name, "gold", tables["gold_funnel"], rows)

        payment_hour_keys = collect_distinct_expression(
            business_events.filter(col("event_type").isin("payment_authorized", "payment_failed")),
            "CAST(date_trunc('hour', event_time) AS STRING)",
            "hour_key",
        )
        payment_failure_gold_source = build_payment_failure_gold_source(
            spark,
            tables["silver_events"],
            payment_hour_keys,
            batch_id,
        )
        if payment_failure_gold_source is not None:
            rows = merge_overwrite_rows(
                spark,
                payment_failure_gold_source,
                tables["gold_payment_failure"],
                "t.window_start = s.window_start AND t.region <=> s.region AND t.channel <=> s.channel AND t.customer_segment <=> s.customer_segment",
                PAYMENT_FAILURE_GOLD_COLUMNS,
                "gold_payment_failure_merge_source",
            )
            record_table_write(query_name, "gold", tables["gold_payment_failure"], rows)

        revenue_refund_gold_source = build_revenue_refund_gold_source(
            spark,
            tables["silver_events"],
            business_dates,
            batch_id,
        )
        if revenue_refund_gold_source is not None:
            rows = merge_overwrite_rows(
                spark,
                revenue_refund_gold_source,
                tables["gold_revenue_refund"],
                "t.business_date = s.business_date AND t.region <=> s.region AND t.channel <=> s.channel AND t.customer_segment <=> s.customer_segment",
                REVENUE_REFUND_GOLD_COLUMNS,
                "gold_revenue_refund_merge_source",
            )
            record_table_write(query_name, "gold", tables["gold_revenue_refund"], rows)

        materialized.unpersist()

    return _write


def main() -> None:
    args = parse_args()
    start_http_server(args.metrics_port)

    if args.output_table:
        args.gold_table = args.output_table

    spark = SparkSession.builder.appName("commerce-events-streaming").getOrCreate()
    ensure_bronze_table(spark, args.bronze_table)
    ensure_quarantine_table(spark, args.quarantine_table)
    ensure_silver_events_table(spark, args.silver_events_table)
    ensure_silver_order_state_table(spark, args.silver_order_state_table)
    ensure_silver_payments_table(spark, args.silver_payments_table)
    ensure_silver_shipments_table(spark, args.silver_shipments_table)
    ensure_silver_refunds_table(spark, args.silver_refunds_table)
    ensure_gold_table(spark, args.gold_table)
    ensure_gold_funnel_table(spark, args.gold_funnel_table)
    ensure_gold_payment_failure_table(spark, args.gold_payment_failure_table)
    ensure_gold_revenue_refund_table(spark, args.gold_revenue_refund_table)

    source = (
        spark.readStream.format("kafka")
        .option("kafka.bootstrap.servers", args.kafka_bootstrap_servers)
        .option("subscribe", args.kafka_topic)
        .option("startingOffsets", args.starting_offsets)
        .option("failOnDataLoss", "false")
        .load()
    )

    parsed = build_parsed_stream(source)
    tables = {
        "bronze": args.bronze_table,
        "quarantine": args.quarantine_table,
        "silver_events": args.silver_events_table,
        "silver_order_state": args.silver_order_state_table,
        "silver_payments": args.silver_payments_table,
        "silver_shipments": args.silver_shipments_table,
        "silver_refunds": args.silver_refunds_table,
        "gold_minute": args.gold_table,
        "gold_funnel": args.gold_funnel_table,
        "gold_payment_failure": args.gold_payment_failure_table,
        "gold_revenue_refund": args.gold_revenue_refund_table,
    }

    query = (
        parsed.withWatermark("event_time", args.watermark_delay)
        .writeStream.queryName(args.query_name)
        .foreachBatch(write_batch_to_tables(args.query_name, tables))
        .option("checkpointLocation", args.checkpoint_location)
        .trigger(processingTime=args.trigger_processing_time)
        .start()
    )

    print(
        "[commerce-events-streaming] started "
        f"query={args.query_name} topics={args.kafka_topic} starting_offsets={args.starting_offsets} "
        f"checkpoint={args.checkpoint_location} bronze_table={args.bronze_table} "
        f"silver_events_table={args.silver_events_table} silver_order_state_table={args.silver_order_state_table} "
        f"gold_minute_table={args.gold_table} gold_funnel_table={args.gold_funnel_table} "
        f"gold_payment_failure_table={args.gold_payment_failure_table} "
        f"gold_revenue_refund_table={args.gold_revenue_refund_table}"
    )

    try:
        while True:
            terminated = query.awaitTermination(10)
            progress = query.lastProgress
            if progress is not None:
                update_stream_metrics(args.query_name, progress)
            if terminated:
                break

        if query.exception() is not None:
            raise RuntimeError(str(query.exception()))
    except Exception:
        FAILURE_COUNT.labels(query=args.query_name).inc()
        raise
    finally:
        spark.stop()


if __name__ == "__main__":
    main()
