"""Google ID token authentication and role checks.

The frontend sends the Google ID token from sign-in as `Authorization: Bearer ...`.
We verify its signature, issuer, audience, and expiry, then load the matching
user row. Sign-in is invite-only: the first sign-in claims an invitation for the
token's email (ADR 0002). Roles live in our database, not in the token, and are
read on every request, so role changes take effect immediately.
"""

import logging
from dataclasses import dataclass
from functools import wraps

import cachecontrol
import google.auth.transport.requests
import requests
from flask import abort, current_app, g, request
from google.oauth2 import id_token
from werkzeug.exceptions import Forbidden

from li_common import db, users
from li_common.config import Settings
from li_common.logs import log_event

logger = logging.getLogger(__name__)

# Caches Google's signing certs per their Cache-Control headers instead of
# fetching them on every request.
_google_request = google.auth.transport.requests.Request(
    session=cachecontrol.CacheControl(requests.Session())
)


@dataclass(frozen=True)
class User:
    id: int
    email: str
    name: str | None
    role: str
    is_admin: bool = False
    is_superuser: bool = False
    is_active: bool = True


# Named 403s, so the frontend can tell them apart (error "not_invited", ...).
class NotInvited(Forbidden):
    name = "Not Invited"
    description = "Your account hasn't been invited. Ask your instructor or an admin."


class AccountDisabled(Forbidden):
    name = "Account Disabled"
    description = "Your account has been disabled. Ask an admin."


def verify_token(token: str, settings: Settings) -> dict:
    """Return the token's claims, or abort with 401."""
    if settings.dev_auth and token.startswith("dev:"):
        email = token.removeprefix("dev:")
        return {"sub": f"dev|{email}", "email": email, "email_verified": True, "name": email}
    try:
        claims = id_token.verify_oauth2_token(token, _google_request, settings.google_client_id)
    except ValueError:
        abort(401, "Invalid or expired ID token")
    if not claims.get("email_verified"):
        abort(401, "Google account email is not verified")
    return claims


def load_user(claims: dict) -> User:
    email = users.normalize_email(claims["email"])
    name = claims.get("name")
    with db.connection() as conn:
        row = conn.execute(
            f"SELECT {users.COLUMNS} FROM users WHERE google_sub = %s", (claims["sub"],)
        ).fetchone()
        # Skip the write on the common path where nothing changed.
        if row and (row["email"] != email or row["name"] != name):
            # Keep the old email if another row (an invitation) already has the new one.
            row = conn.execute(
                f"""
                UPDATE users u SET name = %(name)s,
                    email = CASE WHEN EXISTS (
                        SELECT FROM users o WHERE lower(o.email) = %(email)s AND o.id <> u.id
                    ) THEN u.email ELSE %(email)s END
                WHERE id = %(id)s RETURNING {users.COLUMNS}
                """,
                {"name": name, "email": email, "id": row["id"]},
            ).fetchone()
        elif row is None:
            # First sign-in: claim the invitation for this email, if there is one.
            row = conn.execute(
                f"""
                UPDATE users SET google_sub = %s, name = %s
                WHERE lower(email) = %s AND google_sub IS NULL
                RETURNING {users.COLUMNS}
                """,
                (claims["sub"], name, email),
            ).fetchone()
            if row is None:
                log_event(logger, "sign_in_not_invited", logging.WARNING)
                raise NotInvited()
            log_event(logger, "user_claimed", user_id=row["id"], role=row["role"])
    user = User(**row)
    if not user.is_active:
        raise AccountDisabled()
    return user


def require_user(role: str | None = None, *, admin: bool = False, superuser: bool = False):
    """Require a signed-in user and store it in `g.user`. Optionally require
    `role`, or the admin or superuser flag (a superuser is also an admin)."""

    def decorator(view):
        @wraps(view)
        def wrapper(*args, **kwargs):
            header = request.headers.get("Authorization", "")
            scheme, _, token = header.partition(" ")
            if scheme.lower() != "bearer" or not token:
                abort(401, "Missing bearer token")
            settings: Settings = current_app.config["LI_SETTINGS"]
            g.user = load_user(verify_token(token, settings))
            if role and g.user.role != role:
                abort(403, f"Requires the {role} role")
            if admin and not g.user.is_admin:
                abort(403, "Requires an admin")
            if superuser and not g.user.is_superuser:
                abort(403, "Requires a superuser")
            return view(*args, **kwargs)

        return wrapper

    return decorator
