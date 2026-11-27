#!/usr/bin/env python3
"""Synchronize derived release labels; --check rejects stale consumers."""
from pathlib import Path
import re,sys
root = Path(__file__).resolve().parent.parent
version = re.search(r"^APP_RELEASE_VERSION = (\d+\.\d+\.\d+)$", (root / "Version.xcconfig").read_text(), re.M)[1]
for project in root.glob("**/*.xcodeproj/project.pbxproj"):
    if ".build" in project.parts or "build" in project.parts:
        continue
    content = project.read_text()
    assert "Version.xcconfig" in content, f"Missing source config: {project}"
    labels = re.findall(r"MARKETING_VERSION = ([^;]+);", content)
    assert labels and all(value == '"$(APP_RELEASE_VERSION)"' for value in labels), f"Competing native version: {project}"
rules = [('Web/build-info.js', 'version: "[^"]+"', 'version: "{version}"')]
for name, pattern, replacement in rules:
    path = root / name
    source = path.read_text()
    count = 2 if name.endswith("package-lock.json") else 1
    derived, matches = re.subn(pattern, replacement.format(version=version), source, count=count)
    assert matches == count, f"Missing release label: {name}"
    if "--check" in sys.argv:
        assert source == derived, f"Stale release label: {name}; run {__file__}"
    else:
        path.write_text(derived)
print(f"Application version {version}: derived surfaces verified")
