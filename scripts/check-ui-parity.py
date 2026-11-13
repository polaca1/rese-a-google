#!/usr/bin/env python3
"""Reject unintended changes while moving the existing SwiftUI app into SwiftPM."""
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parents[1]
manifest = json.loads((root / "provenance/upstream.json").read_text())
source = root / "swiftui/Sources/ReviewNfcGoViews"
normalizations = {
    "AppAppearance.swift": [('Image("BrandMark", bundle: .module)', 'Image("BrandMark")')],
    "GoogleSignIn.swift": [('Image("GoogleLogo", bundle: .module)', 'Image("GoogleLogo")')],
    "WidgetSharedStore.swift": [("group.org.appfair.app.ReviewNfcGo.widgets", "group.com.pablo.resenagoogle.20261004.widgets")],
}
failures = []
for name, expected in manifest["sourceSha256"].items():
    value = (source / name).read_bytes()
    for after, before in normalizations.get(name, []):
        value = value.replace(after.encode(), before.encode())
    if hashlib.sha256(value).hexdigest() != expected:
        failures.append(name)
if failures:
    raise SystemExit("Unexpected differences from the original app: " + ", ".join(failures))
print(f"{len(manifest['sourceSha256'])} original Swift sources preserved; resource/group adapters normalized.")
