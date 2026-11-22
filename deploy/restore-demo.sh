#!/usr/bin/env bash
# Clear and re-seed clearly labeled demo beneficiaries & 14-day Insights visits
# (`demo_seed_*` / "Demo ..." rows) for repeatability before a hackathon demo.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

WORKER_ID="${1:-asha_001}"
BACKEND_CID="$(docker compose ps -q backend 2>/dev/null || true)"

if [[ -n "$BACKEND_CID" ]]; then
  echo "==> Resetting labeled demo data inside running backend container for worker '${WORKER_ID}'..."
  docker compose exec -T backend python scripts/seed_demo_stats.py --worker-id "$WORKER_ID" --clear
  docker compose exec -T backend python scripts/seed_demo_stats.py --worker-id "$WORKER_ID"
else
  echo "==> Backend container not running; seeding local database for worker '${WORKER_ID}'..."
  PYTHON_BIN="python3"
  if [[ -x backend/.venv/bin/python ]]; then
    PYTHON_BIN="backend/.venv/bin/python"
  fi
  "$PYTHON_BIN" backend/scripts/seed_demo_stats.py --worker-id "$WORKER_ID" --clear
  "$PYTHON_BIN" backend/scripts/seed_demo_stats.py --worker-id "$WORKER_ID"
fi

echo "Demo data restored (all demo beneficiaries are prefixed with 'Demo ')."
