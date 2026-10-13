"""Structured JSON logs on stdout.

Cloud Logging reads `severity` and `message` from each line and keeps the rest as
jsonPayload fields, which the log-based metrics in infra/terraform/modules/monitoring
filter on (e.g. `event="youtube_api_call"`).
"""

import json
import logging
import sys
import time

from flask import Flask, g, request


class JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        entry = {
            "severity": record.levelname,
            "message": record.getMessage(),
            "logger": record.name,
        }
        entry.update(getattr(record, "fields", {}))
        if record.exc_info:
            entry["exception"] = self.formatException(record.exc_info)
        return json.dumps(entry, default=str)


def configure_logging(level: int = logging.INFO) -> None:
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JsonFormatter())
    root = logging.getLogger()
    root.handlers[:] = [handler]
    root.setLevel(level)


def log_event(logger: logging.Logger, event: str, level: int = logging.INFO, **fields) -> None:
    logger.log(level, event, extra={"fields": {"event": event, **fields}})


def init_request_logging(app: Flask, service: str) -> None:
    logger = logging.getLogger(f"{service}.request")

    @app.before_request
    def _start_timer():
        g.request_started = time.perf_counter()

    @app.after_request
    def _log_request(response):
        started = g.get("request_started")
        if started is None or request.path in ("/healthz", "/readyz"):
            return response
        log_event(
            logger,
            "http_request",
            service=service,
            method=request.method,
            # The route pattern, not the raw path, keeps metric labels low-cardinality.
            route=request.url_rule.rule if request.url_rule else "unmatched",
            status=response.status_code,
            latency_ms=round((time.perf_counter() - started) * 1000, 1),
        )
        return response
