#!/usr/bin/env python3
"""Verify a device build and its embedded extension before distributing an IPA."""
import json
import plistlib
import subprocess
import sys
from pathlib import Path

app = Path(sys.argv[1])
info = plistlib.loads((app / 'Info.plist').read_bytes())
assert info['CFBundleIdentifier'] == 'com.pablo.resenagoogle.20261004'
assert info['CFBundleShortVersionString'] == '7.3.1'
assert info['CFBundleVersion'] == '41'
assert info['ReviewNfcGoDistributionMode'] == 'native-swiftui-preview'
assert info['DayHostIncluded'] is False
binary = app / info['CFBundleExecutable']
arches = subprocess.check_output(['lipo', '-archs', str(binary)], text=True).strip()
assert 'arm64' in arches and 'x86_64' not in arches, arches
platform = subprocess.check_output(['xcrun', 'vtool', '-show-build', str(binary)], text=True)
assert 'platform IOS\n' in platform and 'IOSSIMULATOR' not in platform, platform
widget = app / 'PlugIns/ReviewNfcGoWidgets.appex'
winfo = plistlib.loads((widget / 'Info.plist').read_bytes())
assert winfo['CFBundleIdentifier'] == info['CFBundleIdentifier'] + '.liveactivity'
assert winfo['CFBundleVersion'] == info['CFBundleVersion']
assert winfo['NSExtension']['NSExtensionPointIdentifier'] == 'com.apple.widgetkit-extension'
assert (widget / winfo['CFBundleExecutable']).is_file()
assert list(app.rglob('PrivacyInfo.xcprivacy')), 'Privacy manifest missing'
print(json.dumps({'version':info['CFBundleShortVersionString'],'build':info['CFBundleVersion'],
                 'architecture':arches,'widget':True,'dayHostIncluded':False,
                 'physicalInstallationVerified':False}))
