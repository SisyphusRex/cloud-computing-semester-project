import psycopg
import pytest

import ingest

pytestmark = pytest.mark.db

ADMIN = "admin@example.edu"
OTHER_ADMIN = "admin2@example.edu"
PROF = "prof@example.edu"
STUDENT = "student@example.edu"


@pytest.fixture
def client(make_client, db_settings, invite):
    invite(ADMIN, "student", admin=True)
    invite(OTHER_ADMIN, "professor", admin=True)
    invite(PROF, "professor")
    invite(STUDENT)
    return make_client(ingest.create_app, db_settings)


def _id(client, auth, email):
    users = client.get("/ingest/admin/users", headers=auth(ADMIN)).json["users"]
    return next(u["id"] for u in users if u["email"] == email)


def _audit(database_url):
    with psycopg.connect(database_url) as conn:
        return conn.execute(
            "SELECT a.action, a.detail, actor.email FROM user_audit a "
            "LEFT JOIN users actor ON actor.id = a.actor_id ORDER BY a.id"
        ).fetchall()


def test_me_reports_role_and_admin_flag(client, auth):
    me = client.get("/ingest/me", headers=auth(OTHER_ADMIN)).json
    assert (me["email"], me["role"], me["is_admin"]) == (OTHER_ADMIN, "professor", True)
    assert client.get("/ingest/me", headers=auth(STUDENT)).json["is_admin"] is False


@pytest.mark.parametrize("email", [PROF, STUDENT])
def test_non_admins_cannot_use_admin_endpoints(client, auth, email):
    headers = auth(email)
    assert client.get("/ingest/admin/users", headers=headers).status_code == 403
    invite = {"emails": ["x@example.edu"], "role": "professor"}
    assert client.post("/ingest/admin/users", json=invite, headers=headers).status_code == 403
    assert (
        client.patch("/ingest/admin/users/1", json={"role": "professor"}, headers=headers)
    ).status_code == 403


def test_admin_invites_in_bulk_and_the_invitee_can_sign_in(client, auth, database_url):
    resp = client.post(
        "/ingest/admin/users",
        json={"emails": [" New@Example.edu", "new@example.edu", PROF], "role": "professor"},
        headers=auth(ADMIN),
    )
    assert resp.status_code == 201, resp.json
    assert [u["email"] for u in resp.json["created"]] == ["new@example.edu"]
    assert resp.json["created"][0]["status"] == "invited"
    assert resp.json["already_exists"] == [PROF]

    assert client.get("/ingest/courses", headers=auth("new@example.edu")).status_code == 200
    assert _audit(database_url)[-1][::2] == ("invite", ADMIN)


def test_invite_validates_emails(client, auth):
    resp = client.post(
        "/ingest/admin/users",
        json={"emails": ["not-an-email"], "role": "student"},
        headers=auth(ADMIN),
    )
    assert resp.status_code == 400


def test_admin_changes_role_and_disables(client, auth, database_url):
    student = _id(client, auth, STUDENT)
    resp = client.patch(
        f"/ingest/admin/users/{student}", json={"role": "professor"}, headers=auth(ADMIN)
    )
    assert resp.json["role"] == "professor"
    assert client.get("/ingest/courses", headers=auth(STUDENT)).status_code == 200

    client.patch(f"/ingest/admin/users/{student}", json={"is_active": False}, headers=auth(ADMIN))
    assert client.get("/ingest/me", headers=auth(STUDENT)).json["error"] == "account_disabled"

    action, detail, actor = _audit(database_url)[-1]
    assert (action, actor) == ("update", ADMIN)
    assert detail == {"is_active": {"from": True, "to": False}}


def test_admin_grants_and_revokes_admin(client, auth):
    prof = _id(client, auth, PROF)
    resp = client.patch(f"/ingest/admin/users/{prof}", json={"is_admin": True}, headers=auth(ADMIN))
    assert resp.json["is_admin"] is True
    assert client.get("/ingest/admin/users", headers=auth(PROF)).status_code == 200

    client.patch(f"/ingest/admin/users/{prof}", json={"is_admin": False}, headers=auth(ADMIN))
    assert client.get("/ingest/admin/users", headers=auth(PROF)).status_code == 403


def test_admin_changes_and_disables_another_admin(client, auth):
    other = _id(client, auth, OTHER_ADMIN)
    resp = client.patch(
        f"/ingest/admin/users/{other}", json={"role": "student"}, headers=auth(ADMIN)
    )
    assert resp.json["role"] == "student"

    client.patch(f"/ingest/admin/users/{other}", json={"is_active": False}, headers=auth(ADMIN))
    assert client.get("/ingest/me", headers=auth(OTHER_ADMIN)).json["error"] == "account_disabled"


def test_admin_switches_their_own_role(client, auth, database_url):
    me = _id(client, auth, ADMIN)
    assert client.get("/ingest/courses", headers=auth(ADMIN)).status_code == 403

    resp = client.patch(
        f"/ingest/admin/users/{me}", json={"role": "professor"}, headers=auth(ADMIN)
    )
    assert resp.json["role"] == "professor"
    assert client.get("/ingest/courses", headers=auth(ADMIN)).status_code == 200

    action, detail, actor = _audit(database_url)[-1]
    assert (action, actor) == ("update", ADMIN)
    assert detail == {"role": {"from": "student", "to": "professor"}}

    client.patch(f"/ingest/admin/users/{me}", json={"role": "student"}, headers=auth(ADMIN))
    assert client.get("/ingest/courses", headers=auth(ADMIN)).status_code == 403
    assert client.get("/ingest/admin/users", headers=auth(ADMIN)).status_code == 200


@pytest.mark.parametrize(
    "changes",
    [
        {"is_active": False},
        {"is_admin": False},
        {"role": "professor", "is_active": False},
        {"role": "professor", "is_admin": False},
    ],
)
def test_admins_cannot_disable_or_demote_themselves(client, auth, changes):
    me = _id(client, auth, ADMIN)
    resp = client.patch(f"/ingest/admin/users/{me}", json=changes, headers=auth(ADMIN))
    assert resp.status_code == 403
    assert client.get("/ingest/me", headers=auth(ADMIN)).json["role"] == "student"


def test_admin_cancels_an_admins_invitation(client, auth, invite):
    invite("new-admin@example.edu", admin=True)
    target = _id(client, auth, "new-admin@example.edu")
    assert client.delete(f"/ingest/admin/users/{target}", headers=auth(ADMIN)).status_code == 204


def test_delete_only_unclaimed_invitations(client, auth, database_url):
    client.post(
        "/ingest/admin/users",
        json={"emails": ["typo@example.edu"], "role": "student"},
        headers=auth(ADMIN),
    )
    typo = _id(client, auth, "typo@example.edu")
    assert client.delete(f"/ingest/admin/users/{typo}", headers=auth(ADMIN)).status_code == 204
    assert _audit(database_url)[-1][:2] == ("delete_invitation", {"email": "typo@example.edu"})

    client.get("/ingest/me", headers=auth(STUDENT))  # claims the invitation
    student = _id(client, auth, STUDENT)
    assert client.delete(f"/ingest/admin/users/{student}", headers=auth(ADMIN)).status_code == 409


def test_unknown_user_is_404(client, auth):
    resp = client.patch("/ingest/admin/users/999999", json={"role": "student"}, headers=auth(ADMIN))
    assert resp.status_code == 404
