#!/bin/bash
set -euo pipefail
task_watch_root=$(cd -- "$(dirname -- "$0")/.." && pwd)
task_repo=$(cd -- "$task_watch_root/.." && pwd)
mkdir -p "$1"
task_output=$(cd -- "$1" && pwd)
xcrun swiftc -parse-as-library -swift-version 5 "$task_repo/ios/reviewNfcGo/reviewNfcGo/WatchCompanionModels.swift" "$task_watch_root/Tests/WatchCompanionTests.swift" -o "$task_output/watch-model-tests"
"$task_output/watch-model-tests"
xcodebuild -project "$task_watch_root/reviewNfcGoWatch.xcodeproj" -scheme reviewNfcGoWatch -configuration Release -sdk watchos -destination 'generic/platform=watchOS' -derivedDataPath "$task_output/Release" CODE_SIGNING_ALLOWED=NO build > "$task_output/watch-build.log" 2>&1 || { tail -n 80 "$task_output/watch-build.log"; exit 1; }
task_app="$task_output/Release/Build/Products/Release-watchos/reviewNfcGoWatch.app"
python3 - "$task_app" <<'PY'
import pathlib,plistlib,sys,subprocess
p=pathlib.Path(sys.argv[1]);i=plistlib.loads((p/'Info.plist').read_bytes())
assert i['CFBundleIdentifier']=='com.pablo.resenagoogle.20261004.watch' and i['WKCompanionAppBundleIdentifier']=='com.pablo.resenagoogle.20261004'
assert i['CFBundleShortVersionString']=='7.3.0' and i['CFBundleVersion']=='39' and i['WKApplication']
assert b'--verification-' not in (p/i['CFBundleExecutable']).read_bytes()
assert 'arm64_32' in subprocess.check_output(['xcrun','lipo','-archs',str(p/i['CFBundleExecutable'])],text=True)
assert tuple(map(int,i['MinimumOSVersion'].split('.'))) <= (10,6,2)
PY
(cd "$(dirname -- "$task_app")" && /usr/bin/zip -qry "$task_output/reviewNfcGo-Watch-7.3.0-build39.zip" reviewNfcGoWatch.app)
xcodebuild -project "$task_watch_root/reviewNfcGoWatch.xcodeproj" -scheme reviewNfcGoWatch -configuration Debug -sdk watchsimulator -destination 'generic/platform=watchOS Simulator' -derivedDataPath "$task_output/Simulator" ARCHS="$(uname -m)" ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO build > "$task_output/watch-simulator-build.log" 2>&1 || { tail -n 80 "$task_output/watch-simulator-build.log"; exit 1; }
task_sim_app="$task_output/Simulator/Build/Products/Debug-watchsimulator/reviewNfcGoWatch.app"
codesign --force --sign - "$task_sim_app"
task_runtime=$(xcrun simctl list runtimes -j | python3 -c 'import json,sys; r=[x for x in json.load(sys.stdin)["runtimes"] if x.get("isAvailable") and x["name"].startswith("watchOS 26")]; assert r; print(r[-1]["identifier"])')
task_type=$(xcrun simctl list devicetypes -j | python3 -c 'import json,sys; r=[x for x in json.load(sys.stdin)["devicetypes"] if x["name"].startswith("Apple Watch Series 11")]; assert r; print(r[0]["identifier"])')
task_device=$(xcrun simctl create reviewNfcGo-companion-test "$task_type" "$task_runtime")
trap 'xcrun simctl shutdown "$task_device" >/dev/null 2>&1 || true; xcrun simctl delete "$task_device" >/dev/null 2>&1 || true' EXIT
xcrun simctl boot "$task_device"
xcrun simctl bootstatus "$task_device" -b
xcrun simctl install "$task_device" "$task_sim_app"
task_bundle=com.pablo.resenagoogle.20261004.watch
task_container=$(xcrun simctl get_app_container "$task_device" "$task_bundle" data)
xcrun swiftc -parse-as-library -swift-version 5 "$task_watch_root/Tests/WatchScreenshotTests.swift" -o "$task_output/watch-screen-check"
for task_screen in visit businesses money; do
    xcrun simctl terminate "$task_device" "$task_bundle" >/dev/null 2>&1 || true
    xcrun simctl launch "$task_device" "$task_bundle" --verification-watch "--verification-watch-$task_screen"
    for task_attempt in $(seq 1 30); do
        if [ -f "$task_container/Documents/watch-verification.json" ]; then break; fi
        sleep 1
    done
    cp "$task_container/Documents/watch-verification.json" "$task_output/watch-verification.log"
    python3 - "$task_output/watch-verification.log" <<'PY'
import json,sys
r=json.load(open(sys.argv[1]));assert r['passed'] and r['snapshotExact'] and r['badDataPreservesLast'] and r['logoutClearsData'],r
print(r)
PY
    sleep 3
    xcrun simctl io "$task_device" screenshot "$task_output/watch-$task_screen.png"
    "$task_output/watch-screen-check" "$task_output/watch-$task_screen.png" "$task_screen" | tee "$task_output/watch-screen-$task_screen.log"
done
