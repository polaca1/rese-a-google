"""Test the packaged Windows executable over real HTTP, including a PC-service restart."""
import json
import subprocess
import sqlite3
from contextlib import closing
import sys
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path

binary = str(Path(sys.argv[1]).resolve())

def request(path, body=None):
    raw = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request('http://127.0.0.1:18080' + path, data=raw, headers={'Content-Type': 'application/json'})
    with urllib.request.urlopen(req, timeout=5) as response:
        return response.status, json.load(response)

def start(folder):
    process = subprocess.Popen([binary, '--data', str(folder), '--port', '18080'])
    for _ in range(80):
        if process.poll() is not None:
            raise RuntimeError(f'Packaged server exited with {process.returncode}')
        try:
            assert request('/health')[1]['status'] == 'ok'
            return process
        except (OSError, AssertionError):
            time.sleep(.25)
    process.terminate()
    raise RuntimeError('Packaged server did not start')

with tempfile.TemporaryDirectory(prefix='reviewNfcGo-server-') as name:
    folder = Path(name)
    process = start(folder)
    try:
        for index in range(3):
            status, session = request('/v1/auth/register', {'name': f'Usuario {index}', 'email': f'user{index}@example.com', 'password': 'Password-for-test'})
            assert status == 201 and session['user']['email'] == f'user{index}@example.com'
    finally:
        process.terminate(); process.wait(timeout=15)
    process = start(folder)
    try:
        assert request('/v1/auth/login', {'email': 'user1@example.com', 'password': 'Password-for-test'})[0] == 200
        subprocess.run([binary, '--data', str(folder), '--backup'], check=True, timeout=30)
        accounts = json.loads(subprocess.check_output([binary, '--data', str(folder), '--list-accounts'], timeout=30))
        assert len(accounts) == 3 and set(accounts[0]) == {'Nombre', 'Correo', 'Registro'}
        copies = list((folder / 'copias').glob('*.sqlite3'))
        assert len(copies) == 1
        with closing(sqlite3.connect(copies[0])) as copy:
            assert copy.execute('SELECT COUNT(*) FROM users').fetchone()[0] == 3
        try:
            request('/v1/auth/login', {'email': 'user1@example.com', 'password': 'incorrect-password'})
            raise AssertionError('Wrong password accepted')
        except urllib.error.HTTPError as error:
            assert error.code == 401
    finally:
        process.terminate(); process.wait(timeout=15)
print('Windows executable verified: all registrations persisted, login after restart, backups and private owner account listing.')
