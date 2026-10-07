import importlib.util
import sqlite3
from datetime import datetime, timedelta, timezone
from pathlib import Path


def runtime():
    spec = importlib.util.spec_from_file_location('windows_runtime', Path(__file__).parents[1] / 'windows' / 'runtime.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_daily_backup_includes_wal_and_keeps_30_copies(tmp_path):
    module = runtime()
    source = sqlite3.connect(tmp_path / 'accounts.sqlite3')
    source.execute('PRAGMA journal_mode=WAL')
    source.execute('CREATE TABLE users (email TEXT)')
    source.execute('INSERT INTO users VALUES (?)', ('first@example.com',))
    source.commit()
    now = datetime(2026, 1, 1, tzinfo=timezone.utc)
    first = module.backup_database(tmp_path, now)
    with sqlite3.connect(first) as copy:
        assert copy.execute('SELECT email FROM users').fetchone()[0] == 'first@example.com'
    source.execute('INSERT INTO users VALUES (?)', ('second@example.com',))
    source.commit()
    for offset in range(1, 33):
        module.backup_database(tmp_path, now + timedelta(days=offset))
    copies = sorted((tmp_path / 'copias').glob('*.sqlite3'))
    assert len(copies) == 30 and not first.exists()
    with sqlite3.connect(copies[-1]) as copy:
        assert copy.execute('SELECT COUNT(*) FROM users').fetchone()[0] == 2
    assert not list((tmp_path / 'copias').glob('*.tmp'))
    assert module.backup_database(tmp_path, now + timedelta(days=32)) == copies[-1]
    source.close()


def test_backup_empty_install_does_not_create_fake_database(tmp_path):
    assert runtime().backup_database(tmp_path) is None
    assert not (tmp_path / 'accounts.sqlite3').exists()
