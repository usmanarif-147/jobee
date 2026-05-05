#!/bin/sh
# Creates the MinIO buckets the platform expects.
# Run automatically by the `minio-init` container after MinIO is healthy.
# Idempotent — safe to re-run.

set -e

ENDPOINT="http://minio:9000"
ALIAS="jobee"
BUCKETS="resumes chat-files reports company-assets avatars"

echo "[seed-buckets] waiting for MinIO at $ENDPOINT ..."
until mc alias set "$ALIAS" "$ENDPOINT" "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null 2>&1; do
  sleep 2
done
echo "[seed-buckets] connected."

for bucket in $BUCKETS; do
  if mc ls "$ALIAS/$bucket" >/dev/null 2>&1; then
    echo "[seed-buckets] bucket exists:  $bucket"
  else
    mc mb "$ALIAS/$bucket"
    echo "[seed-buckets] bucket created: $bucket"
  fi
done

echo "[seed-buckets] done."
