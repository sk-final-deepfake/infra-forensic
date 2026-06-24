"""Publish one test analysis job to RabbitMQ (in-cluster)."""
import json
import os
import sys

import pika

body = {
    "analysisRequestId": int(os.getenv("TEST_ANALYSIS_REQUEST_ID", "99901")),
    "evidenceId": int(os.getenv("TEST_EVIDENCE_ID", "9991")),
    "fileType": "video",
    "filePath": os.getenv("TEST_S3_KEY", "cases/demo/1001/copy/sample.mp4"),
    "s3ObjectKey": os.getenv("TEST_S3_KEY", "cases/demo/1001/copy/sample.mp4"),
    "s3Bucket": os.getenv("S3_EVIDENCE_BUCKET", "forenshield-evidence-877044078824"),
    "s3Region": "ap-northeast-2",
    "presignedDownloadUrl": "",
    "originalHash": "pipeline-smoke-test",
    "originalSha256": "pipeline-smoke-test",
    "caseName": "GPU-Pipeline-Smoke-Test",
    "requestedAt": "2026-06-19T04:40:00Z",
}

credentials = pika.PlainCredentials(
    os.getenv("RABBITMQ_USER", "forenshield"),
    os.getenv("RABBITMQ_PASSWORD", ""),
)
params = pika.ConnectionParameters(
    host=os.getenv("RABBITMQ_HOST", "rabbitmq.forenshield.svc.cluster.local"),
    port=int(os.getenv("RABBITMQ_AMQP_PORT", os.getenv("RABBITMQ_SERVICE_PORT", "5672")).split(":")[-1]),
    virtual_host="/",
    credentials=credentials,
)
connection = pika.BlockingConnection(params)
channel = connection.channel()
channel.basic_publish(
    exchange=os.getenv("ANALYSIS_EXCHANGE", "ai.analysis.exchange"),
    routing_key=os.getenv("ANALYSIS_ROUTING_KEY", "analyze.video"),
    body=json.dumps(body).encode("utf-8"),
    properties=pika.BasicProperties(content_type="application/json", delivery_mode=2),
)
connection.close()
print("published", json.dumps(body))
