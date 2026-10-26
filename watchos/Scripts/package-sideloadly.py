#!/usr/bin/env python3
"""Embed a matching, verified Watch bundle in a separate IPA for a capable signer.

Never replaces the canonical iPhone IPA. Does not sign, provision or bypass
Apple account limitations; Sideloadly must sign the phone and Watch bundles.
"""
import argparse
import hashlib
import pathlib
import plistlib
import stat
import zipfile

PHONE = 'Payload/reviewNfcGo.app/'
WATCH = 'reviewNfcGoWatch.app/'

def safe_entries(archive):
    if archive.testzip() is not None:
        raise ValueError('Archivo ZIP dañado')
    entries = archive.infolist()
    if len({x.filename for x in entries}) != len(entries):
        raise ValueError('Entradas duplicadas en el paquete')
    for item in entries:
        path = pathlib.PurePosixPath(item.filename)
        if path.is_absolute() or '..' in path.parts or stat.S_ISLNK(item.external_attr >> 16):
            raise ValueError('Ruta o enlace no admitido en el paquete')
    return entries

def package(phone, watch, output):
    phone, watch, output = map(pathlib.Path, (phone, watch, output))
    if output.resolve() in (phone.resolve(), watch.resolve()) or output.exists():
        raise ValueError('La salida debe ser nueva; no se sustituyen los paquetes originales')
    before = hashlib.sha256(phone.read_bytes()).hexdigest()
    with zipfile.ZipFile(phone) as main, zipfile.ZipFile(watch) as companion:
        originals, children = safe_entries(main), safe_entries(companion)
        parent = plistlib.loads(main.read(PHONE+'Info.plist'))
        child = plistlib.loads(companion.read(WATCH+'Info.plist'))
        if any(x.filename.startswith(PHONE+'Watch/') for x in originals):
            raise ValueError('El iPhone ya contiene otro Watch')
        if parent['CFBundleIdentifier'] != 'com.pablo.resenagoogle.20261004':
            raise ValueError('La app de iPhone no es reviewNfcGo')
        if not child.get('WKApplication') or child['WKCompanionAppBundleIdentifier'] != parent['CFBundleIdentifier'] or not child['CFBundleIdentifier'].startswith(parent['CFBundleIdentifier']+'.'):
            raise ValueError('El Watch no pertenece a la app de iPhone')
        if any(parent[x] != child[x] for x in ('CFBundleShortVersionString','CFBundleVersion')):
            raise ValueError('Las versiones de iPhone y Watch no coinciden')
        if not companion.read(WATCH+child['CFBundleExecutable']):
            raise ValueError('Falta el ejecutable del Watch')
        output.parent.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(output, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=6) as combined:
            for item in originals:
                if item.filename.startswith(PHONE+'_CodeSignature/'):
                    continue
                combined.writestr(item, main.read(item.filename))
            for item in children:
                if not item.filename.startswith(WATCH) or '/_CodeSignature/' in item.filename:
                    continue
                target = zipfile.ZipInfo(PHONE+'Watch/'+item.filename, item.date_time)
                target.external_attr = item.external_attr
                target.compress_type = zipfile.ZIP_DEFLATED
                combined.writestr(target, companion.read(item.filename))
    with zipfile.ZipFile(output) as assembled:
        assert assembled.testzip() is None
        assert assembled.read(PHONE+'Watch/'+WATCH+'Info.plist') == plistlib.dumps(child) or plistlib.loads(assembled.read(PHONE+'Watch/'+WATCH+'Info.plist')) == child
    assert hashlib.sha256(phone.read_bytes()).hexdigest() == before
    return {'version':parent['CFBundleShortVersionString'], 'build':parent['CFBundleVersion'],
            'sha256':hashlib.sha256(output.read_bytes()).hexdigest(), 'size':output.stat().st_size,
            'watchBundle':child['CFBundleIdentifier'], 'signingRequired':True}

if __name__ == '__main__':
    import json
    parser = argparse.ArgumentParser()
    parser.add_argument('--iphone', required=True)
    parser.add_argument('--watch', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    print(json.dumps(package(args.iphone,args.watch,args.output)))
