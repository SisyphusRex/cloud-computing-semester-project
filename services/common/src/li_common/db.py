"""Postgres connection pool.

The services always connect with a plain DSN. In GKE that DSN points at the Cloud
SQL Auth Proxy sidecar on 127.0.0.1, which handles TLS and IAM database login, so
no code here knows about Cloud SQL.
"""

import threading
from contextlib import contextmanager

import psycopg
from flask import Flask, current_app
from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool

_open_lock = threading.Lock()


def init_app(app: Flask, database_url: str, pool_size: int) -> None:
    # Opened lazily so the app (and /healthz) starts even before the database is up.
    app.extensions["li_db_pool"] = ConnectionPool(
        database_url,
        min_size=1,
        max_size=pool_size,
        kwargs={"row_factory": dict_row},
        open=False,
    )


def _pool() -> ConnectionPool:
    pool = current_app.extensions["li_db_pool"]
    if pool.closed:
        with _open_lock:
            if pool.closed:
                pool.open()
    return pool


@contextmanager
def connection(timeout: float = 10.0):
    """A pooled connection; commits on success and rolls back on an exception."""
    with _pool().connection(timeout=timeout) as conn:
        yield conn


def ping(timeout: float = 2.0) -> bool:
    try:
        with connection(timeout=timeout) as conn:
            conn.execute("SELECT 1")
        return True
    except (psycopg.Error, TimeoutError):
        return False
