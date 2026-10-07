#!/usr/bin/env python3
"""Package already verified release binaries for an optional Sideloadly device trial.

This does not establish that Sideloadly can provision or refresh a paired Watch.
It does not change the canonical iPhone IPA or either SideStore source.
"""
import argparse
import base64
import hashlib
import json
import os
import pathlib
import plistlib
import subprocess
import stat
import tempfile
import urllib.request
import zipfile

REPO = 'polaca1/rese-a-google'
TAG = 'reviewnfcgo-5.0-build21'
NAME = 'reviewNfcGo-5.0-build21-iPhone-Watch-Sideloadly.ipa'
BUNDLE = 'com.pablo.resenagoogle.20261004'


def api(path):
    return json.loads(subprocess.check_output(['gh', 'api', f'repos/{REPO}/{path}'], text=True))


def download(asset):
    assert 0 < asset['size'] < 100_000_000
    with urllib.request.urlopen(asset['browser_download_url'], timeout=60) as response:
        data = response.read(asset['size'] + 1)
    assert len(data) == asset['size'], 'Tamaño de descarga distinto'
    assert asset['digest'] == 'sha256:' + hashlib.sha256(data).hexdigest(), 'SHA256 distinto'
    return data


def extract(archive, target):
    with zipfile.ZipFile(archive) as contents:
        assert contents.testzip() is None
        for name in contents.namelist():
            path = pathlib.PurePosixPath(name)
            assert not path.is_absolute() and '..' not in path.parts
            assert not stat.S_ISLNK(contents.getinfo(name).external_attr >> 16), 'Enlace inesperado en el paquete'
        contents.extractall(target)
        for item in contents.infolist():
            if item.is_dir():
                continue
            mode = (item.external_attr >> 16) & 0o777
            if mode:
                os.chmod(target / item.filename, mode)


def package(output):
    project = pathlib.Path(__file__).resolve().parent.parent
    output.mkdir(parents=True, exist_ok=True)
    release = api(f'releases/tags/{TAG}')
    assert not release['draft'] and not release['prerelease']
    assets = {item['name']: item for item in release['assets']}
    checksums = json.loads(base64.b64decode(api('contents/checksums.json?ref=sidestore')['content']))
    phone = assets['reviewNfcGo-5.0-build21.ipa']
    watch = assets['reviewNfcGo-5.0-Watch-device.zip']
    expected = checksums[phone['name']]
    assert phone['digest'] == 'sha256:' + expected['sha256']
    assert expected['sourceCommit'] == 'e1b069d652b7d05de999f2bc08743a34123021f7'
    destination = output / NAME
    with tempfile.TemporaryDirectory() as directory:
        folder = pathlib.Path(directory)
        phone_zip = folder / 'phone.ipa'; phone_zip.write_bytes(download(phone))
        watch_zip = folder / 'watch.zip'; watch_zip.write_bytes(download(watch))
        payload = folder / 'package'
        extract(phone_zip, payload)
        app = payload / 'Payload/reviewNfcGo.app'
        extract(watch_zip, app / 'Watch')
        wrist = app / 'Watch/reviewNfcGoWatch.app'
        watch_widget = wrist / 'PlugIns/reviewNfcGoWatchWidgets.appex'
        phone_widget = app / 'PlugIns/reviewNfcGoLiveActivity.appex'
        identifiers = [BUNDLE, BUNDLE + '.liveactivity', BUNDLE + '.watch', BUNDLE + '.watch.widgets']
        bundles = [app, phone_widget, wrist, watch_widget]
        for bundle, identifier in zip(bundles, identifiers):
            info = plistlib.loads((bundle / 'Info.plist').read_bytes())
            assert info['CFBundleIdentifier'] == identifier, (bundle.name, info['CFBundleIdentifier'])
            assert info['CFBundleShortVersionString'] == '5.0' and info['CFBundleVersion'] == '21'
            assert (bundle / info['CFBundleExecutable']).is_file()
        assert plistlib.loads((wrist / 'Info.plist').read_bytes())['WKCompanionAppBundleIdentifier'] == BUNDLE
        # Supply real ad-hoc entitlement templates. Sideloadly must replace all
        # signatures and obtain valid device profiles from the user's account.
        for bundle, entitlement in [
            (watch_widget, project / 'reviewNfcGoWatchWidgets/WatchWidgets.entitlements'),
            (wrist, project / 'reviewNfcGoWatch/Watch.entitlements'),
            (app, project / 'reviewNfcGo/reviewNfcGo.entitlements'),
        ]:
            subprocess.run(['codesign', '--force', '--sign', '-', '--entitlements', str(entitlement), str(bundle)], check=True)
        subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
        for bundle in [wrist, watch_widget]:
            signed = subprocess.run(['codesign', '-d', '--entitlements', ':-', str(bundle)], capture_output=True, check=True)
            entitlement = plistlib.loads(signed.stdout)
            assert 'group.com.pablo.resenagoogle.20261004.watch' in entitlement['com.apple.security.application-groups']
        subprocess.run(['/usr/bin/zip', '-qry', str(destination), 'Payload'], cwd=payload, check=True)
    with zipfile.ZipFile(destination) as archive:
        assert archive.testzip() is None
        assert 'Payload/reviewNfcGo.app/Watch/reviewNfcGoWatch.app/reviewNfcGoWatch' in archive.namelist()
    report = {
        'package': NAME, 'version': '5.0', 'build': '21',
        'sha256': hashlib.sha256(destination.read_bytes()).hexdigest(), 'size': destination.stat().st_size,
        'compiledSourceCommit': expected['sourceCommit'],
        'originalPhoneSHA256': expected['sha256'], 'originalWatchDigest': watch['digest'],
        'embeddedWatch': True, 'embeddedWatchWidget': True, 'adHocSignaturesVerified': True,
        'sideloadlyDeviceInstallationVerified': False, 'watchAutomaticRefreshVerified': False,
        'signingRequired': True,
    }
    report_file = output / 'Sideloadly-Watch-package.json'
    report_file.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))
    # Publish once. Never replace an already downloaded package with different bytes.
    if NAME in assets:
        assert assets[NAME]['digest'] == 'sha256:' + report['sha256'], 'Ya hay otro paquete publicado con ese nombre'
    else:
        subprocess.run(['gh', 'release', 'upload', TAG, str(destination), str(report_file), '--repo', REPO], check=True)
    guide = project / 'SIDELOADLY-WATCH.md'
    subprocess.run(['gh', 'release', 'upload', TAG, str(guide), '--repo', REPO, '--clobber'], check=True)
    print(f'Paquete opcional publicado: {release["html_url"]}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=pathlib.Path, required=True)
    package(parser.parse_args().output.resolve())
