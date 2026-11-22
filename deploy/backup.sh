#!/usr/bin/env bash
# Create a WAL-safe timestamped SQLite backup under ./backups/ using Python's
# built-in online sqlite3.Connection.backup() API.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

mkdir -p backups
STAMP="$(date -u +%Y%m%d_%H%M%S)"
OUT_FILE="backups/ashavaani_${STAMP}.db"

if [[ ! -f data/ashavaani.db ]]; then
  echo "ERROR: data/ashavaani.db not found. Start the stack first or verify DATABASE_URL." >&2
  exit 1
fi

BACKEND_CID="$(docker compose ps -q backend 2>/dev/null || true)"
if [[ -n "$BACKEND_CID" ]]; then
  echo "==> Backing up running container database via SQLite online backup API..."
  docker compose exec -T backend python -c "
import sqlite3
src = sqlite3.connect('/app/data/ashavaani.db', timeout=30.0)
dst = sqlite3.connect('/tmp/ashavaani_backup.db')
try:
    with dst:
        src.backup(dst)
finally:
    dst.close()
    src.close()
"
  docker compose cp backend:/tmp/ashavaani_backup.db "$OUT_FILE"
  docker compose exec -T backend rm -f /tmp/ashavaani_backup.db
else
  echo "==> Backend container not running; backing up local data/ashavaani.db directly..."
  python3 -c "
import sqlite3, sys
src = sqlite3.connect('data/ashavaani.db', timeout=30.0)
dst = sqlite3.connect(sys.argv[1])
try:
    with dst:
        src.backup(dst)
finally:
    dst.close()
    src.close()
" "$OUT_FILE"
fi

chmod 600 "$OUT_FILE"
ls -lh "$OUT_FILE"
echo "Backup saved to $OUT_FILE"
