"""CLI wrapper for idempotent labeled demo data seeding (`SPEC_V2 §6`)."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

BACKEND_ROOT = Path(__file__).resolve().parents[1]
if str(BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(BACKEND_ROOT))

from app.core.settings import get_settings
from app.db.demo_seed import DEMO_PREFIX, clear_demo_data, seed_demo_data
from app.db.engine import ensure_schema_ready, make_session_factory
from app.db.repository import V2Repository

__all__ = ["DEMO_PREFIX", "clear_demo_data", "seed_demo_data", "main"]


def main() -> None:
    parser = argparse.ArgumentParser(description="Seed labeled V2 demo visits & stats data.")
    parser.add_argument("--worker-id", default="asha_001")
    parser.add_argument("--clear", action="store_true", help="Remove demo_seed_* rows instead.")
    args = parser.parse_args()

    settings = get_settings()
    engine = ensure_schema_ready(settings.DATABASE_URL)
    try:
        repo = V2Repository(make_session_factory(engine))
        if args.clear:
            count = clear_demo_data(repo, worker_id=args.worker_id)
            print(f"Removed {count} demo_seed_* rows for {args.worker_id}.")
        else:
            res = seed_demo_data(repo, worker_id=args.worker_id)
            print(
                f"Demo seed complete for {args.worker_id}: "
                f"+{res['beneficiaries_created']} beneficiaries, +{res['visits_created']} visits."
            )
    finally:
        engine.dispose()


if __name__ == "__main__":
    main()
