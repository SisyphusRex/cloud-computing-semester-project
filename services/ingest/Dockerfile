# Build from the repository root:
#   docker build -f services/ingest/Dockerfile -t li-ingest .
FROM python:3.12-slim AS build
COPY --from=ghcr.io/astral-sh/uv:0.13.0 /uv /bin/uv
ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PYTHON_DOWNLOADS=never \
    UV_PROJECT_ENVIRONMENT=/app/.venv
WORKDIR /src

# Third-party dependencies first, so code changes reuse this cached layer.
COPY services/pyproject.toml services/uv.lock services/.python-version ./
COPY services/common/pyproject.toml common/
COPY services/ingest/pyproject.toml ingest/
COPY services/search/pyproject.toml search/
RUN uv sync --frozen --no-dev --no-install-workspace --package ingest

COPY services/common common
COPY services/ingest ingest
RUN uv sync --frozen --no-dev --no-editable --package ingest

FROM python:3.12-slim
RUN useradd --system --uid 10001 app
COPY --from=build /app/.venv /app/.venv
# The migrate Job and docker-compose run `li-migrate /app/migrations` from this image.
COPY db/migrations /app/migrations
ENV PATH=/app/.venv/bin:$PATH \
    PYTHONUNBUFFERED=1
USER 10001
EXPOSE 8080
CMD ["gunicorn", "--no-control-socket", "--workers", "2", "--threads", "4", "--timeout", "120", "--bind", ":8080", "ingest:create_app()"]
