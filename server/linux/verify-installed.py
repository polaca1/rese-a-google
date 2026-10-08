"""Real Linux HTTP + systemd checks, with disposable test accounts on a CI machine."""
import json
import os
import stat
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

UNIT = 'reviewnfcgo-cuentas.service'
HELPER = '/usr/local/sbin/reviewnfcgo-servidor'
verification = []


def request(path, body=None, token=None):
    headers = {'Content-Type': 'application/json'}
    if token:
        headers['Authorization'] = 'Bearer ' + token
    req = urllib.request.Request('http://127.0.0.1:8080' + path, data=json.dumps(body).encode() if body else None, headers=headers)
    with urllib.request.urlopen(req, timeout=10) as response:
        return response.status, json.load(response)


def ready():
    for _ in range(80):
        try:
            assert request('/health')[1]['status'] == 'ok'
            return
        except (OSError, AssertionError):
            time.sleep(.25)
    raise AssertionError('Service did not recover')


def checked(condition, name):
    assert condition, name
    verification.append(name)


ready()
checked(subprocess.run(['systemctl', 'is-enabled', '--quiet', UNIT]).returncode == 0, 'Arranque automático habilitado sin sesión de escritorio')
checked(subprocess.check_output(['systemctl', 'show', UNIT, '--property=User', '--value'], text=True).strip() == 'reviewnfcgo', 'Servicio sin permisos de administrador')
for target in ('sleep.target', 'suspend.target', 'hibernate.target', 'hybrid-sleep.target'):
    checked(subprocess.check_output(['systemctl', 'is-enabled', target], text=True).strip() == 'masked', 'Suspensión bloqueada: ' + target)
ports = subprocess.check_output(['ss', '-ltn'], text=True)
checked('127.0.0.1:8080' in ports and '0.0.0.0:8080' not in ports and '[::]:8080' not in ports, 'Puerto de cuentas solo accesible localmente')
for index in range(3):
    code, session = request('/v1/auth/register', {'name': f'Usuario Linux {index}', 'email': f'linux{index}@example.com', 'password': 'Verification-password-2026'})
    checked(code == 201 and session['user']['email'] == f'linux{index}@example.com', f'Registro persistente del usuario {index}')
    checked(request('/v1/auth/me', token=session['token'])[1]['email'] == f'linux{index}@example.com', f'Sesión del usuario {index}')
old_pid = subprocess.check_output(['systemctl', 'show', UNIT, '--property=MainPID', '--value'], text=True).strip()
subprocess.run(['systemctl', 'kill', '--kill-whom=main', '--signal=KILL', UNIT], check=True)
time.sleep(.5)
ready()
new_pid = subprocess.check_output(['systemctl', 'show', UNIT, '--property=MainPID', '--value'], text=True).strip()
checked(old_pid != new_pid and new_pid != '0', 'Recuperación automática tras cierre inesperado')
checked(request('/v1/auth/login', {'email': 'linux1@example.com', 'password': 'Verification-password-2026'})[0] == 200, 'Inicio de sesión después de reiniciar el servicio')
try:
    request('/v1/auth/login', {'email': 'linux1@example.com', 'password': 'incorrect-password'})
    raise AssertionError('Incorrect password accepted')
except urllib.error.HTTPError as error:
    checked(error.code == 401, 'Contraseña incorrecta rechazada')
accounts = json.loads(subprocess.check_output([HELPER, 'accounts'], text=True))
checked(len(accounts) == 3 and set(accounts[0]) == {'Nombre', 'Correo', 'Registro'}, 'Lista privada de tres cuentas sin contraseñas ni tokens')
subprocess.run([HELPER, 'backup'], check=True)
code = "import sqlite3,glob; p=glob.glob('/var/lib/reviewnfcgo-cuentas/copias/*.sqlite3'); assert p; d=sqlite3.connect(p[-1]); assert d.execute('SELECT COUNT(*) FROM users').fetchone()[0]==3; assert all(r[0].startswith('$argon2id$') for r in d.execute('SELECT password_hash FROM users'))"
subprocess.run(['runuser', '-u', 'reviewnfcgo', '--', '/opt/reviewnfcgo-cuentas/venv/bin/python', '-c', code], check=True)
checked(stat.S_IMODE(os.stat('/var/lib/reviewnfcgo-cuentas').st_mode) == 0o700, 'Carpeta de cuentas privada')
checked(stat.S_IMODE(os.stat('/var/lib/reviewnfcgo-cuentas/accounts.sqlite3').st_mode) == 0o600, 'Base de datos privada')
denied = subprocess.run(['runuser', '-u', 'nobody', '--', 'cat', '/var/lib/reviewnfcgo-cuentas/accounts.sqlite3'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
checked(denied.returncode != 0, 'Otro usuario del sistema no puede leer las cuentas')
checked(True, 'Copia online contiene los tres usuarios y hashes Argon2id')
unknown = subprocess.run([HELPER, 'shell'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
checked(unknown.returncode != 0, 'El configurador rechaza acciones arbitrarias')
result = {'platform': 'Linux systemd', 'checks': len(verification), 'passed': verification}
Path(sys.argv[1]).write_text(json.dumps(result, ensure_ascii=False, indent=2))
print(json.dumps(result, ensure_ascii=False))
