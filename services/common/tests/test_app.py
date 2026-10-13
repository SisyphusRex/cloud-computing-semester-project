"""Base-app behaviour that doesn't need a database."""

import pytest
from flask import Blueprint

from li_common import auth as auth_module
from li_common.app import create_base_app
from li_common.auth import require_user


def _factory(settings):
    app = create_base_app("test", settings)
    bp = Blueprint("t", __name__)

    @bp.get("/private")
    @require_user()
    def private():
        return {"ok": True}

    app.register_blueprint(bp)
    return app


@pytest.fixture
def client(make_client, settings):
    return make_client(_factory, settings)


def test_healthz(client):
    assert client.get("/healthz").json == {"status": "ok"}


def test_readyz_reports_unreachable_database(client):
    resp = client.get("/readyz")
    assert resp.status_code == 503


def test_missing_token_is_401_json(client):
    resp = client.get("/private")
    assert resp.status_code == 401
    assert resp.json["error"] == "unauthorized"


def test_invalid_google_token_is_401(client, monkeypatch):
    def reject(*args, **kwargs):
        raise ValueError("bad signature")

    monkeypatch.setattr(auth_module.id_token, "verify_oauth2_token", reject)
    resp = client.get("/private", headers={"Authorization": "Bearer not-a-real-token"})
    assert resp.status_code == 401


def test_unverified_email_is_401(client, monkeypatch):
    monkeypatch.setattr(
        auth_module.id_token,
        "verify_oauth2_token",
        lambda *a, **k: {"sub": "1", "email": "x@example.edu", "email_verified": False},
    )
    resp = client.get("/private", headers={"Authorization": "Bearer token"})
    assert resp.status_code == 401


def test_unknown_route_is_404_json(client):
    resp = client.get("/nope")
    assert resp.status_code == 404
    assert resp.json["error"] == "not_found"
