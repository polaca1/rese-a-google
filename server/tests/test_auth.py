import importlib.util
import os
from pathlib import Path

import pytest
from fastapi.testclient import TestClient


@pytest.fixture
def service(tmp_path, monkeypatch):
    monkeypatch.setenv("DATA_DIRECTORY", str(tmp_path))
    monkeypatch.setenv("ALLOW_REGISTRATION", "true")
    spec = importlib.util.spec_from_file_location("test_server", Path(__file__).parents[1] / "app.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module, TestClient(module.app)


def create(client):
    response = client.post("/v1/auth/register", json={"name": "Pablo", "email": "pablo@example.com", "password": "contraseña-segura"})
    assert response.status_code == 201
    return response.json()


def test_register_login_storage_and_profile(service):
    module, client = service
    session = create(client)
    assert session["user"] == {"name": "Pablo", "email": "pablo@example.com"}
    auth = {"Authorization": "Bearer " + session["token"]}
    assert client.get("/v1/auth/me", headers=auth).json() == session["user"]
    with module.database() as db:
        user = db.execute("SELECT * FROM users").fetchone()
        stored = db.execute("SELECT * FROM sessions").fetchone()
    assert user["password_hash"].startswith("$argon2id$")
    assert stored["token_hash"] != session["token"]
    assert "contraseña-segura" not in str(dict(user))
    assert client.post("/v1/auth/login", json={"email": "PABLO@example.com", "password": "contraseña-segura"}).status_code == 200
    assert client.post("/v1/auth/login", json={"email": "pablo@example.com", "password": "incorrecta"}).status_code == 401
    assert client.get("/v1/auth/me").status_code == 401


def test_refresh_revokes_previous_token_and_logout(service):
    _, client = service
    first = create(client)
    auth = {"Authorization": "Bearer " + first["token"]}
    new = client.post("/v1/auth/refresh", headers=auth)
    assert new.status_code == 200 and new.json()["token"] != first["token"]
    assert client.get("/v1/auth/me", headers=auth).status_code == 401
    auth2 = {"Authorization": "Bearer " + new.json()["token"]}
    assert client.post("/v1/auth/logout", headers=auth2).status_code == 204
    assert client.get("/v1/auth/me", headers=auth2).status_code == 401


def test_expiry_registration_policy_and_duplicate(service, monkeypatch):
    module, client = service
    session = create(client)
    duplicate = client.post("/v1/auth/register", json={"name": "Otro", "email": "pablo@example.com", "password": "otra-contraseña"})
    assert duplicate.status_code == 409
    monkeypatch.setenv("ALLOW_REGISTRATION", "false")
    assert client.post("/v1/auth/register", json={"name": "Otro", "email": "otro@example.com", "password": "otra-contraseña"}).status_code == 403
    with module.database() as db:
        db.execute("UPDATE sessions SET expires_at=0")
    assert client.get("/v1/auth/me", headers={"Authorization": "Bearer " + session["token"]}).status_code == 401


def test_limits_and_generic_credentials_errors(service):
    _, client = service
    for _ in range(10):
        response = client.post("/v1/auth/login", json={"email": "unknown@example.com", "password": "incorrecta"})
        assert response.status_code == 401 and response.json()["detail"] == "Correo o contraseña incorrectos."
    response = client.post("/v1/auth/login", json={"email": "unknown@example.com", "password": "incorrecta"})
    assert response.status_code == 429 and response.headers["Retry-After"] == "300"
    assert client.get("/health").headers["Cache-Control"] == "no-store"


def test_malformed_inputs_cannot_create_account(service):
    _, client = service
    for data in [{"name": " ", "email": "pablo@example.com", "password": "12345678"},
                 {"name": "Pablo", "email": "invalid", "password": "12345678"},
                 {"name": "Pablo", "email": "pablo@example.com", "password": "short"}]:
        assert client.post("/v1/auth/register", json=data).status_code == 422
    assert client.get("/docs").status_code == 404
