"""Shared fixtures.

Database tests need DATABASE_URL (any Postgres 16 the user can create schemas in);
each test gets a fresh schema with the migrations applied. Without DATABASE_URL
they are skipped. CI provides one with a Postgres service container.
"""

import dataclasses
import os
import uuid
from pathlib import Path

import psycopg
import pytest
from psycopg.conninfo import make_conninfo

from li_common.config import Settings
from li_common.migrate import apply

MIGRATIONS = Path(__file__).resolve().parent.parent / "db" / "migrations"
PROFESSOR = "prof@example.edu"  # in professor_emails; tests use these literals


@pytest.fixture
def settings() -> Settings:
    """Settings for tests that never reach the database."""
    return Settings(
        database_url="postgresql://127.0.0.1:1/unreachable?connect_timeout=1",
        google_client_id="test-client-id",
        professor_emails=frozenset({PROFESSOR}),
        dev_auth=True,
    )


@pytest.fixture
def database_url():
    base = os.environ.get("DATABASE_URL")
    if not base:
        pytest.skip("DATABASE_URL not set")
    schema = f"li_test_{uuid.uuid4().hex[:12]}"
    with psycopg.connect(base, autocommit=True) as conn:
        conn.execute(f'CREATE SCHEMA "{schema}"')
    url = make_conninfo(base, options=f"-c search_path={schema}")
    apply(url, MIGRATIONS)
    yield url
    with psycopg.connect(base, autocommit=True) as conn:
        conn.execute(f'DROP SCHEMA "{schema}" CASCADE')


@pytest.fixture
def db_settings(settings, database_url) -> Settings:
    return dataclasses.replace(settings, database_url=database_url)


@pytest.fixture
def make_client():
    """Build a test client from an app factory and close its pool afterwards."""
    apps = []

    def _make(factory, settings):
        app = factory(settings)
        app.config["TESTING"] = True
        apps.append(app)
        return app.test_client()

    yield _make
    for app in apps:
        app.extensions["li_db_pool"].close()


@pytest.fixture
def auth():
    """`auth(email)` -> headers for a dev-auth bearer token."""
    return lambda email: {"Authorization": f"Bearer dev:{email}"}
