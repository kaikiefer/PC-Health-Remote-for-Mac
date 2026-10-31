#!/usr/bin/env python3
"""Prepare a source-only handoff, without build products or personal QA notes."""
from pathlib import Path
import plistlib
import zipfile

root = Path(__file__).resolve().parent.parent
version = plistlib.loads((root / "Info.plist").read_bytes())["CFBundleShortVersionString"]
destination = root / "build" / "releases"
destination.mkdir(parents=True, exist_ok=True)
output = destination / f"PC-Health-Remote-v{version}-source.zip"
files = [root / name for name in (
    ".gitignore", "Info.plist", "README.md", "LICENSE", "NOTICE.md", "PRIVACY.md", "CHANGELOG.md"
)]
for name in (".github", "Assets", "Sources", "Tests", "ThirdParty", "scripts", "docs"):
    files.extend(path for path in (root / name).rglob("*") if path.is_file())
with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as archive:
    for path in sorted(set(files)):
        if path.is_symlink() or path.name == ".DS_Store" or "__pycache__" in path.parts:
            continue
        archive.write(path, Path("PCHealthRemote") / path.relative_to(root))
print(output)
