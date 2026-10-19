"""Invite-only sign-in and per-request roles (ADR 0002)."""

import psycopg
import pytest
from flask import Blueprint, g

from li_common import auth as auth_module
from li_common.app import create_base_app
from li_common.auth import require_user

pytestmark = pytest.mark.db


def _factory(settings):
    app = create_base_app("test", settings)
    bp = Blueprint("t", __name__)

    @bp.get("/whoami")
    @require_user()
    def whoami():
        return {"email": g.user.email, "role": g.user.role}

    @bp.get("/professors")
    @require_user("professor")
    def professors():
        return {"ok": True}

    app.register_blueprint(bp)
    return app


@pytest.fixture
def client(make_client, db_settings):
    return make_client(_factory, db_settings)


def _set(database_url, email, **columns):
    sets = ", ".join(f"{k} = %({k})s" for k in columns)
    with psycopg.connect(database_url) as conn:
        conn.execute(
            f"UPDATE users SET {sets} WHERE email = %(email)s", {**columns, "email": email}
        )


def test_uninvited_email_is_403(client, auth):
    resp = client.get("/whoami", headers=auth("stranger@example.edu"))
    assert resp.status_code == 403
    assert resp.json["error"] == "not_invited"


def test_first_sign_in_claims_the_invitation(client, auth, invite, database_url):
    invite("New@Example.edu", "professor")
    resp = client.get("/whoami", headers=auth("new@EXAMPLE.edu"))
    assert resp.json == {"email": "new@example.edu", "role": "professor"}
    with psycopg.connect(database_url) as conn:
        assert conn.execute("SELECT google_sub FROM users").fetchone()[0] == "dev|new@EXAMPLE.edu"


def test_claimed_invitation_cannot_be_claimed_by_another_account(client, auth, invite, monkeypatch):
    invite("prof@example.edu", "professor")
    assert client.get("/whoami", headers=auth("prof@example.edu")).status_code == 200
    # A different Google account (another sub) with the same email.
    monkeypatch.setattr(
        auth_module.id_token,
        "verify_oauth2_token",
        lambda *a, **k: {"sub": "other", "email": "prof@example.edu", "email_verified": True},
    )
    resp = client.get("/whoami", headers={"Authorization": "Bearer google-token"})
    assert resp.json["error"] == "not_invited"


def test_disabled_account_is_403_on_the_next_request(client, auth, invite, database_url):
    invite("student@example.edu")
    assert client.get("/whoami", headers=auth("student@example.edu")).status_code == 200
    _set(database_url, "student@example.edu", is_active=False)
    resp = client.get("/whoami", headers=auth("student@example.edu"))
    assert resp.status_code == 403
    assert resp.json["error"] == "account_disabled"


def test_demotion_takes_effect_on_the_next_request(client, auth, invite, database_url):
    invite("prof@example.edu", "professor")
    assert client.get("/professors", headers=auth("prof@example.edu")).status_code == 200
    _set(database_url, "prof@example.edu", role="student")
    assert client.get("/professors", headers=auth("prof@example.edu")).status_code == 403
