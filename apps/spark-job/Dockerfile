FROM apache/spark:3.5.2-scala2.12-java17-python3-ubuntu

WORKDIR /opt/spark/work-dir
COPY job.py /opt/spark/work-dir/job.py
USER root
RUN chown 185:0 /opt/spark/work-dir/job.py

USER 185
