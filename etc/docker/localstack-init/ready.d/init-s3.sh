#!/usr/bin/env bash
# Creates S3 buckets when LocalStack becomes ready (runs inside the LocalStack container).
set -e
export AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_DEFAULT_REGION=us-east-1
awslocal s3api create-bucket --bucket media || true
awslocal s3api put-bucket-cors --bucket media --cors-configuration file:///config/s3_bucket_cors_rules.json || true
awslocal s3api create-bucket --bucket expense-reports || true
echo "S3 buckets (media, expense-reports) initialized"
