"""Who am I, and user administration (ADRs 0002 and 0003).

Admins invite emails as students or professors, change roles (their own
included), grant and revoke admin, disable accounts, and delete them (ADR
0006). Nobody can disable or delete themselves or change their own admin flag,
so the API always leaves an admin.
The first admin comes from `li-admin create-admin`. Every change is audited in
user_audit, in the same transaction.
"""

import logging

from flask import Blueprint, abort, g, request

from li_common import db, users
from li_common.auth import require_user
from li_common.logs import log_event
from li_common.schemas import UserInvite, UserUpdate

logger = logging.getLogger(__name__)

bp = Blueprint("admin", __name__, url_prefix="/ingest")


@bp.get("/me")
@require_user()
def me():
    u = g.user
    return {
        "id": u.id,
        "email": u.email,
        "name": u.name,
        "role": u.role,
        "is_admin": u.is_admin,
    }


@bp.get("/admin/users")
@require_user(admin=True)
def list_users():
    with db.connection() as conn:
        rows = conn.execute(f"SELECT {users.ADMIN_COLUMNS} FROM users ORDER BY email").fetchall()
    return {"users": rows}


@bp.post("/admin/users")
@require_user(admin=True)
def invite_users():
    body = UserInvite.model_validate(request.get_json(silent=True) or {})
    created, existing = [], []
    with db.connection() as conn:
        for email in body.emails:
            row = users.invite(conn, email, body.role, actor_id=g.user.id)
            (created if row else existing).append(row or email)
    log_event(logger, "users_invited", actor_id=g.user.id, role=body.role, created=len(created))
    return {"created": created, "already_exists": existing}, 201


@bp.patch("/admin/users/<int:user_id>")
@require_user(admin=True)
def update_user(user_id: int):
    body = UserUpdate.model_validate(request.get_json(silent=True) or {})
    changes = body.model_dump(exclude_none=True)
    if user_id == g.user.id and changes.keys() - {"role"}:
        abort(403, "You can only change your own role")
    with db.connection() as conn:
        row = users.update(conn, user_id, actor_id=g.user.id, **changes)
    if row is None:
        abort(404, "User not found")
    log_event(logger, "user_updated", actor_id=g.user.id, target_id=user_id, **changes)
    return row


@bp.delete("/admin/users/<int:user_id>")
@require_user(admin=True)
def delete_user(user_id: int):
    """Deletes an invitation or an account. An account's courses go with it
    (lectures and segments cascade); audit rows they made keep a NULL actor."""
    if user_id == g.user.id:
        abort(403, "You can't delete your own account")
    with db.connection() as conn:
        row = conn.execute(
            """
            SELECT u.email, u.role, u.google_sub,
                   (SELECT count(*) FROM courses c WHERE c.owner_id = u.id) AS courses
            FROM users u WHERE u.id = %s FOR UPDATE
            """,
            (user_id,),
        ).fetchone()
        if row is None:
            abort(404, "User not found")
        # The audit row outlives the user (target_id becomes NULL), so keep the email.
        if row["google_sub"] is None:
            users.audit(conn, g.user.id, user_id, "delete_invitation", email=row["email"])
        else:
            users.audit(
                conn,
                g.user.id,
                user_id,
                "delete_user",
                email=row["email"],
                role=row["role"],
                courses_deleted=row["courses"],
            )
        conn.execute("DELETE FROM users WHERE id = %s", (user_id,))
    log_event(
        logger,
        "user_deleted",
        actor_id=g.user.id,
        target_id=user_id,
        invitation=row["google_sub"] is None,
        courses_deleted=row["courses"],
    )
    return "", 204
