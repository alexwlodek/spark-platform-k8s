FROM apache/spark:3.5.2-scala2.12-java17-python3-ubuntu

WORKDIR /opt/spark/work-dir
COPY job.py /opt/spark/work-dir/job.py
COPY streaming_job.py /opt/spark/work-dir/streaming_job.py
USER root
RUN python3 -m pip install --no-cache-dir prometheus-client==0.21.1 \
  && chown 185:0 /opt/spark/work-dir/job.py /opt/spark/work-dir/streaming_job.py

USER 185
