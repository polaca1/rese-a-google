#!/usr/bin/env python3
"""Configure the free Xcode Watch target for the real SideStore companion ID.

Runs locally on the user's Mac. Does not sign in, send data, install an app,
read private keys or purchase anything. Xcode handles signing after the user
selects their own Personal Team and paired Watch.
"""
import argparse
import json
import pathlib
import plistlib
import re
import subprocess
import tempfile

ORIGINAL = 'com.pablo.resenagoogle.20261004'

def valid_id(value):
    return isinstance(value, str) and re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9.-]{1,230}', value) is not None

def companion_apps(document):
    values = document.get('result', {}).get('apps', [])
    if not isinstance(values, list):
        raise ValueError('El listado de aplicaciones no tiene el formato esperado.')
    return [x for x in values if valid_id(x.get('bundleIdentifier')) and
            (ORIGINAL in x['bundleIdentifier'] or x.get('name', '').lower() == 'reviewnfcgo')]

def choose_bundle(document):
    values = companion_apps(document)
    if len(values) != 1:
        raise ValueError('Conecta el iPhone con una sola instalación de reviewNfcGo, o indica --bundle-id con su identificador real.')
    return values[0]['bundleIdentifier']

def configure(root, bundle):
    if not valid_id(bundle):
        raise ValueError('Identificador de la app no válido.')
    project = root / 'reviewNfcGoWatch.xcodeproj/project.pbxproj'
    text = project.read_text()
    text, count = re.subn(r'PRODUCT_BUNDLE_IDENTIFIER\s*=\s*[^;]+;',
                          lambda _: 'PRODUCT_BUNDLE_IDENTIFIER = ' + bundle + '.watch;', text)
    if count != 2:
        raise ValueError('El proyecto de Watch no contiene las dos configuraciones esperadas.')
    info = root / 'reviewNfcGoWatch/Info.plist'
    data = plistlib.loads(info.read_bytes())
    if not data.get('WKApplication'):
        raise ValueError('El archivo no es una app de Watch válida.')
    data['WKCompanionAppBundleIdentifier'] = bundle
    project.write_text(text)
    info.write_bytes(plistlib.dumps(data))

def main():
    parser = argparse.ArgumentParser(description='Preparar el complemento de Watch para la app real del iPhone')
    parser.add_argument('--phone', help='Identificador del iPhone emparejado que muestra Xcode')
    parser.add_argument('--bundle-id', help='Identificador real de la app del iPhone; permite configurar sin consultar un dispositivo')
    parser.add_argument('--dry-run', action='store_true', help='Comprobar sin modificar el proyecto')
    args = parser.parse_args()
    bundle = args.bundle_id
    if bundle is None:
        if not args.phone:
            raise ValueError('Indica --phone con el identificador del iPhone, o --bundle-id con el identificador real de reviewNfcGo. No uses el del reloj en --phone.')
        with tempfile.TemporaryDirectory() as temporary:
            output = pathlib.Path(temporary) / 'apps.json'
            subprocess.run(['xcrun', 'devicectl', 'device', 'info', 'apps', '--device', args.phone,
                            '--json-output', str(output)], check=True, stdout=subprocess.DEVNULL)
            bundle = choose_bundle(json.loads(output.read_text()))
    if not valid_id(bundle):
        raise ValueError('Identificador de la app no válido.')
    if args.dry_run:
        print('Configuración comprobada; no se han modificado archivos.')
        return
    configure(pathlib.Path(__file__).resolve().parents[1], bundle)
    print('Proyecto preparado para el identificador real del iPhone. Abre el proyecto Watch, selecciona tu Personal Team y el reloj enlazado y pulsa Run. No se ha instalado ni firmado nada todavía.')

if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        raise SystemExit(str(error))
