"""Lecture Indexer Ingest API: professors register YouTube lectures for indexing."""

from flask import Flask

from li_common.app import create_base_app
from li_common.config import Settings


def create_app(settings: Settings | None = None) -> Flask:
    from ingest import admin, routes

    app = create_base_app("ingest", settings)
    app.register_blueprint(routes.bp)
    app.register_blueprint(admin.bp)
    return app
