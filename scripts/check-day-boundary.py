#!/usr/bin/env python3
"""Prevent a hosted legacy application UI from entering the migrated Day target."""
from pathlib import Path
import re
import tomllib
root = Path(__file__).resolve().parents[1]
manifest = tomllib.loads((root / 'Cargo.toml').read_text())
assert 'day-piece-swiftui' not in manifest.get('dependencies', {})
packages = manifest['package']['metadata']['day']['ios']['swift-packages']
assert all(p['path'] == 'native-services' for p in packages)
for path in (root / 'native-services/Sources').rglob('*.swift'):
    text = path.read_text()
    for pattern in [r'^import SwiftUI$', r'UIHostingController\s*[<(]', r'UIViewRepresentable', r'\bstruct\s+\w+\s*:\s*View\b']:
        assert not re.search(pattern, text, re.M), f'{path}: unexpected hosted application UI'
lib = (root / 'src/lib.rs').read_text()
assert 'day::day_start!' in lib and 'pages::root' in lib
print('Day owns application screens/navigation; native services contain no SwiftUI screen host.')
