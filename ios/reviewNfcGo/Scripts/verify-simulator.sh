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
    ARCHS="$(uname -m)" ONLY_ACTIVE_ARCH=YES \
    CODE_SIGNING_ALLOWED=NO build > "$task_output_dir/simulator-build.log" 2>&1 || {
        tail -n 100 "$task_output_dir/simulator-build.log"
        exit 1
    }

task_sim_app="$task_output_dir/SimulatorData/Build/Products/Debug-iphonesimulator/reviewNfcGo.app"
codesign --force --sign - --entitlements "$task_project_dir/reviewNfcGoLiveActivity/reviewNfcGoLiveActivity.entitlements" "$task_sim_app/PlugIns/reviewNfcGoLiveActivity.appex"
codesign --force --sign - --entitlements "$task_project_dir/reviewNfcGo/reviewNfcGo.entitlements" "$task_sim_app"

task_runtime=$(xcrun simctl list runtimes -j | python3 -c 'import json,sys; r=[x for x in json.load(sys.stdin)["runtimes"] if x.get("isAvailable") and x["name"].startswith("iOS 26")]; assert r,"No iOS 26 simulator"; print(r[-1]["identifier"])')
task_device_type=$(xcrun simctl list devicetypes -j | python3 -c 'import json,sys; r=[x for x in json.load(sys.stdin)["devicetypes"] if x["name"].startswith("iPhone 17 Pro")]; print(r[0]["identifier"] if r else "com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro")')
task_device=$(xcrun simctl create reviewNfcGo-validation "$task_device_type" "$task_runtime")
trap 'xcrun simctl shutdown "$task_device" >/dev/null 2>&1 || true; xcrun simctl delete "$task_device" >/dev/null 2>&1 || true' EXIT
xcrun simctl boot "$task_device"
xcrun simctl bootstatus "$task_device" -b
xcrun simctl install "$task_device" "$task_output_dir/SimulatorData/Build/Products/Debug-iphonesimulator/reviewNfcGo.app"
xcrun simctl privacy "$task_device" grant location "$task_bundle_id"
xcrun simctl location "$task_device" set 40.4168,-3.7038
task_container=$(xcrun simctl get_app_container "$task_device" "$task_bundle_id" data)

# Seed the documented local storage format, so a cold deep link opens a real portal.
python3 - "$task_container" "$task_bundle_id" "$task_record_id" <<'PY'
import sys,json,plistlib,datetime,pathlib
container,bundle,record_id=sys.argv[1:]
now=(datetime.datetime.now(datetime.timezone.utc)-datetime.datetime(2001,1,1,tzinfo=datetime.timezone.utc)).total_seconds()
profile={'name':'Prueba iOS','email':'validation@example.invalid'}
record={'id':record_id,'place':{'id':'validation-place','name':'Negocio de prueba','address':'Calle Mayor, Madrid','latitude':40.4168,'longitude':-3.7038},'createdAt':now,'earnings':100,'cardsSold':2,'notes':'Portal abierto desde Live Activity o recordatorio','status':'Completado'}
events=[{'id':'57D4CD2B-C98C-4244-B628-F8041E94EAD8','status':'scheduled','date':now-7200},{'id':'B8F0C42D-75A1-4D8F-B80D-AFF1F0DEBB9B','status':'delivered','date':now-3600},{'id':'73243651-D941-48A2-9034-26E6E54A27AD','status':'opened','date':now-3500}]
entry={'id':'839CA204-B64D-4EA8-90DD-B1E1DB884661','systemID':'validation-reminder','fingerprint':'validation-reminder','kind':'reminder','recordID':record_id,'businessName':record['place']['name'],'title':'Volver al negocio de prueba','body':'Visita programada en Calle Mayor','scheduledDate':now-3600,'createdAt':now-7200,'events':events}
activity=dict(entry,id='5A6E0F17-9962-4E32-A149-E26A1A4668EF',systemID='validation-activity',fingerprint='validation-activity',kind='liveActivity',title='Cuenta atrás para el negocio de prueba',events=events+[{'id':'4787CF44-9E03-45D0-ADEB-3F4B77D99EB4','status':'finished','date':now-1800}])
prefs={'resenago.currentUser':json.dumps(profile).encode(),'resenago.records.validation@example.invalid':json.dumps([record]).encode(),'resenago.alertHistory.validation@example.invalid':json.dumps({'entries':[entry,activity]}).encode()}
path=pathlib.Path(container)/'Library/Preferences'/f'{bundle}.plist'
path.parent.mkdir(parents=True,exist_ok=True)
path.write_bytes(plistlib.dumps(prefs))
PY
xcrun swiftc -parse-as-library -swift-version 5 \
    "$task_project_dir/reviewNfcGo/VisitRecord.swift" \
    "$task_project_dir/reviewNfcGo/AlertHistory.swift" \
    "$task_project_dir/Scripts/VerifyFixture.swift" \
    -o "$task_output_dir/fixture-validation"
