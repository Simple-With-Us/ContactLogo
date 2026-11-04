#!/usr/bin/env python3
"""Check canonical platform paths and the temporary read-only web bridge."""
from pathlib import Path
import hashlib
import os
import re
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

# The deploy job builds the bridge root, and the production catch-up refuses
# any deployment whose CLI tree was dirty.  A build output that is not
# ignored leaves the checkout dirty, so the deployment carries a dirty marker
# and the receipt check fails after the upload.  Both web roots must ignore
# their build output for the catch-up to be able to publish.
unignored_build_output = []
tracked_build_output = []
negated_build_output = []
# Ignore rules that can cover a build output directory.
IGNORE_FILES = (".gitignore", "apps/.gitignore", "apps/web/.gitignore", "web/.gitignore")


def negation_inside(prefix):
    """Ignore rules that un-ignore a path inside a build output directory."""
    hits = []
    for relative in IGNORE_FILES:
        ignore_file = ROOT / relative
        if not ignore_file.is_file():
            continue
        base = os.path.dirname(relative)
        for raw in ignore_file.read_text(encoding="utf-8", errors="replace").splitlines():
            line = raw.strip()
            if not line.startswith("!"):
                continue
            pattern = line[1:].strip()
            if not pattern:
                continue
            literal = re.split(r"[*?\[]", pattern, maxsplit=1)[0].strip("/")
            effective = f"{base}/{literal}" if base else literal
            if effective == prefix or effective.startswith(prefix + "/"):
                hits.append(f"{relative}: {line}")
    return hits


for web_root in ("apps/web", "web"):
    build_output = f"{web_root}/dist"
    # The trailing slash makes git treat the path as a directory, so a
    # directory-only ignore rule counts as covered.
    ignored = subprocess.run(
        ["git", "-C", str(ROOT), "check-ignore", "-q", f"{build_output}/"]
    ).returncode == 0
    # A nested path proves the whole output is covered: a nested un-ignore
    # exception stays invisible to the directory probe.
    nested_ignored = subprocess.run(
        ["git", "-C", str(ROOT), "check-ignore", "-q", f"{build_output}/index.html"]
    ).returncode == 0
    # Tracked build output is rewritten by the build, so it dirties the
    # checkout even when an ignore rule matches.
    tracked = subprocess.run(
        ["git", "-C", str(ROOT), "ls-files", "--", f"{build_output}"],
        check=True, capture_output=True, text=True
    ).stdout.strip()
    if not ignored or not nested_ignored:
        unignored_build_output.append(build_output)
    if tracked:
        tracked_build_output.append(build_output)
    for rule in negation_inside(build_output):
        negated_build_output.append(f"{build_output} ({rule})")

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

if missing or directory_symlinks or missing_bridge or wrong_case_roots or root_collisions or collisions or non_regular or missing_bridge_files or extra_bridge_files or changed_bridge_files or missing_worktree_files or changed_worktree_files or unignored_build_output or tracked_build_output or negated_build_output:
    for path in missing:
        print(f"missing canonical directory: {path}")
    if missing_bridge:
        print("missing required legacy web deployment bridge: web")
    for path in unignored_build_output:
        print(f"web build output is not gitignored: {path}")
    for path in tracked_build_output:
        print(f"web build output is tracked: {path}")
    for path in negated_build_output:
        print(f"web build output is un-ignored by a negation rule: {path}")
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
