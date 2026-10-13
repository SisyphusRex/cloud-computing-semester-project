import pytest

from li_common.config import Settings


def test_from_env_reads_values_and_files(monkeypatch, tmp_path):
    secret = tmp_path / "client-id"
    secret.write_text("abc.apps.googleusercontent.com\n")
    monkeypatch.setenv("GOOGLE_CLIENT_ID_FILE", str(secret))
    monkeypatch.setenv("PROFESSOR_EMAILS", "Prof@Example.edu, other@example.edu")
    monkeypatch.setenv("CORS_ORIGINS", "http://localhost:5173")
    monkeypatch.delenv("KUBERNETES_SERVICE_HOST", raising=False)

    settings = Settings.from_env()

    assert settings.google_client_id == "abc.apps.googleusercontent.com"
    assert settings.professor_emails == {"prof@example.edu", "other@example.edu"}
    assert settings.cors_origins == ["http://localhost:5173"]
    assert not settings.dev_auth


def test_client_id_required_without_dev_auth(monkeypatch):
    monkeypatch.delenv("GOOGLE_CLIENT_ID", raising=False)
    monkeypatch.delenv("GOOGLE_CLIENT_ID_FILE", raising=False)
    monkeypatch.delenv("LI_DEV_AUTH", raising=False)
    with pytest.raises(RuntimeError, match="GOOGLE_CLIENT_ID"):
        Settings.from_env()


def test_dev_auth_refused_in_kubernetes(monkeypatch):
    monkeypatch.setenv("LI_DEV_AUTH", "1")
    monkeypatch.setenv("KUBERNETES_SERVICE_HOST", "10.0.0.1")
    with pytest.raises(RuntimeError, match="LI_DEV_AUTH"):
        Settings.from_env()
