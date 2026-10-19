"""User accounts: invitations, role changes, and their audit trail (ADR 0002).

Sign-in is invite-only. An invitation is a users row with no google_sub; the
first sign-in with a matching verified email claims it (see auth.load_user).
Used by the Ingest API's admin endpoints and the li-admin CLI, on a connection
the caller owns, so each change and its audit row commit together.
"""

from psycopg.types.json import Jsonb

ROLES = ("student", "professor")
_UPDATABLE = {"role", "is_active", "is_admin", "is_superuser"}

COLUMNS = "id, email, name, role, is_admin, is_superuser, is_active"
# What the admin page shows; status is derived, not stored.
ADMIN_COLUMNS = f"""
    {COLUMNS}, created_at,
    CASE WHEN NOT is_active THEN 'disabled'
         WHEN google_sub IS NULL THEN 'invited'
         ELSE 'active' END AS status
"""


def normalize_email(email: str) -> str:
    return email.strip().lower()


def audit(conn, actor_id: int | None, target_id: int, action: str, **detail) -> None:
    conn.execute(
        "INSERT INTO user_audit (actor_id, target_id, action, detail) VALUES (%s, %s, %s, %s)",
        (actor_id, target_id, action, Jsonb(detail)),
    )


def find_by_email(conn, email: str) -> dict | None:
    return conn.execute(
        f"SELECT {ADMIN_COLUMNS} FROM users WHERE lower(email) = %s", (normalize_email(email),)
    ).fetchone()


def invite(conn, email: str, role: str, actor_id: int | None) -> dict | None:
    """Create an invitation; returns None if the email already has a row."""
    row = conn.execute(
        f"""
        INSERT INTO users (email, role, invited_by) VALUES (%s, %s, %s)
        ON CONFLICT ((lower(email))) DO NOTHING
        RETURNING {ADMIN_COLUMNS}
        """,
        (normalize_email(email), role, actor_id),
    ).fetchone()
    if row:
        audit(conn, actor_id, row["id"], "invite", role=role)
    return row


def update(conn, user_id: int, actor_id: int | None, **changes) -> dict | None:
    """Set the given columns (role, is_active, is_admin, is_superuser) and audit
    the ones that actually changed. Returns the updated row, or None if missing."""
    if unknown := changes.keys() - _UPDATABLE:
        raise ValueError(f"not updatable: {sorted(unknown)}")
    before = conn.execute(
        f"SELECT {ADMIN_COLUMNS} FROM users WHERE id = %s FOR UPDATE", (user_id,)
    ).fetchone()
    if before is None:
        return None
    changed = {k: v for k, v in changes.items() if before[k] != v}
    if not changed:
        return before
    assignments = ", ".join(f"{column} = %({column})s" for column in changed)
    after = conn.execute(
        f"UPDATE users SET {assignments} WHERE id = %(id)s RETURNING {ADMIN_COLUMNS}",
        {**changed, "id": user_id},
    ).fetchone()
    audit(
        conn,
        actor_id,
        user_id,
        "update",
        **{k: {"from": before[k], "to": v} for k, v in changed.items()},
    )
    return after
