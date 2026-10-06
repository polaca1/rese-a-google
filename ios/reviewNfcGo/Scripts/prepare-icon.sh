#!/bin/bash
set -euo pipefail
task_project_dir=$(cd -- "$(dirname -- "$0")/.." && pwd)
task_output_dir=$1
task_icon="$task_project_dir/reviewNfcGo/AppIcon.icon"
task_brand="$task_project_dir/reviewNfcGo/Assets.xcassets/BrandMark.imageset"
task_ictool=$(xcrun --find ictool 2>/dev/null || true)
if [ ! -x "$task_ictool" ]; then
    task_ictool="$(dirname "$(xcode-select -p)")/Applications/Icon Composer.app/Contents/Executables/ictool"
fi
if [ ! -x "$task_ictool" ]; then
    task_ictool='/Applications/Icon Composer.app/Contents/Executables/ictool'
fi
test -x "$task_ictool"
"$task_ictool" --help > "$task_output_dir/icon-tool-help.log" 2>&1 || true

export_icon() {
    local task_appearance=$1 task_legacy_appearance=$2 task_file=$3
    if grep -q -- '--export-image' "$task_output_dir/icon-tool-help.log"; then
        "$task_ictool" "$task_icon" --export-image --output-file "$task_file" \
            --platform iOS --rendition "$task_appearance" --width 1024 --height 1024 --scale 1
    else
        "$task_ictool" "$task_icon" --export-preview iOS "$task_legacy_appearance" 1024 1024 1 "$task_file"
    fi
    test -s "$task_file"
}

export_icon Default Light "$task_output_dir/icon-native-light.png"
export_icon Dark Dark "$task_output_dir/icon-native-dark.png"
# In-app branding uses a native rendering of the same layered icon.
cp "$task_output_dir/icon-native-light.png" "$task_brand/BrandMark.png"
cp "$task_output_dir/icon-native-dark.png" "$task_brand/BrandMark-Dark.png"
echo 'Icon Composer: apariencias clara y oscura renderizadas con efectos nativos.'
