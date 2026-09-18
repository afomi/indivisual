#!/bin/bash
set -euo pipefail

IMAGE="$1"

# Refresh env from Secrets Manager. This is why a deploy picks up secret
# changes (GITHUB_CLIENT_ID, CLOAK_KEY, ...) without a Terraform apply.
SECRETS=$(aws secretsmanager get-secret-value --secret-id indivisual/prod --region us-east-1 --query SecretString --output text)
echo "$SECRETS" | jq -r 'to_entries[] | "\(.key)=\(.value)"' > /opt/indivisual.env
echo PHX_SERVER=true >> /opt/indivisual.env
echo PORT=8080 >> /opt/indivisual.env

# POOL_SIZE is deliberately NOT hardcoded here. The shared RDS has a ~400
# connection ceiling across the whole fleet; per-app pool size belongs in the
# app's secret (config/runtime.exs defaults to 5 when unset). Writing it here
# would silently override the secret.
if ! grep -q '^POOL_SIZE=' /opt/indivisual.env; then
  echo POOL_SIZE=5 >> /opt/indivisual.env
fi

# Pull latest image
ECR_REGISTRY=$(aws sts get-caller-identity --query Account --output text).dkr.ecr.us-east-1.amazonaws.com
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin "$ECR_REGISTRY"
docker pull "$IMAGE"

# Restart container
docker stop indivisual 2>/dev/null || true
docker rm indivisual 2>/dev/null || true
INSTANCE_ID=$(ec2-metadata -i | cut -d' ' -f2)
docker run -d --name indivisual --restart unless-stopped --env-file /opt/indivisual.env --network host \
  --log-driver=awslogs --log-opt awslogs-region=us-east-1 --log-opt awslogs-group=/app/indivisual --log-opt awslogs-stream="$INSTANCE_ID" \
  "$IMAGE"

# Explicit success: confirm the container is actually running, not just that
# `docker run` returned 0 (it can exit 0 and the app crash a second later).
sleep 5
if ! docker ps --filter "name=^indivisual$" --filter "status=running" --format '{{.Names}}' | grep -q '^indivisual$'; then
  echo "ERROR: container 'indivisual' is not running after start. Recent logs:"
  docker logs --tail 50 indivisual 2>&1 || true
  exit 1
fi
echo "OK: container indivisual is running"