"$task_output_dir/fixture-validation" "$task_container/Library/Preferences/$task_bundle_id.plist" "$task_record_id"
xcrun simctl status_bar "$task_device" override --time '9:41' --dataNetwork wifi --wifiMode active --wifiBars 3 --batteryState charged --batteryLevel 100
xcrun simctl ui "$task_device" appearance light
xcrun simctl launch "$task_device" "$task_bundle_id" --verification-portal "reviewnfcgo://business/$task_record_id"
sleep 6
xcrun simctl io "$task_device" screenshot "$task_output_dir/portal-light.png"
xcrun simctl ui "$task_device" appearance dark
sleep 2
xcrun simctl io "$task_device" screenshot "$task_output_dir/portal-dark.png"
xcrun simctl spawn "$task_device" log show --last 2m --style compact --predicate 'process == "reviewNfcGo"' > "$task_output_dir/simulator-runtime.log"

# Launch again after terminating to verify the saved route with a cold process.
xcrun simctl terminate "$task_device" "$task_bundle_id"
xcrun simctl launch "$task_device" "$task_bundle_id" --verification-portal "reviewnfcgo://business/$task_record_id"
sleep 3
xcrun simctl io "$task_device" screenshot "$task_output_dir/portal-cold-launch.png"
echo 'Simulador: portal desde arranque en frio, capturas clara/oscura guardadas.'

xcrun simctl terminate "$task_device" "$task_bundle_id"
xcrun simctl ui "$task_device" appearance light
xcrun simctl launch "$task_device" "$task_bundle_id" --verification-portal "reviewnfcgo://business/$task_record_id" --verification-editor
sleep 3
xcrun simctl io "$task_device" screenshot "$task_output_dir/sales-editor-light.png"
xcrun simctl ui "$task_device" appearance dark
sleep 2
xcrun simctl io "$task_device" screenshot "$task_output_dir/sales-editor-dark.png"
# Mutate the editor only in a separate process, after capturing its untouched UI.
xcrun simctl terminate "$task_device" "$task_bundle_id"
xcrun simctl launch "$task_device" "$task_bundle_id" --verification-portal "reviewnfcgo://business/$task_record_id" --verification-editor --verification-unit-calculation
for task_attempt in $(seq 1 20); do
    if [ -f "$task_container/Documents/unit-earnings-verification.json" ]; then break; fi
    sleep 1
done
cp "$task_container/Documents/unit-earnings-verification.json" "$task_output_dir/unit-earnings-verification.log"
python3 - "$task_output_dir/unit-earnings-verification.log" <<'PYCHECK'
import json,sys
result=json.load(open(sys.argv[1]));print(result);assert result['passed'],result
PYCHECK
xcrun simctl terminate "$task_device" "$task_bundle_id"
xcrun simctl launch "$task_device" "$task_bundle_id" --verification-profile
sleep 3
xcrun simctl io "$task_device" screenshot "$task_output_dir/profile-credit.png"

xcrun simctl terminate "$task_device" "$task_bundle_id"
xcrun simctl ui "$task_device" appearance light
xcrun simctl launch "$task_device" "$task_bundle_id" --verification-history
sleep 3
xcrun simctl io "$task_device" screenshot "$task_output_dir/history-light.png"
xcrun simctl ui "$task_device" appearance dark
sleep 2
xcrun simctl io "$task_device" screenshot "$task_output_dir/history-dark.png"

# Exercise actual MKMapView camera updates; assert visible centers and zoom, not just pin coordinates.
xcrun simctl terminate "$task_device" "$task_bundle_id"
xcrun simctl ui "$task_device" appearance light
xcrun simctl launch "$task_device" "$task_bundle_id" --verification-map
for task_attempt in $(seq 1 90); do
    if [ -f "$task_container/Documents/map-camera-verification.json" ]; then break; fi
    sleep 1
done
cp "$task_container/Documents/map-camera-verification.json" "$task_output_dir/map-camera-verification.log"
python3 - "$task_output_dir/map-camera-verification.log" <<'PYCHECK'
import json,sys
result=json.load(open(sys.argv[1]))
print(json.dumps(result,ensure_ascii=False,indent=2))
assert result['passed'] and len(result['checks']) == 10,result
PYCHECK
xcrun simctl io "$task_device" screenshot "$task_output_dir/map-user-focused.png"

