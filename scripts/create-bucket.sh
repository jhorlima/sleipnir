#!/usr/bin/env bash
# Runs inside the aws-cli container (see compose/storage.yaml).
set -euo pipefail

if aws s3api head-bucket --bucket "$S3_BUCKET" 2>/dev/null; then
  echo "Bucket $S3_BUCKET already exists"
  exit 0
fi

aws s3api create-bucket --bucket "$S3_BUCKET"
echo "Bucket $S3_BUCKET created"
