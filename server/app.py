"""Small, self-hosted account service. No passwords or session tokens in logs/storage."""
import hashlib
import os
import secrets
import sqlite3
import time
from contextlib import contextmanager
from pathlib import Path

from argon2 import PasswordHasher
from argon2.exceptions import VerificationError, InvalidHashError
from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel, EmailStr, Field

DATA = Path(os.environ.get("DATA_DIRECTORY", "/app/data"))
DATA.mkdir(parents=True, exist_ok=True, mode=0o700)
DATABASE = DATA / "accounts.sqlite3"
HASHER = PasswordHasher(time_cost=2, memory_cost=19456, parallelism=1)
DUMMY_HASH = HASHER.hash(secrets.token_urlsafe(32))
SESSION_SECONDS = 7 * 86400
bearer = HTTPBearer(auto_error=False)
app = FastAPI(title="reviewNfcGo Accounts", docs_url=None, redoc_url=None, openapi_url=None)


@contextmanager
def database():
    connection = sqlite3.connect(DATABASE, timeout=10)
    connection.row_factory = sqlite3.Row
    try:
        with connection:
            yield connection
    finally:
        connection.close()


with database() as db:
    db.execute("PRAGMA journal_mode=WAL")
    db.executescript("""
        CREATE TABLE IF NOT EXISTS users (
            id TEXT PRIMARY KEY, email TEXT UNIQUE NOT NULL, name TEXT NOT NULL,
            password_hash TEXT NOT NULL, created_at REAL NOT NULL
        );
        CREATE TABLE IF NOT EXISTS sessions (
            token_hash TEXT PRIMARY KEY, user_id TEXT NOT NULL,
            expires_at REAL NOT NULL, FOREIGN KEY(user_id) REFERENCES users(id)
        );
        CREATE TABLE IF NOT EXISTS attempts (key TEXT NOT NULL, timestamp REAL NOT NULL);
        CREATE INDEX IF NOT EXISTS attempts_key_date ON attempts(key,timestamp);
    """)
os.chmod(DATABASE, 0o600)


class Login(BaseModel):
    email: EmailStr
    password: str = Field(min_length=8, max_length=128)


class Register(Login):
    name: str = Field(min_length=1, max_length=100)


def email_key(value):
    return str(value).strip().lower()


def digest(value):
    return hashlib.sha256(value.encode()).hexdigest()


def limit(request, email):
    now = time.time()
    # Persist limits across restarts. Only the TCP peer is trusted, never client-supplied X-Forwarded-For.
    ip = request.client.host if request.client else "unknown"
    keys = [(digest("ip:" + ip), 60), (digest("email:" + email), 10)]
    with database() as db:
        db.execute("BEGIN IMMEDIATE")
        db.execute("DELETE FROM attempts WHERE timestamp < ?", (now - 300,))
        for key, maximum in keys:
            count = db.execute("SELECT COUNT(*) FROM attempts WHERE key=?", (key,)).fetchone()[0]
            if count >= maximum:
                raise HTTPException(429, "Demasiados intentos. Espera cinco minutos.", headers={"Retry-After": "300"})
        db.executemany("INSERT INTO attempts VALUES (?,?)", [(key, now) for key, _ in keys])


def issue_session(db, user):
    token = secrets.token_urlsafe(32)
    expiry = time.time() + SESSION_SECONDS
    db.execute("INSERT INTO sessions VALUES (?,?,?)", (digest(token), user["id"], expiry))
    db.execute("DELETE FROM sessions WHERE expires_at < ?", (time.time(),))
    return {"token": token, "expiresAt": expiry, "user": {"name": user["name"], "email": user["email"]}}


def current(credentials: HTTPAuthorizationCredentials | None = Depends(bearer)):
    if credentials is None or credentials.scheme.lower() != "bearer" or len(credentials.credentials) > 200:
        raise HTTPException(401, "Vuelve a iniciar sesión.")
    hashed = digest(credentials.credentials)
    with database() as db:
        row = db.execute("SELECT u.*,s.token_hash,s.expires_at FROM users u JOIN sessions s ON u.id=s.user_id WHERE s.token_hash=?", (hashed,)).fetchone()
    if row is None or row["expires_at"] <= time.time():
        raise HTTPException(401, "La sesión ha caducado. Vuelve a entrar.")
    return dict(row)


@app.middleware("http")
async def headers(request, next_handler):
    response = await next_handler(request)
    response.headers["Cache-Control"] = "no-store"
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["Referrer-Policy"] = "no-referrer"
    return response


@app.get("/health")
def health():
    return {"status": "ok", "schema": 1}


@app.post("/v1/auth/register", status_code=201)
def register(body: Register, request: Request):
    if os.environ.get("ALLOW_REGISTRATION", "false").lower() != "true":
        raise HTTPException(403, "El registro está cerrado. Contacta con el propietario del servidor.")
    email = email_key(body.email)
    limit(request, email)
    name = body.name.strip()
    if not name:
        raise HTTPException(422, "Introduce tu nombre.")
    password_hash = HASHER.hash(body.password)
    try:
        with database() as db:
            db.execute("INSERT INTO users VALUES (?,?,?,?,?)", (secrets.token_hex(16), email, name, password_hash, time.time()))
            user = db.execute("SELECT * FROM users WHERE email=?", (email,)).fetchone()
            return issue_session(db, user)
    except sqlite3.IntegrityError:
        raise HTTPException(409, "Ya existe una cuenta con ese correo.") from None


@app.post("/v1/auth/login")
def login(body: Login, request: Request):
    email = email_key(body.email)
    limit(request, email)
    with database() as db:
        user = db.execute("SELECT * FROM users WHERE email=?", (email,)).fetchone()
    try:
        valid = HASHER.verify(user["password_hash"] if user else DUMMY_HASH, body.password)
    except (VerificationError, InvalidHashError):
        valid = False
    if not valid or user is None:
        raise HTTPException(401, "Correo o contraseña incorrectos.")
    with database() as db:
        if HASHER.check_needs_rehash(user["password_hash"]):
            db.execute("UPDATE users SET password_hash=? WHERE id=?", (HASHER.hash(body.password), user["id"]))
        return issue_session(db, user)


@app.get("/v1/auth/me")
def me(user=Depends(current)):
    return {"name": user["name"], "email": user["email"]}


@app.post("/v1/auth/refresh")
def refresh(user=Depends(current)):
    with database() as db:
        db.execute("BEGIN IMMEDIATE")
        removed = db.execute("DELETE FROM sessions WHERE token_hash=?", (user["token_hash"],)).rowcount
        if removed != 1:
            raise HTTPException(401, "La sesión ya se ha renovado. Vuelve a entrar.")
        return issue_session(db, user)


@app.post("/v1/auth/logout", status_code=204)
def logout(user=Depends(current)):
    with database() as db:
        db.execute("DELETE FROM sessions WHERE token_hash=?", (user["token_hash"],))

