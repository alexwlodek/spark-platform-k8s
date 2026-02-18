from __future__ import annotations

import argparse
import time

from pyspark.sql import SparkSession


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Spark demo workload")
    parser.add_argument(
        "records",
        nargs="?",
        type=int,
        default=100000,
        help="Number of records to generate",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()

    spark = SparkSession.builder.appName("demo-app").getOrCreate()
    start = time.time()

    df = spark.range(0, args.records)
    even_count = df.where("id % 2 = 0").count()
    odd_count = args.records - even_count

    elapsed = round(time.time() - start, 3)
    print(f"[demo-app] records={args.records} even={even_count} odd={odd_count} elapsed_s={elapsed}")

    spark.stop()


if __name__ == "__main__":
    main()
