import psycopg
import pytest

from li_common import admin

pytestmark = pytest.mark.db


def _users(database_url):
    with psycopg.connect(database_url) as conn:
        return conn.execute(
            "SELECT email, role, is_admin, is_superuser, google_sub FROM users ORDER BY email"
        ).fetchall()


def _audit_actions(database_url):
    with psycopg.connect(database_url) as conn:
        return [r[0] for r in conn.execute("SELECT action FROM user_audit ORDER BY id")]


def test_create_superuser_invites_and_is_idempotent(database_url):
    for _ in range(2):
        admin.main(["--database-url", database_url, "create-superuser", "Boss@Example.edu"])
    assert _users(database_url) == [("boss@example.edu", "student", True, True, None)]
    assert _audit_actions(database_url) == ["invite", "update"]


def test_create_superuser_upgrades_an_existing_user_and_keeps_the_role(database_url):
    admin.main(["--database-url", database_url, "add-user", "p@example.edu", "--role", "professor"])
    admin.main(["--database-url", database_url, "create-superuser", "p@example.edu"])
    assert _users(database_url) == [("p@example.edu", "professor", True, True, None)]


def test_add_user_never_removes_admin(database_url):
    url = ["--database-url", database_url]
    admin.main([*url, "add-user", "a@example.edu", "--role", "student", "--admin"])
    admin.main([*url, "add-user", "a@example.edu", "--role", "professor"])
    assert _users(database_url) == [("a@example.edu", "professor", True, False, None)]


def test_add_user_rejects_unknown_role(database_url):
    with pytest.raises(SystemExit):
        admin.main(["--database-url", database_url, "add-user", "a@example.edu", "--role", "god"])
