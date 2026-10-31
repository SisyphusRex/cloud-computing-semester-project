"""Who am I, and user administration (ADRs 0002 and 0003).

Admins invite emails as students or professors, change roles (their own
included), grant and revoke admin, and disable accounts. Nobody can disable
themselves or change their own admin flag, so the API always leaves an admin.
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
def delete_invitation(user_id: int):
    """Only invitations nobody has claimed; accounts in use are disabled instead,
    because their courses and audit history reference them."""
    with db.connection() as conn:
        row = conn.execute(
            "SELECT email, google_sub FROM users WHERE id = %s", (user_id,)
        ).fetchone()
        if row is None:
            abort(404, "User not found")
        if row["google_sub"] is not None:
            abort(409, "This account has signed in; disable it instead")
        # The audit row outlives the user (target_id becomes NULL), so keep the email.
        users.audit(conn, g.user.id, user_id, "delete_invitation", email=row["email"])
        conn.execute("DELETE FROM users WHERE id = %s", (user_id,))
    log_event(logger, "invitation_deleted", actor_id=g.user.id, target_id=user_id)
    return "", 204
