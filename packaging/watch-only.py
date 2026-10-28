"""Repackage the published, checksum-pinned Watch binary; no rebuilding or signing."""
import hashlib, io, json, pathlib, plistlib, stat, struct, urllib.request, zipfile
original = "https://github.com/polaca1/rese-a-google/releases/download/reviewnfcgo-7.3.0-build39/reviewNfcGo-7.3.0-build39-iPhone-Watch-Sideloadly.ipa"
expected = "a58ad32a376812e921779d8be4033b9e3b5468df5da7448c142c1b22bb19ef1f"
with urllib.request.urlopen(original, timeout=120) as response:
    data = response.read()
assert len(data) == 7481917 and hashlib.sha256(data).hexdigest() == expected
source = "Payload/reviewNfcGo.app/Watch/reviewNfcGoWatch.app/"
target = "Payload/reviewNfcGoWatch.app/"
output = pathlib.Path("output")
output.mkdir(exist_ok=True)
ipa = output / "reviewNfcGo-Watch-7.3.0-build39.ipa"
with zipfile.ZipFile(io.BytesIO(data)) as archive:
    assert archive.testzip() is None
    entries = [entry for entry in archive.infolist() if entry.filename.startswith(source)]
    assert entries and len(entries) < 20000
    assert len({e.filename for e in entries}) == len(entries)
    info = plistlib.loads(archive.read(source + "Info.plist"))
    assert info["CFBundleIdentifier"] == "com.pablo.resenagoogle.20261004.watch"
    assert info["WKCompanionAppBundleIdentifier"] == "com.pablo.resenagoogle.20261004"
    assert info["WKApplication"] and "WatchOS" in info["CFBundleSupportedPlatforms"]
    assert info["CFBundleShortVersionString"] == "7.3.0" and info["CFBundleVersion"] == "39"
    assert tuple(map(int, info["MinimumOSVersion"].split("."))) <= (10, 6, 2)
    executable = archive.read(source + info["CFBundleExecutable"])
    # Verify the released binary includes the user's older Watch architecture.
    magic = executable[:4]
    if magic in (b"\xca\xfe\xba\xbe", b"\xca\xfe\xba\xbf"):
        count = struct.unpack_from(">I", executable, 4)[0]
        stride = 32 if magic[-1] == 0xbf else 20
        assert 0 < count <= 32
        cpus = [struct.unpack_from(">I", executable, 8 + i * stride)[0] for i in range(count)]
    else:
        assert magic in (b"\xcf\xfa\xed\xfe", b"\xce\xfa\xed\xfe")
        cpus = [struct.unpack_from("<I", executable, 4)[0]]
    assert 0x0200000c in cpus, "Missing arm64_32"
    assert b"--verification-" not in executable
    expected_hashes = {}
    with zipfile.ZipFile(ipa, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as result:
        for entry in entries:
            relative = entry.filename[len(source):]
            path = pathlib.PurePosixPath(relative)
            assert not path.is_absolute() and ".." not in path.parts
            assert not stat.S_ISLNK(entry.external_attr >> 16)
            assert not any(part.endswith((".appex", ".app")) for part in path.parts)
            name = target + relative
            payload = archive.read(entry.filename)
            clone = zipfile.ZipInfo(name, entry.date_time)
            clone.external_attr = entry.external_attr
            clone.compress_type = zipfile.ZIP_DEFLATED
            result.writestr(clone, payload)
            expected_hashes[name] = hashlib.sha256(payload).hexdigest()
with zipfile.ZipFile(ipa) as archive:
    assert archive.testzip() is None
    assert {entry.split("/")[1] for entry in archive.namelist()} == {"reviewNfcGoWatch.app"}
    assert {name: hashlib.sha256(archive.read(name)).hexdigest() for name in archive.namelist()} == expected_hashes
sha = hashlib.sha256(ipa.read_bytes()).hexdigest()
manifest = {"version": "7.3.0", "build": "39", "bundleIdentifier": info["CFBundleIdentifier"],
    "companionBundleIdentifier": info["WKCompanionAppBundleIdentifier"], "minimumOS": info["MinimumOSVersion"],
    "arm64_32": True, "watchOnly": True, "fileContentsUnchanged": True,
    "sourceIPA": original, "sourceSHA256": expected, "sha256": sha, "size": ipa.stat().st_size,
    "signingRequired": True, "physicalInstallationVerified": False,
    "note": "The existing provisioning profile must match the Watch bundle identifier. No App IDs are created."}
(output / "WATCH-ONLY-MANIFEST.json").write_text(json.dumps(manifest, indent=2) + "\n")
(output / "SHA256-WATCH-ONLY.txt").write_text(sha + "  " + ipa.name + "\n")
print(json.dumps(manifest, indent=2))
