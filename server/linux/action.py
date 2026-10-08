"""Fixed administrator actions; never executes caller-provided commands or paths."""
import json
import os
import re
import subprocess
import sys
import urllib.request
from pathlib import Path

ROOT = Path('/opt/reviewnfcgo-cuentas')
DATA = Path('/var/lib/reviewnfcgo-cuentas')
UNIT = 'reviewnfcgo-cuentas.service'


def run(arguments, timeout=30):
    return subprocess.check_output(arguments, text=True, timeout=timeout, stderr=subprocess.DEVNULL)


def public_origin(state, funnel):
    host = state.get('Self', {}).get('DNSName', '').rstrip('.').lower()
    if state.get('BackendState') != 'Running' or not re.fullmatch(r'[a-z0-9-]+(?:\.[a-z0-9-]+)+\.ts\.net', host):
        return None
    address = host + ':443'
    proxy = funnel.get('Web', {}).get(address, {}).get('Handlers', {}).get('/', {}).get('Proxy')
    if funnel.get('AllowFunnel', {}).get(address) is not True or proxy != 'http://127.0.0.1:8080':
        return None
    return 'https://' + host


def healthy(origin):
    try:
        request = urllib.request.Request(origin + '/health', headers={'Accept': 'application/json'})
        with urllib.request.urlopen(request, timeout=10) as response:
            return response.status == 200 and json.loads(response.read(4097)).get('status') == 'ok'
    except (OSError, ValueError):
        return False


def state_and_funnel():
    try:
        state = json.loads(run(['/usr/bin/tailscale', 'status', '--json']))
        funnel = json.loads(run(['/usr/bin/tailscale', 'funnel', 'status', '--json']))
        return state, funnel
    except (OSError, ValueError, subprocess.SubprocessError):
        return {}, {}


def status():
    state, funnel = state_and_funnel()
    origin = public_origin(state, funnel)
    result = {
        'localOK': healthy('http://127.0.0.1:8080'),
        'publicURL': origin,
        'publicOK': healthy(origin) if origin else False,
        'autostart': subprocess.run(['/usr/bin/systemctl', 'is-enabled', '--quiet', UNIT]).returncode == 0,
    }
    if origin:
        # This file contains only the public endpoint; credentials stay private.
        (DATA / 'direccion-publica.json').write_text(json.dumps({'schema': 1, 'serverURL': origin}))
    return result


def main():
    if os.geteuid() != 0:
        raise SystemExit('Esta acción requiere permiso de administrador.')
    os.umask(0o077)
    command = sys.argv[1] if len(sys.argv) == 2 else ''
    if command == 'connect':
        state, _ = state_and_funnel()
        if state.get('BackendState') != 'Running':
            subprocess.run(['/usr/bin/tailscale', 'up', '--timeout=5m'], check=True, timeout=330)
        subprocess.run(['/usr/bin/tailscale', 'funnel', '--bg', '--yes', 'http://127.0.0.1:8080'], check=True, timeout=330)
        print(json.dumps(status()))
    elif command == 'status':
        print(json.dumps(status()))
    elif command in ('accounts', 'backup'):
        output = run(['/usr/sbin/runuser', '-u', 'reviewnfcgo', '--', str(ROOT / 'venv/bin/python'),
                      str(ROOT / 'runtime.py'), '--data', str(DATA),
                      '--list-accounts' if command == 'accounts' else '--backup'])
        print(output.strip() if command == 'accounts' else 'Copia guardada en /var/lib/reviewnfcgo-cuentas/copias.')
    else:
        raise SystemExit('Acción desconocida. Usa connect, status, accounts o backup.')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, subprocess.SubprocessError):
        raise SystemExit('No se pudo completar. Revisa Internet y termina los permisos de Tailscale en el navegador; después vuelve a intentarlo.')
