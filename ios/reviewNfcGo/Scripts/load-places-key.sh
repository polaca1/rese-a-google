# Sourced by both build scripts. Existing legacy configuration remains a migration
# fallback while GitHub credentials lack permission to create repository secrets.
if [ -z "${GOOGLE_PLACES_API_KEY:-}" ]; then
  GOOGLE_PLACES_API_KEY=$(python3 - "$task_project_root/config.js" <<'PY'
import pathlib,re,sys
keys=re.findall(r'AIza[0-9A-Za-z_-]+',pathlib.Path(sys.argv[1]).read_text())
assert keys, 'Falta configurar la clave principal de Google Places'
print(keys[0])
PY
)
fi
if [ -n "${GITHUB_ACTIONS:-}" ]; then
  echo "::add-mask::$GOOGLE_PLACES_API_KEY"
fi
export GOOGLE_PLACES_API_KEY
