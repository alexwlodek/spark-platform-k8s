from __future__ import annotations

import argparse
from datetime import datetime, timezone

from prometheus_client import Counter, Gauge, start_http_server
from pyspark.sql import DataFrame, SparkSession
from pyspark.sql.functions import (
    col,
    current_timestamp,
    date_trunc,
    expr,
    get_json_object,
    lit,
    round as spark_round,
    sum as spark_sum,
    to_timestamp,
    when,
)

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


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Commerce Structured Streaming job")
    parser.add_argument("--kafka-bootstrap-servers", default="streaming-kafka.apps.svc.cluster.local:9092")
    parser.add_argument(
        "--kafka-topic",
        default="commerce.order.lifecycle.v1,commerce.payment.events.v1,commerce.generator.technical.v1",
    )
    parser.add_argument("--window-duration", default="1 minute")
    parser.add_argument("--watermark-delay", default="2 minutes")
    parser.add_argument("--checkpoint-location", required=True)
    parser.add_argument("--bronze-table", default="iceberg_nessie.streaming.bronze_commerce_events")
    parser.add_argument("--gold-table", default="iceberg_nessie.streaming.gold_order_metrics_minute")
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
        .withColumn("payload_json", get_json_object(col("raw_json"), "$.payload"))
        .withColumn(
            "parse_status",
            when(
                col("event_id").isNotNull() & col("event_type").isNotNull() & col("event_time").isNotNull(),
                lit("parsed"),
            ).otherwise(lit("invalid")),
        )
        .withColumn(
            "channel",
            when(col("event_type") == "order_created", get_json_object(col("raw_json"), "$.payload.channel")).otherwise(
                get_json_object(col("raw_json"), "$.payload.channel")
            ),
        )
        .withColumn("region", get_json_object(col("raw_json"), "$.payload.region"))
        .withColumn("customer_segment", get_json_object(col("raw_json"), "$.payload.customer_segment"))
        .withColumn(
            "amount",
            when(
                col("event_type") == "order_created",
                get_json_object(col("raw_json"), "$.payload.grand_total").cast("double"),
            ).otherwise(get_json_object(col("raw_json"), "$.payload.amount").cast("double")),
        )
        .withColumn(
            "payment_status",
            when(col("event_type") == "payment_authorized", lit("authorized"))
            .when(col("event_type") == "payment_failed", lit("failed"))
            .otherwise(lit(None)),
        )
        .withColumn(
            "payment_failure_reason_group",
            get_json_object(col("raw_json"), "$.payload.failure_reason_group"),
        )
    )
    return parsed


def write_batch_to_tables(query_name: str, bronze_table: str, gold_table: str):
    def _write(df: DataFrame, batch_id: int) -> None:
        if df.rdd.isEmpty():
            return

        materialized = df.withColumn("ingested_at", current_timestamp()).persist()

        invalid_count = materialized.filter(col("parse_status") != "parsed").count()
        if invalid_count:
            PARSE_FAILURE_COUNT.labels(query=query_name).inc(float(invalid_count))

        bronze_df = materialized.select(
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
        )
        bronze_df.writeTo(bronze_table).append()

        gold_source = materialized.filter(
            (col("parse_status") == "parsed")
            & col("event_type").isin("order_created", "payment_authorized", "payment_failed")
            & col("event_time").isNotNull()
        )

        if not gold_source.rdd.isEmpty():
            aggregated = (
                gold_source.withColumn("window_start", date_trunc("minute", col("event_time")))
                .withColumn("window_end", expr("window_start + INTERVAL 1 MINUTE"))
                .groupBy("window_start", "window_end", "region", "channel", "customer_segment")
                .agg(
                    spark_sum(when(col("event_type") == "order_created", 1).otherwise(0)).alias("orders_created"),
                    spark_sum(when(col("event_type") == "payment_authorized", 1).otherwise(0)).alias(
                        "payment_authorized"
                    ),
                    spark_sum(when(col("event_type") == "payment_failed", 1).otherwise(0)).alias("payment_failed"),
                    spark_sum(when(col("event_type") == "order_created", col("amount")).otherwise(lit(0.0))).alias(
                        "gross_revenue"
                    ),
                )
                .withColumn("gross_revenue", spark_round(col("gross_revenue"), 2))
                .withColumn(
                    "payment_failure_rate",
                    when(
                        (col("payment_authorized") + col("payment_failed")) > 0,
                        spark_round(
                            col("payment_failed") / (col("payment_authorized") + col("payment_failed")),
                            4,
                        ),
                    ).otherwise(lit(0.0)),
                )
                .withColumn("batch_id", lit(batch_id))
                .withColumn("processed_at", current_timestamp())
            )
            aggregated.writeTo(gold_table).append()

        materialized.unpersist()

    return _write


def main() -> None:
    args = parse_args()
    start_http_server(args.metrics_port)

    if args.output_table:
        args.gold_table = args.output_table

    spark = SparkSession.builder.appName("commerce-events-streaming").getOrCreate()
    ensure_bronze_table(spark, args.bronze_table)
    ensure_gold_table(spark, args.gold_table)

    source = (
        spark.readStream.format("kafka")
        .option("kafka.bootstrap.servers", args.kafka_bootstrap_servers)
        .option("subscribe", args.kafka_topic)
        .option("startingOffsets", "latest")
        .option("failOnDataLoss", "false")
        .load()
    )

    parsed = build_parsed_stream(source)

    query = (
        parsed.withWatermark("event_time", args.watermark_delay)
        .writeStream.queryName(args.query_name)
        .foreachBatch(write_batch_to_tables(args.query_name, args.bronze_table, args.gold_table))
        .option("checkpointLocation", args.checkpoint_location)
        .trigger(processingTime=args.trigger_processing_time)
        .start()
    )

    print(
        "[commerce-events-streaming] started "
        f"query={args.query_name} topics={args.kafka_topic} checkpoint={args.checkpoint_location} "
        f"bronze_table={args.bronze_table} gold_table={args.gold_table}"
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
