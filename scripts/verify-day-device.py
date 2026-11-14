#!/usr/bin/env python3
"""Verify the Day device archive, its linked Rust entry point and widget identity."""
import json
import re
from pathlib import Path
import plistlib
import subprocess
import sys

app = Path(sys.argv[1])
info = plistlib.loads((app / 'Info.plist').read_bytes())
assert info['CFBundleIdentifier'] == 'com.pablo.resenagoogle.20261004'
assert info['CFBundleVersion'] == sys.argv[2]
assert info['DayHostIncluded'] is True
assert info['ReviewNfcGoDistributionMode'] == 'day-uikit-device-candidate'
binary = app / info['CFBundleExecutable']
arches = subprocess.check_output(['lipo', '-archs', str(binary)], text=True).strip()
assert arches == 'arm64', arches
platform = subprocess.check_output(['xcrun', 'vtool', '-show-build', str(binary)], text=True)
assert 'platform IOS\n' in platform and 'IOSSIMULATOR' not in platform
symbols = subprocess.check_output(['nm', str(binary)], text=True)
if '_day_main' not in symbols:
    # Release archives can remove static symbols after linking. Inspect the live-symbol map,
    # emitted by Apple's linker before stripping, rather than weakening the entry-point check.
    link_map = Path(sys.argv[3]).read_text()
    live = link_map.split('# Symbols:', 1)[1].split('# Dead Stripped Symbols:', 1)[0]
    assert 'libdayapp.a' in link_map, 'Rust archive not present in the linker map'
    assert re.search(r'0x[0-9A-Fa-f]+\s+0x[0-9A-Fa-f]+\s+\[\s*\d+\]\s+_day_main(?:\s|$)', live), 'Live Day entry point missing' 
widget = app / 'PlugIns/ReviewNfcGoWidgets.appex'
winfo = plistlib.loads((widget / 'Info.plist').read_bytes())
assert winfo['CFBundleIdentifier'] == info['CFBundleIdentifier'] + '.liveactivity'
assert winfo['CFBundleVersion'] == info['CFBundleVersion']
assert (widget / winfo['CFBundleExecutable']).is_file()
assert list(app.rglob('PrivacyInfo.xcprivacy'))
print(json.dumps({'version': info['CFBundleShortVersionString'], 'build': info['CFBundleVersion'],
                  'dayHostIncluded': True, 'architecture': arches, 'widget': True,
                  'physicalInstallationVerified': False}))
