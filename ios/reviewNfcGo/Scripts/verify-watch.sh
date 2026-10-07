#!/bin/bash
set -euo pipefail
task_project_dir=$(cd -- "$(dirname -- "$0")/.." && pwd)
task_output_dir=$1
xcodebuild -project "$task_project_dir/reviewNfcGo.xcodeproj" \
    -scheme reviewNfcGoWatch -configuration Debug -sdk watchsimulator \
    -destination 'generic/platform=watchOS Simulator' \
    -derivedDataPath "$task_output_dir/WatchSimulatorData" \
    ARCHS="$(uname -m)" ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO build \
    > "$task_output_dir/watch-simulator-build.log" 2>&1 || { tail -n 100 "$task_output_dir/watch-simulator-build.log"; exit 1; }
task_app="$task_output_dir/WatchSimulatorData/Build/Products/Debug-watchsimulator/reviewNfcGoWatch.app"
codesign --force --sign - --entitlements "$task_project_dir/reviewNfcGoWatchWidgets/WatchWidgets.entitlements" "$task_app/PlugIns/reviewNfcGoWatchWidgets.appex"
codesign --force --sign - --entitlements "$task_project_dir/reviewNfcGoWatch/Watch.entitlements" "$task_app"
task_runtime=$(xcrun simctl list runtimes -j | python3 -c 'import json,sys; r=[x for x in json.load(sys.stdin)["runtimes"] if x.get("isAvailable") and x["name"].startswith("watchOS 26")]; assert r,"No watchOS 26 simulator"; print(r[-1]["identifier"])')
task_type=$(xcrun simctl list devicetypes -j | python3 -c 'import json,sys; r=[x for x in json.load(sys.stdin)["devicetypes"] if x["name"].startswith("Apple Watch Series 11")]; assert r; print(r[0]["identifier"])')
task_watch=$(xcrun simctl create reviewNfcGo-Watch-validation "$task_type" "$task_runtime")
trap 'xcrun simctl shutdown "$task_watch" >/dev/null 2>&1 || true; xcrun simctl delete "$task_watch" >/dev/null 2>&1 || true' EXIT
xcrun simctl boot "$task_watch"
xcrun simctl bootstatus "$task_watch" -b
xcrun simctl install "$task_watch" "$task_app"
task_bundle=com.pablo.resenagoogle.20261004.watch
task_container=$(xcrun simctl get_app_container "$task_watch" "$task_bundle" data)
xcrun swiftc -parse-as-library -swift-version 5 "$task_project_dir/Tests/WatchScreenshots.swift" -o "$task_output_dir/watch-ui-check"
for task_screen in next business summary sale; do
    xcrun simctl terminate "$task_watch" "$task_bundle" >/dev/null 2>&1 || true
    if [ "$task_screen" = next ]; then
        xcrun simctl launch "$task_watch" "$task_bundle" --verification-watch
    else
        xcrun simctl launch "$task_watch" "$task_bundle" --verification-watch "--verification-watch-$task_screen"
    fi
    for task_attempt in $(seq 1 20); do
        if [ -f "$task_container/Documents/watch-verification.json" ]; then break; fi
        sleep 1
    done
    sleep 3
    cp "$task_container/Documents/watch-verification.json" "$task_output_dir/watch-verification.log"
    python3 - "$task_output_dir/watch-verification.log" <<'PY'
import json,sys
value=json.load(open(sys.argv[1]));print(value);assert value['passed'] and len(value['checks'])>=9,value
PY
    xcrun simctl io "$task_watch" screenshot "$task_output_dir/watch-$task_screen.png"
    "$task_output_dir/watch-ui-check" "$task_output_dir/watch-$task_screen.png" "$task_screen" | tee "$task_output_dir/watch-ui-$task_screen.log"
    rm "$task_container/Documents/watch-verification.json"
done
xcrun simctl spawn "$task_watch" log show --last 3m --style compact --predicate 'process == "reviewNfcGoWatch"' > "$task_output_dir/watch-runtime.log"
echo 'watchOS: cola offline, confirmaciones, protección de cuenta, datos de complicación y capturas verificados.'
