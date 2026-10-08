#!/bin/bash
set -euo pipefail
task_source="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
task_output="$(realpath -m "${1:?Indica la carpeta de salida}")"
task_package="$task_output/reviewNfcGo-Servidor-Linux"
mkdir -p "$task_package"
cp "$task_source/app.py" "$task_source/requirements.txt" "$task_package/"
cp "$task_source/windows/runtime.py" "$task_package/runtime.py"
cp "$task_source/linux/Instalar.sh" "$task_source/linux/action.py" "$task_source/linux/Configurar.py" "$task_source/linux/reviewnfcgo-cuentas.service" "$task_package/"
cp "$task_source/linux/GUIA-RKM-DESDE-MAC.md" "$task_package/LEEME.md"
chmod 0755 "$task_package/Instalar.sh"
cd "$task_output"
zip -qr reviewNfcGo-Servidor-Linux.zip reviewNfcGo-Servidor-Linux
sha256sum reviewNfcGo-Servidor-Linux.zip > SHA256SUMS.txt
