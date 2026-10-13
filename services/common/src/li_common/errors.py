import logging

from flask import Flask, jsonify
from pydantic import ValidationError
from werkzeug.exceptions import HTTPException

logger = logging.getLogger(__name__)


def error_response(status: int, error: str, message: str, **extra):
    return jsonify({"error": error, "message": message, **extra}), status


def register_error_handlers(app: Flask) -> None:
    @app.errorhandler(HTTPException)
    def _http_error(exc: HTTPException):
        name = (exc.name or "error").lower().replace(" ", "_")
        return error_response(exc.code or 500, name, exc.description or "")

    @app.errorhandler(ValidationError)
    def _validation_error(exc: ValidationError):
        details = [
            {"field": ".".join(str(p) for p in err["loc"]), "message": err["msg"]}
            for err in exc.errors()
        ]
        return error_response(400, "invalid_request", "Request validation failed", details=details)

    @app.errorhandler(Exception)
    def _unhandled(exc: Exception):
        logger.exception("Unhandled error")
        return error_response(500, "internal_error", "Internal server error")
