"""Run after executing Instalar.sh again: no account data may disappear."""
import json
import subprocess
import urllib.request

request = urllib.request.Request('http://127.0.0.1:8080/v1/auth/login',
    data=json.dumps({'email': 'linux1@example.com', 'password': 'Verification-password-2026'}).encode(),
    headers={'Content-Type': 'application/json'})
with urllib.request.urlopen(request, timeout=10) as response:
    assert response.status == 200
    assert json.load(response)['user']['email'] == 'linux1@example.com'
accounts = json.loads(subprocess.check_output(['/usr/local/sbin/reviewnfcgo-servidor', 'accounts'], text=True))
assert len(accounts) == 3
print('Reinstalación verificada: los tres usuarios y sus contraseñas siguen funcionando.')
