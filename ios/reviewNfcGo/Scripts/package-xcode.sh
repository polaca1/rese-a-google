#!/bin/bash
set -euo pipefail
task_project_dir=$(cd -- "$(dirname -- "$0")/.." && pwd)
task_project_root=$(cd -- "$task_project_dir/../.." && pwd)
task_output_dir=$1
task_package_dir=$(mktemp -d)
trap 'rm -rf "$task_package_dir"' EXIT
# Package the complete layout so both projects retain shared files and release checks.
git -C "$task_project_root" archive --format=tar --prefix=reviewNfcGo/ HEAD | tar -xf - -C "$task_package_dir"
python3 - "$task_package_dir/reviewNfcGo" <<'PYDATA'
import pathlib,plistlib,re,sys
root=pathlib.Path(sys.argv[1])
for path in [root/'ios/reviewNfcGo/reviewNfcGo/Info.plist',root/'macos/reviewNfcGo/Info.plist']:
    value=plistlib.loads(path.read_bytes())
    value['GooglePlacesAPIKey']='';value['GooglePlacesFallbackAPIKey']=''
    path.write_bytes(plistlib.dumps(value))
config=root/'config.js'
if config.exists():config.write_text(re.sub(r'AIza[0-9A-Za-z_-]+','',config.read_text()))
PYDATA
(cd "$task_package_dir" && /usr/bin/zip -qry "$task_output_dir/reviewNfcGo-7.2.0-Xcode.zip" reviewNfcGo)
echo 'Proyecto completo de Xcode preparado sin claves de Google Places.'
