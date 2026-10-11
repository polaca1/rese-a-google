#!/usr/bin/env python3
"""Fail packaging when development routes, unsafe transport or mismatched extensions leak."""
import argparse
import plistlib
from pathlib import Path


def validate(app: Path, platform: str) -> None:
    contents = app / "Contents" if platform == "macos" else app
    info = plistlib.loads((contents / "Info.plist").read_bytes())
    assert info.get("CFBundleShortVersionString") and info.get("CFBundleVersion"), "Falta versión del paquete"
    assert info.get("CFBundleURLTypes", [{}])[0].get("CFBundleURLSchemes") == ["reviewnfcgo"], "Callback de acceso incorrecto"
    assert not info.get("NSAppTransportSecurity", {}).get("NSAllowsArbitraryLoads"), "El transporte seguro está desactivado"
    executable = contents / "MacOS" / info["CFBundleExecutable"] if platform == "macos" else contents / info["CFBundleExecutable"]
    binary = executable.read_bytes()
    for marker in (b"--verification-", b"--verify-desktop", b"GOCSPX-", b"sb_secret_", b"service_role"):
        assert marker not in binary, "El ejecutable contiene un modo de prueba o credencial de servidor"
    privacy_path = contents / "Resources" / "PrivacyInfo.xcprivacy" if platform == "macos" else contents / "PrivacyInfo.xcprivacy"
    privacy = plistlib.loads(privacy_path.read_bytes())
    assert privacy.get("NSPrivacyTracking") is False and not privacy.get("NSPrivacyTrackingDomains"), "Declaración de seguimiento inesperada"
    declared = {item["NSPrivacyCollectedDataType"] for item in privacy["NSPrivacyCollectedDataTypes"]}
    assert {"NSPrivacyCollectedDataTypeEmailAddress", "NSPrivacyCollectedDataTypeUserID", "NSPrivacyCollectedDataTypeOtherFinancialInfo"} <= declared, "Faltan categorías de datos de la cuenta"
    if platform == "macos":
        assert info["LSMinimumSystemVersion"] == "14.0", "El paquete no declara compatibilidad con macOS 14"
    else:
        assert info.get("NSLocationWhenInUseUsageDescription"), "Falta explicación del permiso de ubicación"
        extensions = list((app / "PlugIns").glob("*.appex"))
        assert extensions, "Falta la extensión de widgets y Live Activities"
        for extension in extensions:
            child = plistlib.loads((extension / "Info.plist").read_bytes())
            assert all(child[key] == info[key] for key in ("CFBundleShortVersionString", "CFBundleVersion")), "La versión del widget no coincide"
        assert not (app / "Watch").exists(), "Se ha incluido una app de Watch retirada"


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("app", type=Path)
    parser.add_argument("--platform", choices=["ios", "macos"], required=True)
    args = parser.parse_args()
    validate(args.app, args.platform)
    print("Paquete de producción validado: versión, privacidad, transporte seguro y ausencia de rutas de prueba.")
