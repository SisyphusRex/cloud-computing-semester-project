from pathlib import Path

import psycopg
import pytest

from li_common.migrate import apply

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