# Real compact date controls: measure the label/control vertical centers, and capture the form.
xcrun simctl terminate "$task_device" "$task_bundle_id"
xcrun simctl ui "$task_device" appearance light
xcrun simctl launch "$task_device" "$task_bundle_id" --verification-dates
for task_attempt in $(seq 1 25); do
    if [ -f "$task_container/Documents/date-layout-verification.json" ]; then break; fi
    sleep 1
done
cp "$task_container/Documents/date-layout-verification.json" "$task_output_dir/date-layout-verification.log"
python3 - "$task_output_dir/date-layout-verification.log" <<'PYCHECK'
import json,sys
result=json.load(open(sys.argv[1]));print(result)
assert result['passed'] and result['rows']==2,result
PYCHECK
xcrun simctl io "$task_device" screenshot "$task_output_dir/reminder-dates-light.png"

# Call the real form save handler, reload persisted data and verify edge cases.
xcrun simctl terminate "$task_device" "$task_bundle_id"
xcrun simctl launch "$task_device" "$task_bundle_id" --verification-reminder-save
for task_attempt in $(seq 1 25); do
    if [ -f "$task_container/Documents/reminder-save-verification.json" ]; then break; fi
    sleep 1
done
cp "$task_container/Documents/reminder-save-verification.json" "$task_output_dir/reminder-save-verification.log"
python3 - "$task_output_dir/reminder-save-verification.log" <<'PYCHECK'
import json,sys
result=json.load(open(sys.argv[1]));print(json.dumps(result,ensure_ascii=False,indent=2))
assert result['passed'] and len(result['checks'])==7,result
PYCHECK

# Use the same widget views/providers as the extension, with real MapKit snapshots and App Group data.
xcrun simctl terminate "$task_device" "$task_bundle_id"
xcrun simctl launch "$task_device" "$task_bundle_id" --verification-widgets
for task_attempt in $(seq 1 90); do
    if [ -f "$task_container/Documents/widgets-verification.json" ]; then break; fi
    sleep 1
done
cp "$task_container/Documents/widgets-verification.json" "$task_output_dir/widgets-verification.log"
python3 - "$task_output_dir/widgets-verification.log" <<'PYCHECK'
import json,sys
result=json.load(open(sys.argv[1]));print(result)
assert result['passed'] and len(result['checks'])==4,result
PYCHECK
cp "$task_container"/Documents/widget-*.png "$task_output_dir/"

xcrun simctl terminate "$task_device" "$task_bundle_id"
xcrun simctl launch "$task_device" "$task_bundle_id" --verification-portal reviewnfcgo://widgets/earnings
sleep 3
xcrun simctl io "$task_device" screenshot "$task_output_dir/widget-earnings-deeplink.png"

# Major update: actual AppStore persistence/finance, photos and search selection.
xcrun simctl terminate "$task_device" "$task_bundle_id"
xcrun simctl ui "$task_device" appearance light
xcrun simctl launch "$task_device" "$task_bundle_id" --verification-money
for task_attempt in $(seq 1 35); do
    if [ -f "$task_container/Documents/major-update-verification.json" ]; then break; fi
    sleep 1
done
cp "$task_container/Documents/major-update-verification.json" "$task_output_dir/major-update-verification.log"
python3 - "$task_output_dir/major-update-verification.log" <<'PYCHECK'
import json,sys
result=json.load(open(sys.argv[1]));print(json.dumps(result,ensure_ascii=False,indent=2))
assert result['passed'] and len(result['checks'])>=18,result
PYCHECK
cp "$task_container/Documents/widget-money-real-light.png" "$task_output_dir/widget-money-real-light.png"
cp "$task_container/Documents/widget-money-real-dark.png" "$task_output_dir/widget-money-real-dark.png"
sleep 2
xcrun simctl io "$task_device" screenshot "$task_output_dir/money-light.png"
xcrun simctl ui "$task_device" appearance dark
sleep 2
xcrun simctl io "$task_device" screenshot "$task_output_dir/money-dark.png"
xcrun simctl terminate "$task_device" "$task_bundle_id"
xcrun simctl ui "$task_device" appearance light
xcrun simctl launch "$task_device" "$task_bundle_id" --verification-inventory
sleep 3
xcrun simctl io "$task_device" screenshot "$task_output_dir/inventory-light.png"
xcrun simctl terminate "$task_device" "$task_bundle_id"
xcrun simctl launch "$task_device" "$task_bundle_id" --verification-expense
sleep 3
xcrun simctl io "$task_device" screenshot "$task_output_dir/expense-light.png"
xcrun simctl terminate "$task_device" "$task_bundle_id"
xcrun simctl launch "$task_device" "$task_bundle_id" --verification-search
sleep 3
xcrun simctl io "$task_device" screenshot "$task_output_dir/search-suggestions.png"
xcrun simctl terminate "$task_device" "$task_bundle_id"
xcrun simctl launch "$task_device" "$task_bundle_id" --verification-profile
sleep 3
xcrun simctl io "$task_device" screenshot "$task_output_dir/profile-photo.png"
echo 'Major update: dinero, inventario, selección de búsqueda y fotos verificados en simulador.'

