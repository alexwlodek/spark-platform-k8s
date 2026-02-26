from __future__ import annotations

import argparse
from datetime import datetime, timezone

from prometheus_client import Counter, Gauge, start_http_server
from pyspark.sql import DataFrame, SparkSession
from pyspark.sql.functions import col, count, from_json, lit, round as spark_round, sum as spark_sum, to_timestamp, window
from pyspark.sql.types import DoubleType, IntegerType, StringType, StructField, StructType

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


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Orders Structured Streaming job")
    parser.add_argument("--kafka-bootstrap-servers", default="streaming-kafka.apps.svc.cluster.local:9092")
    parser.add_argument("--kafka-topic", default="orders")
    parser.add_argument("--window-duration", default="1 minute")
    parser.add_argument("--watermark-delay", default="2 minutes")
    parser.add_argument("--checkpoint-location", required=True)
    parser.add_argument("--output-path", required=True)
    parser.add_argument("--query-name", default="orders_revenue_per_minute")
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


def write_batch(output_path: str):
    def _write(df: DataFrame, batch_id: int) -> None:
        if df.rdd.isEmpty():
            return

        (
            df.withColumn("batch_id", lit(batch_id))
            .write.mode("append")
            .parquet(output_path)
        )

    return _write


def main() -> None:
    args = parse_args()
    start_http_server(args.metrics_port)

    spark = SparkSession.builder.appName("orders-streaming").getOrCreate()

    schema = StructType(
        [
            StructField("event_id", StringType(), False),
            StructField("event_time", StringType(), False),
            StructField("order_id", StringType(), False),
            StructField("customer_id", StringType(), False),
            StructField("items", IntegerType(), False),
            StructField("amount", DoubleType(), False),
            StructField("currency", StringType(), False),
            StructField("region", StringType(), False),
        ]
    )

    source = (
        spark.readStream.format("kafka")
        .option("kafka.bootstrap.servers", args.kafka_bootstrap_servers)
        .option("subscribe", args.kafka_topic)
        .option("startingOffsets", "latest")
        .option("failOnDataLoss", "false")
        .load()
    )

    parsed = (
        source.selectExpr("CAST(value AS STRING) AS payload")
        .select(from_json(col("payload"), schema).alias("event"))
        .select("event.*")
        .withColumn("event_time", to_timestamp(col("event_time")))
        .where(col("event_time").isNotNull())
    )

    aggregated = (
        parsed.withWatermark("event_time", args.watermark_delay)
        .groupBy(window(col("event_time"), args.window_duration).alias("window"))
        .agg(
            count("*").alias("events"),
            spark_round(spark_sum(col("amount")), 2).alias("revenue"),
        )
        .select(
            col("window.start").alias("window_start"),
            col("window.end").alias("window_end"),
            col("events"),
            col("revenue"),
        )
    )

    query = (
        aggregated.writeStream.outputMode("append")
        .queryName(args.query_name)
        .foreachBatch(write_batch(args.output_path))
        .option("checkpointLocation", args.checkpoint_location)
        .trigger(processingTime=args.trigger_processing_time)
        .start()
    )

    print(
        "[orders-streaming] started "
        f"query={args.query_name} topic={args.kafka_topic} checkpoint={args.checkpoint_location} output={args.output_path}"
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
