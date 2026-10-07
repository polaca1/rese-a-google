"""Packaged Windows account service: no Python or Docker installation required."""
import argparse
import json
import os
import sqlite3
import threading
import time
from datetime import datetime, timezone
from contextlib import closing
from uuid import uuid4
from pathlib import Path


def backup_database(data: Path, now=None):
    """SQLite online backup includes committed WAL records without stopping signups."""
    source = data / "accounts.sqlite3"
    if not source.exists():
        return None
    now = now or datetime.now(timezone.utc)
    destination = data / "copias"
    destination.mkdir(parents=True, exist_ok=True)
    target = destination / ("cuentas-" + now.strftime("%Y-%m-%d") + ".sqlite3")
    temporary = target.with_suffix("." + uuid4().hex + ".tmp")
    try:
        with closing(sqlite3.connect(source, timeout=30)) as original, closing(sqlite3.connect(temporary)) as copy:
            original.backup(copy)
        os.replace(temporary, target)
    finally:
        temporary.unlink(missing_ok=True)
    for old in sorted(destination.glob("cuentas-*.sqlite3"))[:-30]:
        old.unlink()
    return target


def backup_loop(data):
    while True:
        try:
            backup_database(data)
        except (OSError, sqlite3.Error):
            # Never log user data or stop authentication because a backup failed.
            pass
        time.sleep(3600)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--data", type=Path, required=True)
    parser.add_argument("--port", type=int, default=8080)
    parser.add_argument("--list-accounts", action="store_true")
    parser.add_argument("--backup", action="store_true")
    args = parser.parse_args()
    data = args.data.resolve()
    if args.list_accounts:
        source = data / "accounts.sqlite3"
        if not source.exists():
            print("[]")
            return
        with closing(sqlite3.connect(source.as_uri() + "?mode=ro", uri=True, timeout=10)) as db:
            rows = db.execute("SELECT name,email,created_at FROM users ORDER BY created_at DESC").fetchall()
        print(json.dumps([{"Nombre": row[0], "Correo": row[1], "Registro": datetime.fromtimestamp(row[2], timezone.utc).isoformat()} for row in rows]))
        return
    if args.backup:
        backup_database(data)
        return
    os.environ["DATA_DIRECTORY"] = str(data)
    # Public signups are the app's normal behavior, not a temporary setup mode.
    os.environ["ALLOW_REGISTRATION"] = "true"
    import uvicorn
    from app import app
    threading.Thread(target=backup_loop, args=(data,), daemon=True).start()
    uvicorn.run(app, host="127.0.0.1", port=args.port, access_log=False, proxy_headers=False,
                limit_concurrency=8, timeout_keep_alive=5, log_level="warning")


if __name__ == "__main__":
    main()
