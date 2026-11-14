#!/usr/bin/env python3
"""Build the real Day/UIKit entry point with a temporary Xcode 26 PBX compatibility host.
The conventional Day project and its Xcode 27 host remain unchanged. Never uses preview/.
"""
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
os.chdir(root)
day = os.environ.get('DAY_BIN', 'day')
number = int(os.environ.get('DAY_DEVICE_BUILD', '42'))
# Each cloud candidate gets a fresh build number before Day resolves its metadata.
flavor = root / 'Day-device.toml'
source = flavor.read_text()
source = source.replace('build = 42', 'build = ' + str(number))
flavor.write_text(source)
os.environ['DAY_FLAVOR'] = 'device'
subprocess.run([day, 'prepare', '-t', 'ios-uikit', '--flavor', 'device'], check=True)
out = root / 'build/day-device'
out.mkdir(parents=True, exist_ok=True)
info = plistlib.loads((root / 'platform/ios/Runner/Info.plist').read_bytes())
info.update(DayHostIncluded=True, ReviewNfcGoDistributionMode='day-uikit-device-candidate',
            DayCompatibilityHost='XcodeGen PBX with Day Runner and xcode-backend',
            NSLocationWhenInUseUsageDescription='Encuentra los negocios cercanos y distingue locales vecinos.')
(out / 'RunnerInfo.plist').write_bytes(plistlib.dumps(info))
settings = {
    'SWIFT_VERSION': '6.0', 'IPHONEOS_DEPLOYMENT_TARGET': '16.1',
    'CODE_SIGNING_ALLOWED': 'NO', 'ENABLE_USER_SCRIPT_SANDBOXING': 'NO',
    'TARGETED_DEVICE_FAMILY': '1,2', 'MARKETING_VERSION': '7.3.1',
    'CURRENT_PROJECT_VERSION': str(number), 'DAY_PROJECT_ROOT': str(root),
    'DAY_APP_TITLE': 'reviewNfcGo', 'DAY_URL_SCHEME': 'reviewnfcgo',
    'DAY_WINDOW_MIN_WIDTH': '320', 'DAY_WINDOW_MIN_HEIGHT': '400',
    'DAY_BIN': day, 'DAY_FLAVOR': 'device', 'SDKROOT': 'iphoneos',
}
spec = {
    'name': 'ReviewNfcGoDayDevice',
    'options': {'deploymentTarget': {'iOS': '16.1'}},
    'settings': {'base': settings},
    'packages': {'DayPieces': {'path': str(root / 'build/day/ios/DayPieces')}},
    'targets': {
        'reviewNfcGo': {
            'type': 'application', 'platform': 'iOS',
            'sources': [{'path': str(root / 'platform/ios/Runner/main.swift')},
                        {'path': str(root / 'build/day/host/ios/Assets.xcassets')},
                        {'path': str(root / 'platform/ios/Runner/InfoPlist.xcstrings')},
                        {'path': str(root / 'platform/ios/Runner/PrivacyInfo.xcprivacy')},
                        {'path': str(root / 'platform/ios/Runner/ThirdPartyNotices.txt')}],
            'settings': {'base': {
                'PRODUCT_BUNDLE_IDENTIFIER': 'com.pablo.resenagoogle.20261004',
                'ASSETCATALOG_COMPILER_APPICON_NAME': 'AppIcon',
                'INFOPLIST_FILE': str(out / 'RunnerInfo.plist'),
                'CODE_SIGN_ENTITLEMENTS': str(root / 'platform/ios/Runner/ReviewNfcGo.entitlements'),
                'OTHER_LDFLAGS': '@"$(BUILT_PRODUCTS_DIR)/day/dayapp-link.rsp"',
                'LD_GENERATE_MAP_FILE': 'YES',
                'LD_MAP_FILE_PATH': str(out / 'day-link-map.txt'),
            }},
            'dependencies': [{'package': 'DayPieces', 'product': 'DayPieces'},
                             {'target': 'ReviewNfcGoWidgets', 'embed': True}],
            'preBuildScripts': [{
                'name': 'Build Rust (Day)',
                'script': '"$DAY_BIN" xcode-backend build --project "$DAY_PROJECT_ROOT" --flavor device',
                'basedOnDependencyAnalysis': False,
                'outputFiles': ['$(BUILT_PRODUCTS_DIR)/day/libdayapp.a', '$(BUILT_PRODUCTS_DIR)/day/dayapp-link.rsp'],
            }],
            'postBuildScripts': [{
                'name': 'Stage Day Strings',
                'script': '"$DAY_BIN" xcode-backend stage-strings --project "$DAY_PROJECT_ROOT" --flavor device',
                'basedOnDependencyAnalysis': False,
            }],
        },
        'ReviewNfcGoWidgets': {
            'type': 'app-extension', 'platform': 'iOS',
            'sources': [{'path': str(root / 'platform/ios/ReviewNfcGoWidgets')}],
            'settings': {'base': {
                'SWIFT_VERSION': '5.0', 'APPLICATION_EXTENSION_API_ONLY': 'YES',
                'PRODUCT_BUNDLE_IDENTIFIER': 'com.pablo.resenagoogle.20261004.liveactivity',
                'SWIFT_ACTIVE_COMPILATION_CONDITIONS': '$(inherited) WIDGET_EXTENSION',
                'INFOPLIST_FILE': str(root / 'build/day/extensions/ios/ReviewNfcGoWidgets/Info.plist'),
                'CODE_SIGN_ENTITLEMENTS': str(root / 'build/day/extensions/ios/ReviewNfcGoWidgets/ReviewNfcGoWidgets.entitlements'),
            }},
        },
    },
    'schemes': {'reviewNfcGo': {'build': {'targets': {'reviewNfcGo': 'all'}}, 'archive': {'config': 'Release'}}},
}
(out / 'project.json').write_text(json.dumps(spec, indent=2))
subprocess.run(['xcodegen', 'generate', '--spec', str(out / 'project.json'), '--project', str(out)], check=True)
archive = out / 'reviewNfcGo.xcarchive'
subprocess.run(['xcodebuild', '-project', str(out / 'ReviewNfcGoDayDevice.xcodeproj'), '-scheme', 'reviewNfcGo',
                '-configuration', 'Release', '-destination', 'generic/platform=iOS',
                '-archivePath', str(archive), 'CODE_SIGNING_ALLOWED=NO', 'archive'], check=True)
app = archive / 'Products/Applications/reviewNfcGo.app'
subprocess.run([sys.executable, str(root / 'scripts/verify-day-device.py'), str(app), str(number), str(out / 'day-link-map.txt')], check=True)
print(app)
