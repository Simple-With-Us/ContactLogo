#!/usr/bin/env python3
"""Check canonical platform paths and the temporary read-only web bridge."""
from pathlib import Path
import hashlib
import stat
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
directory_symlinks = sorted(
    path for path in ("apps/web", "web") if (ROOT / path).is_symlink()
)
root_names = sorted(path.name for path in ROOT.iterdir())
root_folded = {}
root_collisions = []
for name in root_names:
    key = name.casefold()
    previous = root_folded.setdefault(key, name)
    if previous != name:
        root_collisions.append((previous, name))
wrong_case_roots = sorted(
    name for name in root_names if name.casefold() in {"apps", "web"}
    and name not in {"apps", "web"}
)
missing_bridge = not (ROOT / "web").is_dir()

index = subprocess.run(
    ["git", "-C", str(ROOT), "ls-files", "-s", "-z"], check=True, capture_output=True
).stdout.split(b"\0")
entries = {}
for record in index:
    if not record:
        continue
    metadata, raw_path = record.split(b"\t", 1)
    mode, blob, _stage = metadata.decode("ascii").split()
    entries[raw_path.decode("utf-8")] = (mode, blob)
paths = list(entries)
folded = {}
collisions = []
for path in paths:
    key = path.casefold()
    previous = folded.setdefault(key, path)
    if previous != path:
        collisions.append((previous, path))

source = {
    path.removeprefix("apps/web/"): entry
    for path, entry in entries.items()
    if path.startswith("apps/web/")
}
bridge = {
    path.removeprefix("web/"): entry
    for path, entry in entries.items()
    if path.startswith("web/")
}
non_regular = sorted(
    f"{prefix}{path} (mode {mode})"
    for prefix, files in (("apps/web/", source), ("web/", bridge))
    for path, (mode, _blob) in files.items()
    if mode not in {"100644", "100755"}
)
missing_bridge_files = sorted(set(source) - set(bridge))
extra_bridge_files = sorted(set(bridge) - set(source))
changed_bridge_files = sorted(
    path for path in set(source) & set(bridge) if source[path] != bridge[path]
)
missing_worktree_files = []
changed_worktree_files = []
for prefix, files in (("apps/web/", source), ("web/", bridge)):
    for relative, (expected_mode, expected_blob) in files.items():
        path = prefix + relative
        full_path = ROOT / path
        if full_path.is_symlink() or not full_path.is_file():
            missing_worktree_files.append(path)
            continue
        content = full_path.read_bytes()
        blob = hashlib.sha1(f"blob {len(content)}\0".encode() + content).hexdigest()
        mode_bits = stat.S_IMODE(full_path.stat().st_mode)
        mode = "100755" if mode_bits & 0o111 else "100644"
        if blob != expected_blob or mode != expected_mode:
            changed_worktree_files.append(path)

if missing or directory_symlinks or missing_bridge or wrong_case_roots or root_collisions or collisions or non_regular or missing_bridge_files or extra_bridge_files or changed_bridge_files or missing_worktree_files or changed_worktree_files:
    for path in missing:
        print(f"missing canonical directory: {path}")
    if missing_bridge:
        print("missing required legacy web deployment bridge: web")
    for path in directory_symlinks:
        print(f"canonical source and web bridge directories cannot be symlinks: {path}")
    for path in wrong_case_roots:
        print(f"unexpected case variant for required root directory: {path}")
    for left, right in root_collisions:
        print(f"case-fold root-name collision: {left} <> {right}")
    for left, right in collisions:
        print(f"case-fold path collision: {left} <> {right}")
    for path in non_regular:
        print(f"web bridge only supports tracked regular files: {path}")
    for path in missing_bridge_files:
        print(f"missing tracked web bridge file: web/{path}")
    for path in extra_bridge_files:
        print(f"extra tracked web bridge file: web/{path}")
    for path in changed_bridge_files:
        source_mode, source_blob = source[path]
        bridge_mode, bridge_blob = bridge[path]
        details = []
        if source_blob != bridge_blob:
            details.append("blob differs")
        if source_mode != bridge_mode:
            details.append(f"mode {bridge_mode} != {source_mode}")
        print(f"web bridge differs from apps/web/{path}: {', '.join(details)}")
    for path in missing_worktree_files:
        print(f"missing tracked worktree file: {path}")
    for path in changed_worktree_files:
        print(f"tracked worktree file differs from index: {path}")
    sys.exit(1)

print("platform directories are canonical; tracked paths are case-fold unique; web bridge matches apps/web")
