#!/bin/bash
set -euo pipefail
task_project_dir=$(cd -- "$(dirname -- "$0")/.." && pwd)
task_output_dir=${1:-"$task_project_dir/build"}
mkdir -p "$task_output_dir"
task_output_dir=$(cd -- "$task_output_dir" && pwd)
task_project_root=$(git -C "$task_project_dir" rev-parse --show-toplevel)
source "$task_project_dir/Scripts/load-places-key.sh"

if ! command -v xcodebuild >/dev/null; then
    echo 'Se necesita macOS con Xcode 26 o posterior.' >&2
    exit 1
fi
task_xcode_major=$(xcodebuild -version | awk '/^Xcode / {split($2,v,".");print v[1]}')
if [ "$task_xcode_major" -lt 26 ]; then
    echo 'Liquid Glass nativo requiere compilar con Xcode 26 o posterior.' >&2
    exit 1
fi

# Never print the API key or pass it as a visible xcodebuild argument.
task_info_plist="$task_project_dir/reviewNfcGo/Info.plist"
task_plist_backup=$(mktemp)
cp "$task_info_plist" "$task_plist_backup"
trap 'cp "$task_plist_backup" "$task_info_plist"; rm -f "$task_plist_backup"' EXIT
if [ -n "${GOOGLE_PLACES_API_KEY:-}" ]; then
    /usr/libexec/PlistBuddy -c "Set :GooglePlacesAPIKey $GOOGLE_PLACES_API_KEY" "$task_info_plist"
fi
python3 - "$task_info_plist" <<'PY'
import pathlib,plistlib,os,sys
p=pathlib.Path(sys.argv[1]);v=plistlib.loads(p.read_bytes());v['GooglePlacesFallbackAPIKey']=os.environ.get('GOOGLE_PLACES_FALLBACK_API_KEY','');p.write_bytes(plistlib.dumps(v))
PY

bash "$task_project_dir/Scripts/prepare-icon.sh" "$task_output_dir" > "$task_output_dir/icon-render.log" 2>&1 || {
    cat "$task_output_dir/icon-render.log"
    cat "$task_output_dir/icon-tool-help.log" 2>/dev/null || true
    exit 1
}
sh "$task_project_dir/Tests/run.sh"
xcodebuild -project "$task_project_dir/reviewNfcGo.xcodeproj" \
    -scheme reviewNfcGo -configuration Release -sdk iphoneos \
    -destination 'generic/platform=iOS' \
    -derivedDataPath "$task_output_dir/DerivedData" \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build \
    > "$task_output_dir/xcodebuild.log" 2>&1 || {
        tail -n 100 "$task_output_dir/xcodebuild.log"
        exit 1
    }
task_app="$task_output_dir/DerivedData/Build/Products/Release-iphoneos/reviewNfcGo.app"
test -f "$task_app/reviewNfcGo"
test -f "$task_app/PlugIns/reviewNfcGoLiveActivity.appex/reviewNfcGoLiveActivity"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleURLTypes:0:CFBundleURLSchemes:0' "$task_app/Info.plist")" = 'reviewnfcgo'

# Embed only an ad-hoc entitlement template, so AltStore can discover and provision
# the shared App Group. AltStore replaces this signature with the user's identity.
codesign --force --sign - --entitlements "$task_project_dir/reviewNfcGoLiveActivity/reviewNfcGoLiveActivity.entitlements" "$task_app/PlugIns/reviewNfcGoLiveActivity.appex"
codesign --force --sign - --entitlements "$task_project_dir/reviewNfcGo/reviewNfcGo.entitlements" "$task_app"

# AltStore/SideStore signs the main binary and the embedded widget for the device.
task_package_dir=$(mktemp -d)
mkdir -p "$task_package_dir/Payload"
ditto "$task_app" "$task_package_dir/Payload/reviewNfcGo.app"
task_ipa="$task_output_dir/reviewNfcGo-5.2-AltStore.ipa"
rm -f "$task_ipa"
(cd "$task_package_dir" && /usr/bin/zip -qry "$task_ipa" Payload)
rm -rf "$task_package_dir"
unzip -tq "$task_ipa"
echo "IPA generado: $task_ipa"
