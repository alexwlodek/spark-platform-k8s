FROM python:3.11-slim-bookworm

ARG SPARK_VERSION=3.5.2
ARG HADOOP_PROFILE=3
ARG SPARK_UID=185

ENV SPARK_HOME=/opt/spark
ENV PATH="${SPARK_HOME}/bin:${PATH}"

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    curl \
    openjdk-17-jre-headless \
    tini \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL "https://archive.apache.org/dist/spark/spark-${SPARK_VERSION}/spark-${SPARK_VERSION}-bin-hadoop${HADOOP_PROFILE}.tgz" \
    | tar -xz -C /opt \
    && ln -s "/opt/spark-${SPARK_VERSION}-bin-hadoop${HADOOP_PROFILE}" "${SPARK_HOME}" \
    && adduser --disabled-password --gecos "" --uid "${SPARK_UID}" spark \
    && chown -R spark:spark "/opt/spark-${SPARK_VERSION}-bin-hadoop${HADOOP_PROFILE}"

WORKDIR /opt/spark/work-dir
COPY job.py /opt/spark/work-dir/job.py
COPY entrypoint.sh /opt/entrypoint.sh
RUN chmod +x /opt/entrypoint.sh

USER spark

ENTRYPOINT ["/opt/entrypoint.sh"]
