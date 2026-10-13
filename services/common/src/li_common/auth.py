"""Google ID token authentication and role checks.

The frontend sends the Google ID token from sign-in as `Authorization: Bearer ...`.
We verify its signature, issuer, audience, and expiry, then load (or create) the
matching user row. Roles live in our database, not in the token.
"""

from dataclasses import dataclass
from functools import wraps

import cachecontrol
import google.auth.transport.requests
import requests
from flask import abort, current_app, g, request
from google.oauth2 import id_token

from li_common import db
from li_common.config import Settings

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


def load_user(claims: dict, settings: Settings) -> User:
    email = claims["email"].lower()
    name = claims.get("name")
    role = "professor" if email in settings.professor_emails else "student"
    with db.connection() as conn:
        row = conn.execute(
            "SELECT id, email, name, role FROM users WHERE google_sub = %s", (claims["sub"],)
        ).fetchone()
        # Skip the write on the common path where nothing changed.
        if (
            row
            and row["email"] == email
            and row["name"] == name
            and (role == "student" or row["role"] == "professor")
        ):
            return User(**row)
        row = conn.execute(
            """
            INSERT INTO users (google_sub, email, name, role)
            VALUES (%s, %s, %s, %s)
            ON CONFLICT (google_sub) DO UPDATE SET
                email = EXCLUDED.email,
                name = EXCLUDED.name,
                role = CASE WHEN EXCLUDED.role = 'professor' THEN 'professor'
                            ELSE users.role END
            RETURNING id, email, name, role
            """,
            (claims["sub"], email, name, role),
        ).fetchone()
    return User(**row)


def require_user(role: str | None = None):
    """Require a signed-in user (optionally with `role`) and store it in `g.user`."""

    def decorator(view):
        @wraps(view)
        def wrapper(*args, **kwargs):
            header = request.headers.get("Authorization", "")
            scheme, _, token = header.partition(" ")
            if scheme.lower() != "bearer" or not token:
                abort(401, "Missing bearer token")
            settings: Settings = current_app.config["LI_SETTINGS"]
            g.user = load_user(verify_token(token, settings), settings)
            if role and g.user.role != role:
                abort(403, f"Requires the {role} role")
            return view(*args, **kwargs)

        return wrapper

    return decorator
