from datetime import date, datetime

from flask import Flask
from flask.json.provider import DefaultJSONProvider
from flask_cors import CORS

from li_common import db, health
from li_common.config import Settings
from li_common.errors import register_error_handlers
from li_common.logs import configure_logging, init_request_logging


class JSONProvider(DefaultJSONProvider):
    """ISO 8601 dates instead of Flask's default HTTP-date format."""

    @staticmethod
    def default(o):
        if isinstance(o, (date, datetime)):
            return o.isoformat()
        return DefaultJSONProvider.default(o)


def create_base_app(service: str, settings: Settings | None = None) -> Flask:
    """A Flask app with config, logging, CORS, database, errors, and health checks
    wired up. Each service adds its own blueprint."""
    settings = settings or Settings.from_env()
    configure_logging()

    app = Flask(service)
    app.json = JSONProvider(app)
    app.config["LI_SETTINGS"] = settings
    if settings.cors_origins:
        CORS(
            app,
            origins=settings.cors_origins,
            allow_headers=["Authorization", "Content-Type", "X-YouTube-Token"],
        )
    db.init_app(app, settings.database_url, settings.db_pool_size)
    register_error_handlers(app)
    init_request_logging(app, service)
    app.register_blueprint(health.bp)
    return app
