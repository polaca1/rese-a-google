#!/usr/bin/env python3
"""Publish a verified IPA and maintain the permanent SideStore source."""
import argparse
import base64
import datetime
import hashlib
import json
import pathlib
import plistlib
import re
import subprocess
import tempfile
import zipfile

REPO = 'polaca1/rese-a-google'
BRANCH = 'sidestore'
RAW = f'https://raw.githubusercontent.com/{REPO}/refs/heads/{BRANCH}'
BUNDLE = 'com.pablo.resenagoogle.20261004'


def api(method, path, payload=None, missing=False):
    cmd = ['gh', 'api', '--method', method, f'repos/{REPO}/{path}']
    if payload is not None:
        cmd += ['--input', '-']
    result = subprocess.run(cmd, input=json.dumps(payload) if payload is not None else None,
                            text=True, capture_output=True)
    if result.returncode:
        if missing and '404' in result.stderr:
            return None
        raise RuntimeError(result.stderr.strip())
    return json.loads(result.stdout) if result.stdout.strip() else None


def version_key(version):
    return tuple(int(part) for part in version.split('.'))


def publish(args):
    ipa = pathlib.Path(args.ipa).resolve()
    with zipfile.ZipFile(ipa) as archive:
        assert archive.testzip() is None, 'Paquete IPA dañado'
        app_info = plistlib.loads(archive.read('Payload/reviewNfcGo.app/Info.plist'))
        assert app_info['CFBundleIdentifier'] == BUNDLE, 'Identificador inesperado'
        privacy, minimums = {}, []
        for name in archive.namelist():
            if name.endswith('/Info.plist') and (name.count('/') == 2 or '.appex/' in name):
                info = plistlib.loads(archive.read(name))
                privacy.update({key: value for key, value in info.items() if key.endswith('UsageDescription')})
                minimums.append(info.get('MinimumOSVersion', '16.0'))
    version, build = app_info['CFBundleShortVersionString'], app_info['CFBundleVersion']
    assert re.fullmatch(r'\d+(?:\.\d+){0,2}', version) and re.fullmatch(r'\d+', build)
    notes = pathlib.Path(args.notes).read_text().strip()
    tag = f'reviewnfcgo-{version}-build{build}'
    existing_release = api('GET', f'releases/tags/{tag}', missing=True)
    release_name = f'reviewNfcGo {version} ({build})'
    if existing_release is None:
        subprocess.run(['gh', 'release', 'create', tag, '--repo', REPO, '--target', args.source_commit,
                        '--title', release_name, '--notes-file', args.notes, '--latest=false'], check=True)
    else:
        assert not existing_release['draft'] and not existing_release['prerelease']
    filename = f'reviewNfcGo-{version}-build{build}.ipa'
    download_url = RAW + '/ipas/' + filename
    digest = hashlib.sha256(ipa.read_bytes()).hexdigest()
    release = api('GET', f'releases/tags/{tag}')

    ref = api('GET', f'git/ref/heads/{BRANCH}', missing=True)
    current_file = api('GET', f'contents/source.json?ref={BRANCH}', missing=True) if ref else None
    source = json.loads(base64.b64decode(current_file['content'])) if current_file else {
        'name': 'reviewNfcGo · Pablo Cancho Flores',
        'identifier': 'com.pablo.reviewnfcgo.source',
        'iconURL': RAW + '/icon.png',
        'sourceURL': RAW + '/source.json', 'apps': [], 'news': []}
    assert source['identifier'] == 'com.pablo.reviewnfcgo.source', 'No se cambia el identificador de la fuente'
    source['sourceURL'] = RAW + '/source.json'
    source['iconURL'] = RAW + '/icon.png'
    for key in ['subtitle', 'description', 'tintColor']:
        source.pop(key, None)
    if not source['apps']:
        source['apps'] = [{
            'name': 'reviewNfcGo', 'bundleIdentifier': BUNDLE, 'developerName': 'Pablo Cancho Flores',
            'subtitle': 'Negocios, tarjetas NFC, visitas y dinero',
            'localizedDescription': 'Encuentra negocios y organiza tus visitas, tarjetas NFC e ingresos y gastos. '
                'Incluye inventario por color, historial de operaciones, foto de perfil, widgets y recordatorios con cuenta atrás.',
            'iconURL': RAW + '/icon.png', 'tintColor': '1976EC', 'versions': []}]
    app = source['apps'][0]
    assert app['bundleIdentifier'] == BUNDLE
    app['iconURL'] = RAW + '/icon.png'
    entry = {'version': version, 'buildVersion': build, 'date': release['published_at'],
             'localizedDescription': notes, 'downloadURL': download_url,
             'size': ipa.stat().st_size, 'minOSVersion': max(minimums, key=version_key)}
    app['versions'] = [v for v in app['versions'] if (v['version'], v.get('buildVersion')) != (version, build)] + [entry]
    app['versions'].sort(key=lambda v: (version_key(v['version']), int(v.get('buildVersion', '0'))), reverse=True)
    newest = app['versions'][0]
    # Compatibility with older clients, in addition to the modern versions array.
    app.update({'version': newest['version'], 'versionDate': newest['date'],
                'versionDescription': newest['localizedDescription'], 'downloadURL': newest['downloadURL'], 'size': newest['size']})
    app['appPermissions'] = {'entitlements': ['com.apple.security.application-groups'], 'privacy': privacy}
    app['permissions'] = [{'type': 'location', 'usageDescription': privacy['NSLocationWhenInUseUsageDescription']},
                          {'type': 'network', 'usageDescription': 'Buscar negocios y consultar enlaces de compra.'}]
    news = {'title': release_name, 'identifier': tag, 'caption': notes.splitlines()[0],
            'date': release['published_at'], 'tintColor': '1976EC', 'notify': entry == newest,
            'url': release['html_url'], 'appID': BUNDLE}
    source['news'] = [n for n in source['news'] if n['identifier'] != tag] + [news]
    source['news'].sort(key=lambda n: n['date'], reverse=True)
    checksum_file = api('GET', f'contents/checksums.json?ref={BRANCH}', missing=True) if ref else None
    checksums = json.loads(base64.b64decode(checksum_file['content'])) if checksum_file else {}
    if filename in checksums:
        assert checksums[filename]['sha256'] == digest, 'No se reemplaza una versión por bytes diferentes'
    checksums[filename] = {'sha256': digest, 'size': ipa.stat().st_size, 'sourceCommit': args.source_commit}
    files = {'ipas/' + filename: ipa.read_bytes(),
             'checksums.json': (json.dumps(checksums, indent=2) + '\n').encode(),
             'SHA256SUMS.txt': ''.join(f'{value["sha256"]}  ipas/{key}\n' for key, value in sorted(checksums.items())).encode(),
             'source.json': (json.dumps(source, ensure_ascii=False, indent=2) + '\n').encode(),
             'README.md': ('# reviewNfcGo\n\nDesarrollado por Pablo Cancho Flores.\n\n'
                f'Fuente para SideStore y AltStore: **{RAW}/source.json**\n\n'
                'En SideStore abre Sources, pulsa + y pega el enlace. Las actualizaciones y notas de versión '
                'aparecen en la misma fuente. Actualiza la app instalada para conservar tus datos.\n\n'
                'Los IPA de cada versión están en ipas/ y sus comprobaciones en SHA256SUMS.txt. Releases contiene las notas y enlaces de descarga.\n').encode()}
    if args.previews:
        previews = pathlib.Path(args.previews)
        for local, remote in [('icon-native-light.png', 'icon.png'), ('icon-native-dark.png', 'icon-dark.png')]:
            if (previews / local).exists():
                files[remote] = (previews / local).read_bytes()
        screenshots = []
        for name in ['blur-home-light.png', 'money-light.png', 'inventory-light.png', 'reminder-dates-light.png']:
            if (previews / name).exists():
                files['screenshots/' + name] = (previews / name).read_bytes()
                screenshots.append(RAW + '/screenshots/' + name)
        if screenshots:
            app['screenshotURLs'] = screenshots
            files['source.json'] = (json.dumps(source, ensure_ascii=False, indent=2) + '\n').encode()
    entries = []
    for name, content in files.items():
        blob = api('POST', 'git/blobs', {'content': base64.b64encode(content).decode(), 'encoding': 'base64'})
        entries.append({'path': name, 'mode': '100644', 'type': 'blob', 'sha': blob['sha']})
    tree_payload = {'tree': entries}
    parents = []
    if ref:
        parent = ref['object']['sha']
        parents = [parent]
        tree_payload['base_tree'] = api('GET', f'git/commits/{parent}')['tree']['sha']
    tree = api('POST', 'git/trees', tree_payload)
    commit = api('POST', 'git/commits', {'message': f'Publish {release_name} to SideStore',
                 'tree': tree['sha'], 'parents': parents})
    if ref:
        api('PATCH', f'git/refs/heads/{BRANCH}', {'sha': commit['sha'], 'force': False})
    else:
        api('POST', 'git/refs', {'ref': f'refs/heads/{BRANCH}', 'sha': commit['sha']})
    with tempfile.TemporaryDirectory() as folder:
        release_notes = pathlib.Path(folder) / 'notes.md'
        release_notes.write_text(notes + f'\n\n[Descargar IPA]({download_url})\n\nSHA256: `{digest}`\n')
        edit = ['gh', 'release', 'edit', tag, '--repo', REPO, '--notes-file', str(release_notes)]
        if entry == newest:
            edit.append('--latest')
        subprocess.run(edit, check=True)
    print(f'Publicado {release_name}: {RAW}/source.json')
    subprocess.run(['python3', str(pathlib.Path(__file__).with_name('publish-release-assets.py'))], check=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--ipa', required=True)
    parser.add_argument('--source-commit', required=True)
    parser.add_argument('--notes', required=True)
    parser.add_argument('--previews')
    publish(parser.parse_args())
