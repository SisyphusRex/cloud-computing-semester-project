"""Manage user accounts from the command line, like Django's manage.py
createsuperuser. Connects with database-admin credentials, the same way as
li-migrate (DATABASE_URL, password in PGPASSWORD).

  li-admin create-admin EMAIL
  li-admin add-user EMAIL --role student|professor [--admin]
  li-admin list

How the first admin is made; after that, admins can grant admin on the Admin
page (ADR 0003). Every command is idempotent and audited with actor_id NULL. In
prod, run it with `make cloud-admin ARGS="..."` (scripts/cloud-admin.sh).
"""

import argparse
import logging

import psycopg
from psycopg.rows import dict_row

from li_common import users
from li_common.config import env

logger = logging.getLogger(__name__)


def add_user(conn, email: str, role: str | None = None, *, admin: bool = False) -> dict:
    """Invite `email`, or update its existing row. `role` replaces the current
    role, and `role=None` keeps it; the admin flag is only ever turned on."""
    row = users.find_by_email(conn, email)
    if row is None:
        row = users.invite(conn, email, role or "student", actor_id=None)
    changes = {}
    if role:
        changes["role"] = role
    if admin:
        changes["is_admin"] = True
    return users.update(conn, row["id"], actor_id=None, **changes)


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--database-url", default=env("DATABASE_URL"))
    commands = parser.add_subparsers(dest="command", required=True)
    create_admin = commands.add_parser("create-admin", help="make EMAIL an admin")
    create_admin.add_argument("email")
    add = commands.add_parser("add-user", help="invite EMAIL, or update its role")
    add.add_argument("email")
    add.add_argument("--role", choices=users.ROLES, required=True)
    add.add_argument("--admin", action="store_true", help="also make the user an admin")
    commands.add_parser("list", help="list all users")
    args = parser.parse_args(argv)
    logging.basicConfig(level=logging.INFO, format="%(message)s")

    with psycopg.connect(args.database_url, row_factory=dict_row) as conn:
        if args.command == "list":
            for row in conn.execute(f"SELECT {users.ADMIN_COLUMNS} FROM users ORDER BY email"):
                logger.info(_describe(row))
            return
        if args.command == "create-admin":
            row = add_user(conn, args.email, admin=True)
        else:
            row = add_user(conn, args.email, args.role, admin=args.admin)
        logger.info(_describe(row))


def _describe(row: dict) -> str:
    admin = "is_admin" if row["is_admin"] else ""
    return f"{row['email']}  {row['role']}  {row['status']}  {admin}".rstrip()


if __name__ == "__main__":
    main()
