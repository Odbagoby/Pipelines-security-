"""Secure Notes API: a deliberately small service used to demonstrate a DevSecOps pipeline.

Security-relevant design choices:
  * API key is read from the environment (injected from a secret store), never hard-coded.
  * Key comparison is constant-time to avoid timing side channels.
  * The service fails closed: if no key is configured, protected routes return 503.
  * All input is validated and length-bounded by Pydantic models.
  * Security headers are set on every response.
  * The in-memory store is capped so the service cannot be used to exhaust memory.
"""

import hmac
import os
from uuid import UUID, uuid4

from fastapi import Depends, FastAPI, Header, HTTPException, Request, status
from pydantic import BaseModel, ConfigDict, Field

MAX_NOTES = 1000

app = FastAPI(
    title="Secure Notes API",
    version="1.0.0",
    docs_url=None,  # interactive docs are disabled; /openapi.json stays on for DAST
    redoc_url=None,
)

_notes: dict[UUID, "Note"] = {}


class NoteIn(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    title: str = Field(min_length=1, max_length=100)
    body: str = Field(min_length=1, max_length=2000)


class Note(NoteIn):
    id: UUID


def require_api_key(x_api_key: str | None = Header(default=None)) -> None:
    """Authenticate the caller with a shared API key supplied in the X-API-Key header."""
    expected = os.environ.get("API_KEY", "")
    if not expected:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Service is not configured",
        )
    supplied = x_api_key or ""
    if not hmac.compare_digest(supplied.encode(), expected.encode()):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or missing API key",
        )


@app.middleware("http")
async def add_security_headers(request: Request, call_next):
    response = await call_next(request)
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["Referrer-Policy"] = "no-referrer"
    response.headers["Content-Security-Policy"] = "default-src 'none'; frame-ancestors 'none'"
    response.headers["Strict-Transport-Security"] = "max-age=63072000; includeSubDomains"
    response.headers["Permissions-Policy"] = "geolocation=(), camera=(), microphone=()"
    response.headers["Cross-Origin-Resource-Policy"] = "same-origin"
    response.headers["Cache-Control"] = "no-store"
    return response


@app.get("/healthz")
def healthz() -> dict[str, str]:
    """Unauthenticated liveness probe. Returns no internal details."""
    return {"status": "ok"}


@app.post(
    "/notes",
    response_model=Note,
    status_code=status.HTTP_201_CREATED,
    dependencies=[Depends(require_api_key)],
)
def create_note(payload: NoteIn) -> Note:
    if len(_notes) >= MAX_NOTES:
        raise HTTPException(
            status_code=status.HTTP_507_INSUFFICIENT_STORAGE,
            detail="Note store is full",
        )
    note = Note(id=uuid4(), **payload.model_dump())
    _notes[note.id] = note
    return note


@app.get("/notes/{note_id}", response_model=Note, dependencies=[Depends(require_api_key)])
def get_note(note_id: UUID) -> Note:
    note = _notes.get(note_id)
    if note is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Note not found")
    return note


@app.delete(
    "/notes/{note_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    dependencies=[Depends(require_api_key)],
)
def delete_note(note_id: UUID) -> None:
    if _notes.pop(note_id, None) is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Note not found")
