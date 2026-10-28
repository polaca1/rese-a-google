"""Adapt the already published Watch bundle to an existing, compatible App ID."""
import hashlib, io, json, pathlib, plistlib, stat, urllib.request, zipfile

SOURCE = "https://github.com/polaca1/rese-a-google/releases/download/reviewnfcgo-7.3.0-build39/reviewNfcGo-Watch-7.3.0-build39.ipa"
SOURCE_SHA256 = "859b6bd9711abe2b315909114a9231e9d15c9d23e51b5c2558698e84f368ded2"
PHONE_ID = "com.pablo.resenagoogle.20261004.DU4R2L3YQF"
WATCH_ID = PHONE_ID + ".liveactivity"
ROOT = "Payload/reviewNfcGoWatch.app/"

def compatible(parent, child):
    return bool(parent) and child != parent and child.startswith(parent + ".") and "*" not in child

assert compatible(PHONE_ID, WATCH_ID)
assert not compatible(PHONE_ID, PHONE_ID)
assert not compatible(PHONE_ID, "com.kdt.livecontainer.DU4R2L3YQF.LiveProcess")
assert not compatible(PHONE_ID, PHONE_ID + "-wrong.watch")

with urllib.request.urlopen(SOURCE, timeout=120) as response:
    data = response.read()
assert len(data) == 451302 and hashlib.sha256(data).hexdigest() == SOURCE_SHA256
out = pathlib.Path("reuse-output")
out.mkdir(exist_ok=True)
ipa = out / "reviewNfcGo-Watch-7.3.0-build39-ReuseID.ipa"
kept_hashes = {}
with zipfile.ZipFile(io.BytesIO(data)) as original:
    assert original.testzip() is None
    entries = original.infolist()
    assert 0 < len(entries) < 20000
    assert len({e.filename for e in entries}) == len(entries)
    info = plistlib.loads(original.read(ROOT + "Info.plist"))
    assert info["CFBundleIdentifier"] == "com.pablo.resenagoogle.20261004.watch"
    assert info["WKCompanionAppBundleIdentifier"] == "com.pablo.resenagoogle.20261004"
    assert info["WKApplication"] and "WatchOS" in info["CFBundleSupportedPlatforms"]
    assert info["CFBundleShortVersionString"] == "7.3.0" and info["CFBundleVersion"] == "39"
    assert tuple(map(int, info["MinimumOSVersion"].split("."))) <= (10, 6, 2)
    before = dict(info)
    info["CFBundleIdentifier"] = WATCH_ID
    info["WKCompanionAppBundleIdentifier"] = PHONE_ID
    assert {key for key in info if info[key] != before.get(key)} == {"CFBundleIdentifier", "WKCompanionAppBundleIdentifier"}
    executable_name = ROOT + info["CFBundleExecutable"]
    executable_hash = hashlib.sha256(original.read(executable_name)).hexdigest()
    with zipfile.ZipFile(ipa, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as result:
        for entry in entries:
            name = entry.filename
            assert name.startswith(ROOT)
            path = pathlib.PurePosixPath(name[len(ROOT):])
            assert not path.is_absolute() and ".." not in path.parts
            assert not stat.S_ISLNK(entry.external_attr >> 16)
            assert not any(part.endswith((".appex", ".app")) for part in path.parts)
            if "_CodeSignature" in path.parts or path.name == "embedded.mobileprovision":
                continue  # SideStore must generate the matching signature and embed the real profile.
            payload = plistlib.dumps(info) if name == ROOT + "Info.plist" else original.read(name)
            clone = zipfile.ZipInfo(name, entry.date_time)
            clone.external_attr = entry.external_attr
            clone.compress_type = zipfile.ZIP_DEFLATED
            result.writestr(clone, payload)
            kept_hashes[name] = hashlib.sha256(payload).hexdigest()
with zipfile.ZipFile(ipa) as result:
    assert result.testzip() is None
    assert {name.split("/")[1] for name in result.namelist()} == {"reviewNfcGoWatch.app"}
    assert {name: hashlib.sha256(result.read(name)).hexdigest() for name in result.namelist()} == kept_hashes
    assert hashlib.sha256(result.read(executable_name)).hexdigest() == executable_hash
    actual = plistlib.loads(result.read(ROOT + "Info.plist"))
    assert actual == info and compatible(actual["WKCompanionAppBundleIdentifier"], actual["CFBundleIdentifier"])

sha = hashlib.sha256(ipa.read_bytes()).hexdigest()
manifest = {"version": "7.3.0", "build": "39", "watchOnly": True,
    "bundleIdentifier": WATCH_ID, "companionBundleIdentifier": PHONE_ID,
    "sourceURL": SOURCE, "sourceSHA256": SOURCE_SHA256, "sha256": sha, "size": ipa.stat().st_size,
    "executableUnchanged": True, "metadataChanged": ["CFBundleIdentifier", "WKCompanionAppBundleIdentifier"],
    "signingRequired": True, "createsNewAppIDs": False,
    "physicalInstallationVerified": False, "phoneSynchronizationVerified": False,
    "note": "Select the existing reviewNfcGo liveactivity App ID. A valid profile must include this Watch and the active signing certificate."}
(out / "WATCH-REUSE-ID-MANIFEST.json").write_text(json.dumps(manifest, indent=2) + "\n")
(out / "SHA256-WATCH-REUSE-ID.txt").write_text(sha + "  " + ipa.name + "\n")
print(json.dumps(manifest, indent=2))
print("Existing-ID Watch package verified; physical installation is still unverified.")
