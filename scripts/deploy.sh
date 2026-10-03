#!/usr/bin/env bash
set -euo pipefail

IMAGE="${GHCR_IMAGE:?must set GHCR_IMAGE}"
TAG="${IMAGE_TAG:?must set IMAGE_TAG}"
CONTAINER_NAME="fastapi-demo"
PORT="${APP_PORT:-80}"

echo "Pulling ${IMAGE}:${TAG}..."
docker pull "${IMAGE}:${TAG}"

echo "Stopping old container (if any)..."
docker stop "${CONTAINER_NAME}" 2>/dev/null || true
docker rm "${CONTAINER_NAME}" 2>/dev/null || true

echo "Starting new container..."
docker run -d \
  --name "${CONTAINER_NAME}" \
  --restart unless-stopped \
  -p "${PORT}:8000" \
  "${IMAGE}:${TAG}"

echo "Waiting for health check..."
for _ in $(seq 1 10); do
  if curl -fs "http://localhost:${PORT}/health" >/dev/null; then
    echo "Deployed successfully."
    exit 0
  fi
  sleep 2
done

echo "Health check failed after deploy." >&2
exit 1
