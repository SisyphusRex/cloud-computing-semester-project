from flask import Blueprint

from li_common import db

bp = Blueprint("health", __name__)


@bp.get("/healthz")
def healthz():
    """Liveness: the process is serving requests."""
    return {"status": "ok"}


@bp.get("/readyz")
def readyz():
    """Readiness: the database is reachable, so the pod can take traffic."""
    if db.ping():
        return {"status": "ok"}
    return {"status": "database_unavailable"}, 503
