#!/bin/bash
set -euo pipefail
task_project_dir=$(cd -- "$(dirname -- "$0")/.." && pwd)
task_output_dir=$1
task_bundle_id=com.pablo.resenagoogle.20261004
task_record_id=E686DAE0-73ED-4A82-B1D9-A2062F2EACB4
xcodebuild -project "$task_project_dir/reviewNfcGo.xcodeproj" \
    -scheme reviewNfcGo -configuration Debug -sdk iphonesimulator \
    -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath "$task_output_dir/SimulatorData" \
    CODE_SIGNING_ALLOWED=NO build > "$task_output_dir/simulator-build.log" 2>&1 || {
        tail -n 100 "$task_output_dir/simulator-build.log"
        exit 1
    }

task_runtime=$(xcrun simctl list runtimes -j | python3 -c 'import json,sys; r=[x for x in json.load(sys.stdin)["runtimes"] if x.get("isAvailable") and x["name"].startswith("iOS 26")]; assert r,"No iOS 26 simulator"; print(r[-1]["identifier"])')
task_device_type=$(xcrun simctl list devicetypes -j | python3 -c 'import json,sys; r=[x for x in json.load(sys.stdin)["devicetypes"] if x["name"].startswith("iPhone 17 Pro")]; print(r[0]["identifier"] if r else "com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro")')
task_device=$(xcrun simctl create reviewNfcGo-validation "$task_device_type" "$task_runtime")
trap 'xcrun simctl shutdown "$task_device" >/dev/null 2>&1 || true; xcrun simctl delete "$task_device" >/dev/null 2>&1 || true' EXIT
xcrun simctl boot "$task_device"
xcrun simctl bootstatus "$task_device" -b
xcrun simctl install "$task_device" "$task_output_dir/SimulatorData/Build/Products/Debug-iphonesimulator/reviewNfcGo.app"
task_container=$(xcrun simctl get_app_container "$task_device" "$task_bundle_id" data)

# Seed the documented local storage format, so a cold deep link opens a real portal.
python3 - "$task_container" "$task_bundle_id" "$task_record_id" <<'PY'
import sys,json,plistlib,datetime,pathlib
container,bundle,record_id=sys.argv[1:]
now=(datetime.datetime.now(datetime.timezone.utc)-datetime.datetime(2001,1,1,tzinfo=datetime.timezone.utc)).total_seconds()
profile={'name':'Prueba iOS','email':'validation@example.invalid'}
record={'id':record_id,'place':{'id':'validation-place','name':'Negocio de prueba','address':'Calle Mayor, Madrid','latitude':40.4168,'longitude':-3.7038},'createdAt':now,'earnings':25,'notes':'Portal abierto desde Live Activity o recordatorio','status':'pending','reminderDate':now+21600,'notificationDate':now+18000}
prefs={'resenago.currentUser':json.dumps(profile).encode(),'resenago.records.validation@example.invalid':json.dumps([record]).encode()}
path=pathlib.Path(container)/'Library/Preferences'/f'{bundle}.plist'
path.parent.mkdir(parents=True,exist_ok=True)
path.write_bytes(plistlib.dumps(prefs))
PY
xcrun simctl status_bar "$task_device" override --time '9:41' --dataNetwork wifi --wifiMode active --wifiBars 3 --batteryState charged --batteryLevel 100
xcrun simctl ui "$task_device" appearance light
xcrun simctl openurl "$task_device" "reviewnfcgo://business/$task_record_id"
sleep 6
xcrun simctl io "$task_device" screenshot "$task_output_dir/portal-light.png"
xcrun simctl ui "$task_device" appearance dark
sleep 2
xcrun simctl io "$task_device" screenshot "$task_output_dir/portal-dark.png"
xcrun simctl spawn "$task_device" log show --last 2m --style compact --predicate 'process == "reviewNfcGo"' > "$task_output_dir/simulator-runtime.log"

# Reopen the same business with the app already running, then test cold launch again.
xcrun simctl openurl "$task_device" "reviewnfcgo://business/$task_record_id"
xcrun simctl terminate "$task_device" "$task_bundle_id"
xcrun simctl openurl "$task_device" "reviewnfcgo://business/$task_record_id"
sleep 3
xcrun simctl io "$task_device" screenshot "$task_output_dir/portal-cold-launch.png"
echo 'Simulador: apertura en frio y en caliente, capturas clara/oscura guardadas.'