# Inspect the actual native scroll edge on each screen without a navigation panel.
for task_blur_screen in home auth; do
    xcrun simctl terminate "$task_device" "$task_bundle_id"
    xcrun simctl ui "$task_device" appearance light
    xcrun simctl launch "$task_device" "$task_bundle_id" "--verification-blur-$task_blur_screen"
    for task_attempt in $(seq 1 20); do
        if [ -f "$task_container/Documents/blur-$task_blur_screen-verification.json" ]; then break; fi
        sleep 1
    done
    cp "$task_container/Documents/blur-$task_blur_screen-verification.json" "$task_output_dir/blur-$task_blur_screen-verification.log"
    python3 - "$task_output_dir/blur-$task_blur_screen-verification.log" <<'PYCHECK'
import json,sys
result=json.load(open(sys.argv[1]));print(result)
assert result['passed'] and result['nativeSoftEffect'] and not result['effectHidden'],result
if result['screen']=='home':
    assert result['scrollOffset']>0 and result['headerInScrollContent'] and result['headerScrollsWithContent'],result
PYCHECK
    xcrun simctl io "$task_device" screenshot "$task_output_dir/blur-$task_blur_screen-light.png"
    xcrun simctl ui "$task_device" appearance dark
    sleep 2
    xcrun simctl io "$task_device" screenshot "$task_output_dir/blur-$task_blur_screen-dark.png"
done
echo 'Blur variable nativo: Inicio y acceso verificados.'

# Actual Keychain migration and authentication, using an isolated account namespace.
xcrun simctl terminate "$task_device" "$task_bundle_id"
xcrun simctl launch "$task_device" "$task_bundle_id" --verification-production
for task_attempt in $(seq 1 25); do
    if [ -f "$task_container/Documents/production-verification.json" ]; then break; fi
    sleep 1
done
cp "$task_container/Documents/production-verification.json" "$task_output_dir/production-verification.log"
python3 - "$task_output_dir/production-verification.log" <<'PYCHECK'
import json,sys
result=json.load(open(sys.argv[1]));print(json.dumps(result,ensure_ascii=False,indent=2))
assert result['passed'] and len(result['checks'])>=12,result
PYCHECK

# Capture the greeting at the top of the page, before scrolling it away.
xcrun simctl terminate "$task_device" "$task_bundle_id"
xcrun simctl ui "$task_device" appearance light
xcrun simctl launch "$task_device" "$task_bundle_id" --verification-home-top
sleep 3
xcrun simctl io "$task_device" screenshot "$task_output_dir/home-top-light.png"
xcrun simctl ui "$task_device" appearance dark
sleep 2
xcrun simctl io "$task_device" screenshot "$task_output_dir/home-top-dark.png"

# Verify backups, undo accounting and persistence using real app storage.
xcrun simctl terminate "$task_device" "$task_bundle_id" >/dev/null 2>&1 || true
xcrun simctl launch "$task_device" "$task_bundle_id" --verification-v5
for task_attempt in $(seq 1 25); do
    if [ -f "$task_container/Documents/version5-verification.json" ]; then break; fi
    sleep 1
done
cp "$task_container/Documents/version5-verification.json" "$task_output_dir/version5-verification.log"
python3 - "$task_output_dir/version5-verification.log" <<'PYV5'
import json,sys
result=json.load(open(sys.argv[1]));print(result);assert result['passed'] and len(result['checks'])>=12,result
PYV5
for task_screen in route backup profit; do
    xcrun simctl terminate "$task_device" "$task_bundle_id"
    xcrun simctl launch "$task_device" "$task_bundle_id" "--verification-v5-$task_screen"
    sleep 3
    xcrun simctl io "$task_device" screenshot "$task_output_dir/v5-$task_screen.png"
done

# Exercise every new shared screen in a native iPhone host.
for task_screen in sale clients goals profit history; do
    xcrun simctl terminate "$task_device" "$task_bundle_id"
    xcrun simctl launch "$task_device" "$task_bundle_id" "--verification-suite-$task_screen"
    sleep 3
    xcrun simctl io "$task_device" screenshot "$task_output_dir/suite-$task_screen.png"
done
