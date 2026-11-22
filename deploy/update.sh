#!/usr/bin/env bash
# Pull latest deployment/app code from origin/saad, rebuild containers,
# show recent logs, and check /v1/health.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

mkdir -p data backups

echo "==> Pulling latest commits from origin/saad..."
git pull --ff-only origin saad

echo "==> Rebuilding and restarting backend + caddy..."
docker compose up -d --build

echo "==> Waiting 5s for backend startup & migrations..."
sleep 5

echo "==> Container status:"
docker compose ps

echo "==> Recent logs:"
docker compose logs --tail=30 backend caddy

echo "==> Running internal backend health check..."
docker compose exec -T backend python -c \
  "import urllib.request; print(urllib.request.urlopen('http://127.0.0.1:8000/v1/health', timeout=5).read().decode())"

if [[ -f .env ]]; then
  DOMAIN_VAL="$(grep -E '^DOMAIN=' .env | tail -n 1 | cut -d '=' -f2- | tr -d '[:space:]\"'\''' || true)"
  if [[ -n "$DOMAIN_VAL" && "$DOMAIN_VAL" != "your-subdomain.duckdns.org" ]]; then
    echo "==> Checking external HTTPS endpoint: https://${DOMAIN_VAL}/v1/health"
    curl -fsS "https://${DOMAIN_VAL}/v1/health"
    echo ""
  fi
fi
