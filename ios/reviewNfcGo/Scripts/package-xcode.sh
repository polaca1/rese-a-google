#!/bin/bash
set -euo pipefail
task_project_dir=$(cd -- "$(dirname -- "$0")/.." && pwd)
task_output_dir=$1
task_package_dir=$(mktemp -d)
trap 'rm -rf "$task_package_dir"' EXIT
mkdir "$task_package_dir/reviewNfcGo"
git -C "$task_project_dir" ls-files -z . | python3 -c '
import sys,pathlib,shutil
source=pathlib.Path(sys.argv[1]);target=pathlib.Path(sys.argv[2])
for name in sys.stdin.buffer.read().decode().split("\0"):
    if not name: continue
    origin=source/name
    if not origin.is_file(): continue
    dest=target/name;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(origin,dest)
' "$task_project_dir" "$task_package_dir/reviewNfcGo"
python3 - "$task_package_dir/reviewNfcGo/reviewNfcGo/Info.plist" <<'PY'
import pathlib,plistlib,sys
path=pathlib.Path(sys.argv[1]);value=plistlib.loads(path.read_bytes());value['GooglePlacesAPIKey']='';path.write_bytes(plistlib.dumps(value))
PY
(cd "$task_package_dir" && /usr/bin/zip -qry "$task_output_dir/reviewNfcGo-5.1.1-Xcode.zip" reviewNfcGo)
echo 'Proyecto de Xcode preparado sin credenciales.'
