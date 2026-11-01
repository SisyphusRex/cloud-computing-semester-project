import uuid
from pathlib import Path

import psycopg
import pytest
from psycopg import sql

from li_common.migrate import apply, parse_grants

pytestmark = pytest.mark.db

MIGRATIONS = Path(__file__).resolve().parents[3] / "db" / "migrations"


def test_migrations_are_applied_once(database_url, tmp_path):
    # The fixture already applied the real migrations; running again is a no-op.
    assert apply(database_url, MIGRATIONS) == []
    with psycopg.connect(database_url) as conn:
        versions = [r[0] for r in conn.execute("SELECT version FROM schema_migrations")]
    assert "0001_init.sql" in versions


def test_failed_migration_rolls_back(database_url, tmp_path):
    (tmp_path / "9001_ok.sql").write_text("CREATE TABLE ok_table (id int);")
    (tmp_path / "9002_bad.sql").write_text("CREATE TABLE broken (;")
    with pytest.raises(psycopg.errors.SyntaxError):
        apply(database_url, tmp_path)
    with psycopg.connect(database_url) as conn:
        assert conn.execute("SELECT to_regclass('ok_table')").fetchone()[0] is None


def test_parse_grants():
    assert parse_grants(["li_search_role = a@p.iam"]) == [("li_search_role", "a@p.iam")]
    with pytest.raises(ValueError):
        parse_grants(["no-equals-sign"])


@pytest.fixture
def login_roles(database_url):
    """Two throwaway login roles standing in for the services' IAM users."""
    suffix = uuid.uuid4().hex[:8]
    names = {"ingest": f"ingest-{suffix}@p.iam", "search": f"search-{suffix}@p.iam"}
    with psycopg.connect(database_url, autocommit=True) as conn:
        for name in names.values():
            conn.execute(sql.SQL("CREATE ROLE {} LOGIN").format(sql.Identifier(name)))
    yield names
    with psycopg.connect(database_url, autocommit=True) as conn:
        for name in names.values():
            conn.execute(sql.SQL("DROP OWNED BY {}").format(sql.Identifier(name)))
            conn.execute(sql.SQL("DROP ROLE {}").format(sql.Identifier(name)))


def _as(conn, role, statement):
    conn.execute(sql.SQL("SET ROLE {}").format(sql.Identifier(role)))
    try:
        conn.execute(statement)
    finally:
        conn.rollback()


def test_grants_give_least_privilege(database_url, login_roles):
    apply(
        database_url,
        MIGRATIONS,
        grants=[
            ("li_ingest_role", login_roles["ingest"]),
            ("li_search_role", login_roles["search"]),
        ],
    )
    with psycopg.connect(database_url) as conn:
        _as(conn, login_roles["search"], "SELECT count(*) FROM segments")
        with pytest.raises(psycopg.errors.InsufficientPrivilege):
            _as(
                conn,
                login_roles["search"],
                "INSERT INTO users (google_sub, email) VALUES ('s', 's')",
            )
        with pytest.raises(psycopg.errors.InsufficientPrivilege):
            _as(
                conn,
                login_roles["search"],
                "INSERT INTO courses (owner_id, code, title) VALUES (1, 'x', 'x')",
            )
        _as(conn, login_roles["ingest"], "INSERT INTO users (google_sub, email) VALUES ('i', 'i')")
        # Sign-in claims an invitation.
        _as(conn, login_roles["search"], "UPDATE users SET name = 'x' WHERE email = 'i'")
        _as(conn, login_roles["ingest"], "DELETE FROM segments")
