"""Apply db/migrations/*.sql in filename order, once each.

Runs as a Kubernetes Job before each rollout and from docker-compose locally.
All pending files apply in one transaction under an advisory lock, so a failed
migration leaves the schema unchanged and two runners can't race.
"""

import argparse
import logging
from pathlib import Path

import psycopg

from li_common.config import env

logger = logging.getLogger(__name__)

_LOCK_ID = 6030_0001


def apply(conninfo: str, migrations_dir: Path) -> list[str]:
    files = sorted(migrations_dir.glob("*.sql"))
    with psycopg.connect(conninfo) as conn:
        conn.execute("SELECT pg_advisory_xact_lock(%s)", (_LOCK_ID,))
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS schema_migrations (
                version     text PRIMARY KEY,
                applied_at  timestamptz NOT NULL DEFAULT now()
            )
            """
        )
        applied = {r[0] for r in conn.execute("SELECT version FROM schema_migrations")}
        pending = [f for f in files if f.name not in applied]
        for path in pending:
            logger.info("applying %s", path.name)
            conn.execute(path.read_text())
            conn.execute("INSERT INTO schema_migrations (version) VALUES (%s)", (path.name,))
    return [p.name for p in pending]


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("migrations_dir", type=Path)
    parser.add_argument("--database-url", default=env("DATABASE_URL"))
    args = parser.parse_args(argv)
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    applied = apply(args.database_url, args.migrations_dir)
    logger.info("applied %d migration(s)", len(applied))


if __name__ == "__main__":
    main()
