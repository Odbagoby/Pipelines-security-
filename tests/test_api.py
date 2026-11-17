"""Functional and security regression tests for the Secure Notes API."""

from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

from app import main

API_KEY = "test-key-not-a-real-secret"  # noqa: S105 - test fixture value only
AUTH = {"X-API-Key": API_KEY}


@pytest.fixture()
def client(monkeypatch):
    monkeypatch.setenv("API_KEY", API_KEY)
    main._notes.clear()
    return TestClient(main.app)


def test_healthz_is_public(client):
    response = client.get("/healthz")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_create_and_fetch_note(client):
    created = client.post("/notes", json={"title": "hello", "body": "world"}, headers=AUTH)
    assert created.status_code == 201
    note = created.json()

    fetched = client.get(f"/notes/{note['id']}", headers=AUTH)
    assert fetched.status_code == 200
    assert fetched.json() == note


def test_delete_note(client):
    note = client.post("/notes", json={"title": "t", "body": "b"}, headers=AUTH).json()
    assert client.delete(f"/notes/{note['id']}", headers=AUTH).status_code == 204
    assert client.get(f"/notes/{note['id']}", headers=AUTH).status_code == 404


def test_unknown_note_returns_404(client):
    assert client.get(f"/notes/{uuid4()}", headers=AUTH).status_code == 404


# --- Security regression tests -------------------------------------------------


@pytest.mark.parametrize("headers", [{}, {"X-API-Key": "wrong"}, {"X-API-Key": ""}])
def test_protected_routes_reject_bad_credentials(client, headers):
    assert client.post("/notes", json={"title": "a", "body": "b"}, headers=headers).status_code == 401
    assert client.get(f"/notes/{uuid4()}", headers=headers).status_code == 401
    assert client.delete(f"/notes/{uuid4()}", headers=headers).status_code == 401


def test_fails_closed_when_api_key_not_configured(client, monkeypatch):
    monkeypatch.delenv("API_KEY")
    response = client.post("/notes", json={"title": "a", "body": "b"}, headers=AUTH)
    assert response.status_code == 503


def test_empty_key_never_authenticates_when_unconfigured(client, monkeypatch):
    monkeypatch.setenv("API_KEY", "")
    response = client.post("/notes", json={"title": "a", "body": "b"}, headers={"X-API-Key": ""})
    assert response.status_code == 503


@pytest.mark.parametrize(
    "payload",
    [
        {"title": "", "body": "b"},
        {"title": "x" * 101, "body": "b"},
        {"title": "t", "body": "x" * 2001},
        {"title": "t"},
        {"title": "t", "body": "b", "is_admin": True},  # unknown fields are rejected
    ],
)
def test_input_validation(client, payload):
    assert client.post("/notes", json=payload, headers=AUTH).status_code == 422


def test_note_id_must_be_a_uuid(client):
    assert client.get("/notes/../../etc/passwd", headers=AUTH).status_code in (404, 422)
    assert client.get("/notes/not-a-uuid", headers=AUTH).status_code == 422


def test_store_is_capped(client, monkeypatch):
    monkeypatch.setattr(main, "MAX_NOTES", 2)
    for _ in range(2):
        assert client.post("/notes", json={"title": "t", "body": "b"}, headers=AUTH).status_code == 201
    assert client.post("/notes", json={"title": "t", "body": "b"}, headers=AUTH).status_code == 507


def test_security_headers_present(client):
    headers = client.get("/healthz").headers
    assert headers["X-Content-Type-Options"] == "nosniff"
    assert headers["X-Frame-Options"] == "DENY"
    assert "default-src 'none'" in headers["Content-Security-Policy"]
    assert "max-age=" in headers["Strict-Transport-Security"]
    assert headers["Cache-Control"] == "no-store"


def test_interactive_docs_disabled(client):
    assert client.get("/docs").status_code == 404
    assert client.get("/redoc").status_code == 404
