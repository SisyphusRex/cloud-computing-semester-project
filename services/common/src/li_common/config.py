"""Settings read from the environment.

In GKE the Secret Manager add-on mounts secrets as files, so any setting can be
given as NAME_FILE (a path) instead of NAME.
"""

import os
from dataclasses import dataclass, field


def env(name: str, default: str = "") -> str:
    path = os.environ.get(f"{name}_FILE")
    if path:
        with open(path) as f:
            return f.read().strip()
    return os.environ.get(name, default)


def _split(value: str) -> list[str]:
    return [item.strip() for item in value.split(",") if item.strip()]


@dataclass(frozen=True)
class Settings:
    database_url: str
    google_client_id: str
    cors_origins: list[str] = field(default_factory=list)
    # Signing in with one of these emails grants the professor role.
    professor_emails: frozenset[str] = frozenset()
    # Accept "dev:<email>" bearer tokens instead of Google ID tokens. Local only.
    dev_auth: bool = False
    db_pool_size: int = 4

    @classmethod
    def from_env(cls) -> "Settings":
        settings = cls(
            database_url=env("DATABASE_URL", "postgresql:///li"),
            google_client_id=env("GOOGLE_CLIENT_ID"),
            cors_origins=_split(env("CORS_ORIGINS")),
            professor_emails=frozenset(e.lower() for e in _split(env("PROFESSOR_EMAILS"))),
            dev_auth=env("LI_DEV_AUTH") == "1",
            db_pool_size=int(env("DB_POOL_SIZE", "4")),
        )
        settings.validate()
        return settings

    def validate(self) -> None:
        if self.dev_auth and "KUBERNETES_SERVICE_HOST" in os.environ:
            raise RuntimeError("LI_DEV_AUTH must not be enabled inside Kubernetes")
        if not self.dev_auth and not self.google_client_id:
            raise RuntimeError("GOOGLE_CLIENT_ID is required unless LI_DEV_AUTH=1")
