FROM python:3.11-slim

WORKDIR /app
ENV PYTHONUNBUFFERED=1
ENV PYTHONPATH=/app/src

COPY generator.py /app/generator.py
COPY src /app/src
COPY schemas /app/schemas
COPY samples /app/samples
COPY docs /app/docs

RUN pip install --no-cache-dir \
  kafka-python==2.0.2 \
  jsonschema==4.25.1 \
  prometheus-client==0.21.1

CMD ["python", "/app/generator.py"]
