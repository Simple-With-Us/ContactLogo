#!/usr/bin/env python3
"""Check the canonical platform directories and case-folded path uniqueness."""
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
EXPECTED = {
    "apps/android",
    "apps/ios",
    "apps/macos",
    "apps/macos-app-store",
    "apps/web",
}

missing = sorted(path for path in EXPECTED if not (ROOT / path).is_dir())
root_names = {path.name for path in ROOT.iterdir()}
legacy = sorted(path for path in ("Apps", "web") if path in root_names)
tracked = subprocess.run(
    ["git", "-C", str(ROOT), "ls-files", "-z"], check=True, capture_output=True
).stdout.split(b"\0")
paths = [path.decode("utf-8") for path in tracked if path]
folded = {}
collisions = []
for path in paths:
    key = path.casefold()
    previous = folded.setdefault(key, path)
    if previous != path:
        collisions.append((previous, path))

if missing or legacy or collisions:
    for path in missing:
        print(f"missing canonical directory: {path}")
    for path in legacy:
        print(f"legacy top-level directory remains: {path}")
    for left, right in collisions:
        print(f"case-fold path collision: {left} <> {right}")
    sys.exit(1)

print("platform directory layout is canonical; tracked paths are case-fold unique")
