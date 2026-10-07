#!/usr/bin/env python3
"""Move SideStore downloads to permanent, checksum-verified GitHub release assets."""
import base64
import hashlib
import json
import pathlib
import subprocess
import tempfile
import urllib.request

REPO = 'polaca1/rese-a-google'
BRANCH = 'sidestore'


def api(path, method='GET', payload=None):
    command = ['gh', 'api', '--method', method, f'repos/{REPO}/{path}']
    if payload is not None:
        command += ['--input', '-']
    result = subprocess.run(command, input=json.dumps(payload) if payload else None,
                            text=True, capture_output=True, check=True)
    return json.loads(result.stdout)


def contents(path):
    response = api(f'contents/{path}?ref={BRANCH}')
    return response, json.loads(base64.b64decode(response['content']))


def publish():
    source_file, source = contents('source.json')
    _, checksums = contents('checksums.json')
    app = source['apps'][0]
    changed = False
    with tempfile.TemporaryDirectory() as directory:
        for version in app['versions']:
            filename = f'reviewNfcGo-{version["version"]}-build{version["buildVersion"]}.ipa'
            tag = f'reviewnfcgo-{version["version"]}-build{version["buildVersion"]}'
            expected = checksums[filename]
            assert expected['size'] == version['size']
            release = api(f'releases/tags/{tag}')
            assert not release['draft'] and not release['prerelease']
            assets = [a for a in release['assets'] if a['name'] == filename]
            if not assets:
                path = pathlib.Path(directory) / filename
                with urllib.request.urlopen(version['downloadURL'], timeout=60) as response:
                    data = response.read(expected['size'] + 1)
                assert len(data) == expected['size'], f'Tamaño incorrecto: {filename}'
                assert hashlib.sha256(data).hexdigest() == expected['sha256'], f'IPA distinto: {filename}'
                path.write_bytes(data)
                subprocess.run(['gh', 'release', 'upload', tag, str(path), '--repo', REPO], check=True)
                release = api(f'releases/tags/{tag}')
                assets = [a for a in release['assets'] if a['name'] == filename]
            assert len(assets) == 1
            asset = assets[0]
            assert asset['state'] == 'uploaded' and asset['size'] == expected['size']
            if asset.get('digest'):
                assert asset['digest'] == 'sha256:' + expected['sha256']
            # Verify the public URL as well; metadata alone cannot prove the download works.
            with urllib.request.urlopen(asset['browser_download_url'], timeout=60) as response:
                data = response.read(expected['size'] + 1)
            assert len(data) == expected['size']
            assert hashlib.sha256(data).hexdigest() == expected['sha256']
            if version['downloadURL'] != asset['browser_download_url']:
                version['downloadURL'] = asset['browser_download_url']
                changed = True
            print(f'Verificado {filename}: asset público y SHA256 correcto', flush=True)
    app['downloadURL'] = app['versions'][0]['downloadURL']
    if changed:
        api('contents/source.json', method='PUT', payload={
            'message': 'Use verified GitHub release assets for SideStore downloads',
            'branch': BRANCH, 'sha': source_file['sha'],
            'content': base64.b64encode((json.dumps(source, ensure_ascii=False, indent=2) + '\n').encode()).decode()})
    print('Fuente SideStore actualizada con descargas de GitHub Releases', flush=True)


if __name__ == '__main__':
    publish()
