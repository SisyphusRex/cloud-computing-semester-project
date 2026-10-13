"""Lecture Indexer Search API: keyword search over indexed lecture captions."""

from flask import Flask

from li_common.app import create_base_app
from li_common.config import Settings


def create_app(settings: Settings | None = None) -> Flask:
    from search import routes

    app = create_base_app("search", settings)
    app.register_blueprint(routes.bp)
    return app
