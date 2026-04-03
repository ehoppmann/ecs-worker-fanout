FROM python:3.13-slim

RUN pip install --no-cache-dir boto3

WORKDIR /app
COPY scheduler.py worker.py ./
