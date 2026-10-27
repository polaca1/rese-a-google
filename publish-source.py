"""Generate feeds only from a downloaded, verified release manifest and IPA."""
import argparse, hashlib, io, json, pathlib, plistlib, urllib.request, zipfile
parser=argparse.ArgumentParser()
parser.add_argument("manifest", type=pathlib.Path)
parser.add_argument("--date", required=True)
args=parser.parse_args()
manifest=json.loads(args.manifest.read_text())
version=manifest["version"]; build=manifest["build"]
assert version == "0.7.0" and build.isdigit()
assert manifest["nativeWatchStoreIncluded"] is False
assert manifest["createsNewAppIDs"] is False
assert manifest["reusesExistingSideStoreIdentity"] is True
name=f"SideStore-Watch-Beta-{version}-build{build}.ipa"
url=f"https://github.com/polaca1/rese-a-google/releases/download/sidestore-watch-beta-{version}-build{build}/{name}"
with urllib.request.urlopen(url, timeout=120) as response: data=response.read()
assert len(data)==manifest["size"]
assert hashlib.sha256(data).hexdigest()==manifest["sha256"]
with zipfile.ZipFile(io.BytesIO(data)) as archive:
    assert archive.testzip() is None
    info=plistlib.loads(archive.read("Payload/SideStore.app/Info.plist"))
    assert info["CFBundleIdentifier"]=="com.SideStore.SideStore"
    assert info["CFBundleShortVersionString"]==version and info["CFBundleVersion"]==build
    assert not any("/Watch/" in entry for entry in archive.namelist())
base="https://raw.githubusercontent.com/polaca1/rese-a-google/refs/heads/sidestore-watch-source/"
details="muestra el paso exacto y el código numérico cuando Apple rechaza el perfil" if int(build)>=707 else "comprueba la conexión, el reloj enlazado y la solicitud del perfil"
notes=(f"Beta {version} ({build}). Diagnóstico del Watch en iPhone: {details}. "
       "Conserva Apple ID, fuentes, instalación, refirma y atajos de datos móviles de SideStore. "
       "Todavía NO instala ni renueva apps del Watch. Actualiza sobre SideStore, con la misma cuenta Apple y sin borrar la app. No crea App IDs.")
release={"version":version,"buildVersion":build,"date":args.date,"localizedDescription":notes,"downloadURL":url,"size":len(data),"minOSVersion":info["MinimumOSVersion"]}
app={"name":"SideStore Watch · Beta","bundleIdentifier":"com.SideStore.SideStore","developerName":"Variante personal · basada en SideStore Team",
     "subtitle":"Diagnóstico Watch · iPhone","localizedDescription":notes,"iconURL":base+"icon.png","tintColor":"9B20EB",
     "version":version,"buildVersion":build,"versionDate":args.date,"versionDescription":notes,"downloadURL":url,"size":len(data),"minOSVersion":info["MinimumOSVersion"],
     "versions":[release],"appPermissions":{"entitlements":["com.apple.security.application-groups"],"privacy":{k:v for k,v in info.items() if k.endswith("UsageDescription")}}}
root=pathlib.Path(__file__).resolve().parent
for feed in ["source.json","source-compatible.json"]:
    source={"name":"SideStore Watch · Beta","identifier":"com.polaca1.sidestorewatch.beta","sourceURL":base+feed,"subtitle":"Beta personal para pruebas del Watch","description":"Fuente independiente. Actualmente contiene diagnóstico de watchOS en iPhone; la tienda autónoma del Watch sigue en desarrollo.","website":"https://github.com/polaca1/rese-a-google/tree/beta/sidestore-watch","iconURL":base+"icon.png","tintColor":"9B20EB","apps":[app],"news":[]}
    (root/feed).write_text(json.dumps(source,ensure_ascii=False,indent=2)+"\n")
(root/"SOURCE-PROVENANCE.json").write_text(json.dumps({"manifest":manifest,"releaseURL":url,"checks":["public-download","sha256","size","zip-crc","bundle-id","version","build","no-watch-bundle"]},indent=2)+"\n")
print(f"Verified source: {version} ({build}), {len(data)} bytes")
