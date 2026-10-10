#!/bin/bash
set -euo pipefail
task_root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
task_out=${1:-"$task_root/macos/build"}
mkdir -p "$task_out"
task_out=$(cd "$task_out" && pwd)
task_resources="$task_root/macos/reviewNfcGo/Resources"
task_project_root="$task_root"
source "$task_root/ios/reviewNfcGo/Scripts/load-places-key.sh"
task_icons="$task_out/AppIcon.iconset"
mkdir -p "$task_icons"
for task_size in 16 32 64 128 256 512; do
  sips -z "$task_size" "$task_size" "$task_resources/SourceIcon.png" --out "$task_icons/icon_${task_size}x${task_size}.png" >/dev/null
done
for task_size in 16 32 128 256 512; do
  sips -z "$((task_size * 2))" "$((task_size * 2))" "$task_resources/SourceIcon.png" --out "$task_icons/icon_${task_size}x${task_size}@2x.png" >/dev/null
done
iconutil -c icns "$task_icons" -o "$task_resources/AppIcon.icns"

xcodebuild -project "$task_root/macos/reviewNfcGo.xcodeproj" -scheme reviewNfcGoMac \
  -configuration Release -destination 'generic/platform=macOS' -derivedDataPath "$task_out/DerivedData" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO ONLY_ACTIVE_ARCH=NO ARCHS='arm64 x86_64' build \
  > "$task_out/mac-build.log" 2>&1 || { tail -n 100 "$task_out/mac-build.log"; exit 1; }
task_app="$task_out/DerivedData/Build/Products/Release/reviewNfcGo.app"
python3 - "$task_app/Contents/Info.plist" <<'PY'
import os,pathlib,plistlib,sys
p=pathlib.Path(sys.argv[1]);v=plistlib.loads(p.read_bytes())
for field,variable in [('GooglePlacesAPIKey','GOOGLE_PLACES_API_KEY'),('GooglePlacesFallbackAPIKey','GOOGLE_PLACES_FALLBACK_API_KEY')]:v[field]=os.environ.get(variable,'')
assert v['LSMinimumSystemVersion']=='14.0', 'El paquete debe admitir Sonoma'
p.write_bytes(plistlib.dumps(v))
PY
lipo "$task_app/Contents/MacOS/reviewNfcGoMac" -verify_arch arm64 x86_64
codesign --force --sign - --timestamp=none "$task_app"
codesign --verify --deep --strict "$task_app"
ditto -c -k --sequesterRsrc --keepParent "$task_app" "$task_out/reviewNfcGo-Mac-2.0.zip"
mkdir -p "$task_out/Installer"
ditto "$task_app" "$task_out/Installer/reviewNfcGo.app"
ln -s /Applications "$task_out/Installer/Applications"
cp "$task_root/macos/LEEME.txt" "$task_out/Installer/LEEME.txt"
hdiutil create -volname reviewNfcGo -srcfolder "$task_out/Installer" -ov -format UDZO "$task_out/reviewNfcGo-Mac-2.0.dmg" >/dev/null

# The native app is exercised on the runner with an isolated data directory.
xcodebuild -project "$task_root/macos/reviewNfcGo.xcodeproj" -scheme reviewNfcGoMac \
  -configuration Debug -destination 'platform=macOS' -derivedDataPath "$task_out/DerivedData" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build \
  > "$task_out/mac-debug.log" 2>&1 || { tail -n 100 "$task_out/mac-debug.log"; exit 1; }
task_debug="$task_out/DerivedData/Build/Products/Debug/reviewNfcGo.app"
codesign --force --sign - --timestamp=none "$task_debug"
mkdir -p "$task_out/verification"
"$task_debug/Contents/MacOS/reviewNfcGoMac" --verify-desktop "$task_out/verification" > "$task_out/mac-run.log" 2>&1 &
task_process=$!
for task_attempt in $(seq 1 90); do
  if [ -f "$task_out/verification/verification.json" ]; then break; fi
  if ! kill -0 "$task_process" 2>/dev/null; then break; fi
  sleep 2
done
if [ ! -f "$task_out/verification/verification.json" ]; then
  tail -n 100 "$task_out/mac-run.log"
  python3 - "$task_out/mac-crash.log" <<'PY'
import pathlib,sys
reports=sorted(pathlib.Path.home().joinpath('Library/Logs/DiagnosticReports').glob('reviewNfcGo*.ips'), key=lambda p:p.stat().st_mtime)
if reports:
    text=reports[-1].read_text(errors='replace')
    pathlib.Path(sys.argv[1]).write_text(text)
    print(text[-20000:])
PY
fi
python3 - "$task_out/verification/verification.json" <<'PY'
import json,pathlib,sys
p=pathlib.Path(sys.argv[1]);assert p.exists(),'La app no terminó la verificación nativa'
v=json.loads(p.read_text());print(json.dumps(v,ensure_ascii=False));assert v['passed'],v.get('error')
PY
git -C "$task_root" archive --format=zip --output="$task_out/reviewNfcGo-Mac-2.0-Xcode.zip" HEAD macos ios/reviewNfcGo server
echo 'App universal para macOS 14 preparada y verificada.'
