"""Apply db/migrations/*.sql in filename order, once each.

Runs as a Kubernetes Job before each rollout and from docker-compose locally.
All pending files apply in one transaction under an advisory lock, so a failed
migration leaves the schema unchanged and two runners can't race.

`--grant ROLE=USER` (or LI_MIGRATE_GRANTS="role=user,role=user") then grants the
group roles from 0002_app_roles.sql to the services' database users. On Cloud SQL
those are IAM users, which Terraform creates with no privileges.
"""

import argparse
import logging
from pathlib import Path

import psycopg
from psycopg import sql

from li_common.config import env

logger = logging.getLogger(__name__)

_LOCK_ID = 6030_0001


def parse_grants(values: list[str]) -> list[tuple[str, str]]:
    grants = []
    for value in values:
        role, sep, user = value.partition("=")
        if not sep or not role.strip() or not user.strip():
            raise ValueError(f"grant must look like ROLE=USER, got {value!r}")
        grants.append((role.strip(), user.strip()))
    return grants


def apply(conninfo: str, migrations_dir: Path, grants: list[tuple[str, str]] = ()) -> list[str]:
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
        for role, user in grants:
            logger.info("granting %s to %s", role, user)
            conn.execute(
                sql.SQL("GRANT {} TO {}").format(sql.Identifier(role), sql.Identifier(user))
            )
    return [p.name for p in pending]


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("migrations_dir", type=Path)
    parser.add_argument("--database-url", default=env("DATABASE_URL"))
    parser.add_argument(
        "--grant",
        action="append",
        metavar="ROLE=USER",
        default=[g for g in env("LI_MIGRATE_GRANTS").split(",") if g.strip()],
        help="grant a group role to a database user; repeatable",
    )
    args = parser.parse_args(argv)
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    applied = apply(args.database_url, args.migrations_dir, parse_grants(args.grant))
    logger.info("applied %d migration(s)", len(applied))


if __name__ == "__main__":
    main()
