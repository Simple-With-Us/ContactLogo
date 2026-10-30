#!/usr/bin/env python3
"""Static contract for the ContactLogo TestFlight release (CL-203/CL-204).

One owner workflow (.github/workflows/testflight.yml) owns every trigger,
plans ONE merge-timestamp build per release, and hands it to the iOS and Mac
lanes (ios-testflight.yml, mac-testflight.yml), which are reusable
(workflow_call) and carry no push/schedule triggers of their own.

The pipeline has several parts that only fail together, and each failure shows
up late: after a merge, in a macOS job that takes ten minutes to reach the
upload.  This check runs in CI on every pull request and fails fast on the
mistakes that would otherwise produce a green PR followed by a rejected upload
or a merge that never ships:

  * the owner must fire on a push to main that touches either native tree,
    must keep both catch-up crons, must be dispatchable with the merged
    inputs, must mirror the push paths in every gate (so a missed push
    still ships on the cron), must plan one build and hand the same value
    to both lanes;
  * each lane must require the planned build, must pass it via --build, must
    fetch full history, must ship through the fleet script with the mandatory
    What to Test note, and must never set the rate gate override as a
    standing value;
  * the App Store target must not link or compile Sparkle, must use the update
    stub, and must carry no temporary-exception entitlement;
  * the profile map, project.yml, the registry and the workflows must agree on
    the bundle id, the profile name, the scheme, the fixed versions and the
    source paths.

Standard library only.  Exit status 0 when every check passes.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FAILURES = []


def check(ok, message):
    print(("  ok  : " if ok else "  FAIL: ") + message)
    if not ok:
        FAILURES.append(message)


def read(rel):
    path = ROOT / rel
    if not path.is_file():
        check(False, f"{rel} exists")
        return ""
    return path.read_text(encoding="utf-8")


def block(text, header, indent):
    """Lines of the YAML mapping that starts at `header` (a line) and runs while
    the following lines are indented deeper than `indent`."""
    lines = text.splitlines()
    out = []
    inside = False
    for line in lines:
        if not inside:
            if line == header:
                inside = True
            continue
        if line.strip() == "" or line.lstrip().startswith("#"):
            out.append(line)
            continue
        depth = len(line) - len(line.lstrip(" "))
        if depth <= indent:
            break
        out.append(line)
    return "\n".join(out)


def code_lines(text):
    return [ln for ln in text.splitlines() if not ln.lstrip().startswith("#")]


def _unquote(token):
    token = token.strip()
    if len(token) >= 2 and token[0] == token[-1] and token[0] in "'\"":
        return token[1:-1]
    return token


def push_paths(paths_block):
    """Entries of an on.push.paths list, whatever their quoting: single, double or none."""
    paths = []
    for line in paths_block.splitlines():
        m = re.match(r"\s*-\s*(.+?)\s*(?:#.*)?$", line)
        if m:
            paths.append(_unquote(m.group(1)))
    return paths


# Bare value excludes a backslash (from HEAD) so a wrapped `--path-prefix e/f/ \`
# line never captures the continuation marker; quoted alternatives are main's.
# Unanchored on purpose: findall scans multi-line gate-call chunks, so no $ anchor.
GATE_PREFIX_RE = re.compile(r"--path-prefix\s+(?:'([^']+)'|\"([^\"]+)\"|([^\s\\]+))")


def gate_prefixes(text):
    """--path-prefix values from scheduled-ship-gate.sh calls only, whatever their quoting."""
    prefixes = []
    lines = text.splitlines()
    i = 0
    while i < len(lines):
        if "scheduled-ship-gate.sh" in lines[i]:
            chunk = [lines[i]]
            j = i + 1
            while chunk[-1].rstrip().endswith("\\") and j < len(lines):
                chunk.append(lines[j])
                j += 1
            cleaned = "\n".join(ln.split("#", 1)[0] for ln in "\n".join(chunk).splitlines())
            for single, double, bare in GATE_PREFIX_RE.findall(cleaned):
                prefixes.append(single or double or bare)
            i = j
        else:
            i += 1
    return prefixes


def gate_step(wf_code):
    """The Scheduled ship gate step: from its `- name:` line to the next step
    at the same indent or the next job header (the Mac gate is the last step
    of its job, so without the job break it would slurp the ship job)."""
    out = []
    inside = False
    for line in wf_code.splitlines():
        if not inside:
            if re.match(r"\s*- name: Scheduled ship gate", line):
                inside = True
                out.append(line)
            continue
        if re.match(r"      - ", line):
            break
        if re.match(r"  \S", line):
            break
        out.append(line)
    return "\n".join(out)


print("== extractor self-check ==")
_SAMPLE_PUSH = (
    "      - 'a/**'\n"
    '      - "b/**"\n'
    "      - c/**\n"
    "      - 'd/**' # reason\n"
)
check(push_paths(_SAMPLE_PUSH) == ["a/**", "b/**", "c/**", "d/**"],
      "push-path extractor keeps single, double, bare and trailing-comment entries")
_SAMPLE_PUSH_BLOCK = (
    "    branches: [main]\n"
    "    paths:  # push filter\n"
    "      - 'a/b/'\n"
    '      - "c/d/"\n'
    "      - e/f/\n"
    "      - 'g/h/' # trailing reason\n"
    "    paths-ignore:\n"
    "      - 'zzz/'\n"
)
_sample_header = re.search(r"^    paths:\s*(?:#.*)?$", _SAMPLE_PUSH_BLOCK, re.MULTILINE)
check(push_paths(block(_SAMPLE_PUSH_BLOCK,
                       _sample_header.group(0) if _sample_header else "    paths:", 4))
      == ["a/b/", "c/d/", "e/f/", "g/h/"],
      "push-path extraction tolerates a trailing comment on 'paths:' and ignores paths-ignore")
_SAMPLE_GATE = (
    "          bash scripts/ios-fleet/scheduled-ship-gate.sh \\\n"
    "            --event schedule \\\n"
    "            --path-prefix 'a/**' \\\n"
    '            --path-prefix "b/**" \\\n'
    "            --path-prefix c/** \\\n"
    "            --path-prefix 'd/**' # reason\n"
    "      - run: echo --path-prefix 'zzz/'\n"
)
check(gate_prefixes(_SAMPLE_GATE) == ["a/**", "b/**", "c/**", "d/**"],
      "gate-prefix extractor keeps single, double, bare and trailing-comment entries (gate calls only)")
_SAMPLE_GATE_STEP = (
    "      - name: Scheduled ship gate (skip unless a release path changed)\n"
    "        id: gate\n"
    "        run: |\n"
    "          bash scripts/ios-fleet/scheduled-ship-gate.sh \\\n"
    "            --path-prefix 'a/**' \\\n"
    "            contactlogo-mac\n"
    "\n"
    "  ship:\n"
    "    name: Ship\n"
    "    steps:\n"
    "      - uses: actions/checkout@v7\n"
)
check("  ship:" not in gate_step(_SAMPLE_GATE_STEP)
      and gate_prefixes(gate_step(_SAMPLE_GATE_STEP)) == ["a/**"],
      "gate_step stops at the next job header when the gate is the last step")


# ---------------------------------------------------------------- release owner
print("== release owner (.github/workflows/testflight.yml) ==")
owner = read(".github/workflows/testflight.yml")
owner_code = "\n".join(code_lines(owner))
owner_on = block(owner, "on:", 0)
owner_push = block(owner_on, "  push:", 2)

# Exact match, not a substring:  exactly one `branches:` key under push (a
# `branches-ignore:` or a second key fails too), written as the one-item flow
# list `[main]`.  A block-style list or any extra branch fails the check.
branch_lines = [
    ln.split("#", 1)[0].rstrip()
    for ln in owner_push.splitlines()
    if ln.strip().startswith("branches")
]
check(
    len(branch_lines) == 1 and re.fullmatch(r"\s*branches:\s*\[\s*main\s*\]", branch_lines[0]) is not None,
    "owner push trigger is limited to main (exactly `branches: [main]`)",
)
# The scheduled backstop must ship exactly what the push trigger would have
# shipped, so every gate mirrors on.push.paths entry for entry (globs and
# '!' exclusions verbatim).  The push list is the single source of truth:
# it is read out of the workflow file here, not repeated.  The header match
# tolerates a trailing comment (from HEAD: `paths:  # push filter`).
_paths_header = re.search(r"^    paths:\s*(?:#.*)?$", owner_push, re.MULTILINE)
PUSH_PATHS = push_paths(block(owner_push, _paths_header.group(0) if _paths_header else "    paths:", 4))
check(len(PUSH_PATHS) >= 10, "the owner push filter is readable as a path list")
for needed in (
    "Apps/ContactLogoiOS/**",
    "Apps/ContactLogoMac/**",
    "Apps/ContactLogoMacAppStore/**",
    "Sources/**",
    "project.yml",
    ".github/workflows/testflight.yml",
    ".github/workflows/ios-testflight.yml",
    ".github/workflows/mac-testflight.yml",
    ".github/actions/infisical-secrets/**",
    "scripts/ios-fleet/**",
    "scripts/ios-fleet-pin.sh",
    "scripts/ios-fleet.sha256",
):
    check(needed in PUSH_PATHS, f"owner push paths filter covers {needed}")
check("workflow_dispatch:" in owner_on, "owner workflow_dispatch is available")
owner_dispatch = block(owner_on, "  workflow_dispatch:", 2)
for name in ("export_only:", "validate_only:", "force_ship:"):
    check(name in owner_dispatch, f"owner dispatch merges {name[:-1]}")
check("force_ship:" in owner_dispatch and "default: false" in owner_dispatch,
      "owner force_ship defaults to false")
check("cron: '19,49 * * * *'" in owner_on and "cron: '17 * * * *'" in owner_on,
      "owner keeps both catch-up crons unchanged")
check("scripts/ios-fleet/scheduled-ship-gate.sh" in owner_code, "owner gates carry the path gate")
check(owner_code.count("--event schedule") >= 2,
      "owner gates always take the path-diff (--event schedule)")
for _job in ("gate-ios", "gate-mac"):
    _gate_prefixes = gate_prefixes(block(owner, f"  {_job}:", 2))
    check(bool(_gate_prefixes) and len(_gate_prefixes) == len(set(_gate_prefixes)),
          f"{_job} passes each gate path exactly once")
    check(set(_gate_prefixes) == set(PUSH_PATHS),
          f"{_job} mirrors on.push.paths entry for entry")
check(owner_code.count("fetch-depth: 0") >= 2, "owner gates checkout full history (fetch-depth: 0)")
check("--plan-build-only" in owner_code, "owner plans the release build once (--plan-build-only)")
check(owner_code.count("needs.plan-build.outputs.build") >= 2,
      "both lane calls receive the same planned build")
for lane in ("ios-testflight.yml", "mac-testflight.yml"):
    check(f"uses: ./.github/workflows/{lane}" in owner_code, f"owner calls {lane}")
check("secrets: inherit" in owner_code, "owner passes secrets to the lanes")
check("secret-path: /asc" in owner_code, "plan-build loads the ASC key the way the ships do")
check("ios-fleet-pin.sh --check" in owner_code, "plan-build verifies the tooling pin")
check(re.search(r"IOS_TF_MIN_INTERVAL_SEC\s*[:=]", owner_code) is None,
      "owner never sets the rate-gate override as a standing value")
check("--force-ship" not in owner_code, "owner never passes --force-ship")
check("contactlogo-testflight-release" in owner, "owner serializes releases")


def check_lane(rel, ship_via):
    print(f"== lane ({rel}) ==")
    wf = read(rel)
    wf_code = "\n".join(code_lines(wf))
    on_block = block(wf, "on:", 0)
    check("  push:" not in on_block, f"{rel} carries no push trigger (the owner does)")
    check("  schedule:" not in on_block, f"{rel} carries no schedule trigger (the owner does)")
    check("workflow_call:" in on_block, f"{rel} is reusable (workflow_call)")
    call_build = re.search(r"      build:\n((?:        \S.*\n)+)", on_block)
    check(call_build is not None and "required: true" in call_build.group(1)
          and "type: string" in call_build.group(1),
          f"{rel} requires the planned build input")
    check("workflow_dispatch:" in on_block, f"{rel} keeps a standalone workflow_dispatch")
    check("build:" in block(on_block, "  workflow_dispatch:", 2),
          f"{rel} dispatch takes or plans a build")
    check("scripts/ios-fleet/scheduled-ship-gate.sh" in wf_code, f"{rel} keeps its ship gate")
    check(set(gate_prefixes(gate_step(wf_code))) == set(PUSH_PATHS),
          f"{rel} gate mirrors the owner's push paths")
    check(ship_via in wf_code, f"{rel} ships through {ship_via}")
    check("--build" in wf_code, f"{rel} passes the planned build via --build")
    check("--plan-build-only" in wf_code, f"{rel} plans its own build on a standalone dispatch")
    check(re.search(r'IOS_TF_RELEASE_NOTES:\s*"1"', wf_code) is not None,
          f"{rel} publishes What to Test (IOS_TF_RELEASE_NOTES=1)")
    check(re.search(r"IOS_TF_MIN_INTERVAL_SEC\s*[:=]", wf_code) is None,
          f"{rel} never sets the rate-gate override as a standing value")
    check("group: contactlogo-testflight" in wf, f"{rel} keeps the shared ship concurrency group")
    return wf, wf_code, on_block


ios_wf, ios_code, ios_on = check_lane(
    ".github/workflows/ios-testflight.yml",
    "scripts/ios-ship-testflight.sh",
)
check("github.ref == 'refs/heads/main'" in ios_code, "iOS lane uploads only from main")
check("--force-ship" not in ios_code, "iOS lane never passes --force-ship")

mac_wf, mac_code, mac_on = check_lane(
    ".github/workflows/mac-testflight.yml",
    "scripts/ios-fleet/ship-testflight.sh",
)
check(mac_code.count("fetch-depth: 0") >= 2,
      "the Mac gate and the Mac ship checkout full history (fetch-depth: 0)")
force_lines = [i for i, ln in enumerate(mac_code.splitlines()) if "--force-ship" in ln]
mac_lines = mac_code.splitlines()
guarded = all(
    any('FORCE_SHIP" = "true"' in mac_lines[j] for j in range(max(0, i - 4), i)) for i in force_lines
)
check(len(force_lines) == 1 and guarded, "--force-ship appears once, only behind the per-run force_ship input")
check("force_ship:" in block(mac_on, "  workflow_dispatch:", 2)
      and "default: false" in block(mac_on, "  workflow_dispatch:", 2),
      "Mac force_ship defaults to false")
check("github.ref == 'refs/heads/main'" in mac_code, "Mac lane uploads only from main")
check("ios-fleet-pin.sh --check" in mac_code, "the Mac ship verifies the tooling pin")
check("mac-appstore-gm-prepare.sh" in mac_code, "the Mac ship imports the signing identities")

# ------------------------------------------------------------- project.yml
print("== project.yml ==")
spec = read("project.yml")
check('MARKETING_VERSION: "0.1.0"' in spec, "project.yml carries the 0.1.0 placeholder")
check('CURRENT_PROJECT_VERSION: "202610290000"' in spec, "project.yml carries the merge-stamp placeholder build")
target = block(spec, "  ContactLogoMacAppStore:", 2)
check(bool(target.strip()), "the ContactLogoMacAppStore target exists")
check("Sparkle" not in "\n".join(code_lines(target)), "the App Store target has no Sparkle dependency")
check("AutoUpdate.swift" in target and "excludes:" in target, "the App Store target excludes AutoUpdate.swift")
check("Apps/ContactLogoMacAppStore" in target, "the App Store target compiles the update stub folder")
check("PRODUCT_BUNDLE_IDENTIFIER: com.contactlogo.macos" in target, "the App Store target keeps the Mac bundle id")
check("ContactLogoMacAppStore.entitlements" in target, "the App Store target uses its own entitlements")
check("CODE_SIGN_STYLE: Manual" in target and 'CODE_SIGN_IDENTITY: "Apple Distribution"' in target,
      "Release signs manually with Apple Distribution")
spec_profile = re.search(r'PROVISIONING_PROFILE_SPECIFIER:\s*"([^"]+)"', target)
check(spec_profile is not None, "Release names a provisioning profile")
schemes = block(spec, "schemes:", 0)
check("  ContactLogoMacAppStore:" in schemes, "the ContactLogoMacAppStore scheme is declared")
mac_target = block(spec, "  ContactLogoMac:", 2)
check("package: Sparkle" in mac_target, "the Developer ID target still links Sparkle")

# ----------------------------------------------------- registry + profile map
print("== registry and profile map ==")
apps = json.loads(read("scripts/ios-fleet/apps.json") or "{}").get("apps", {})
ios = apps.get("contactlogo", {})
mac = apps.get("contactlogo-mac", {})
profile_map = json.loads(read("scripts/ios-fleet/mac-appstore-profiles.json") or "{}")
check(ios.get("fixedMarketingVersion") == "0.1.0", "the registry pins the iOS fixed marketing version")
check(ios.get("pairedBundleId") == "com.contactlogo.macos", "the iOS entry pairs with the Mac bundle id")
check(mac.get("fixedMarketingVersion") == "0.1.0", "the registry pins the Mac fixed marketing version")
check(mac.get("pairedBundleId") == "com.contactlogo", "the Mac entry pairs with the iOS bundle id")
check(mac.get("scheme") == "ContactLogoMacAppStore", "the registry ships the App Store scheme")
check(mac.get("platform") == "macOS", "the registry marks contactlogo-mac as macOS")
check(mac.get("bundleId") == "com.contactlogo.macos", "the registry bundle id is com.contactlogo.macos")
check(mac.get("appleId") == 6804248235, "the registry names the ASC app record")
check(mac.get("appstoreProfilesMap") == "scripts/ios-fleet/mac-appstore-profiles.json", "the registry points at the profile map")
check(list(profile_map) == ["com.contactlogo.macos"], "the profile map covers exactly the Mac bundle id")
check(spec_profile is not None and profile_map.get("com.contactlogo.macos") == spec_profile.group(1),
      "the profile map name equals PROVISIONING_PROFILE_SPECIFIER")

# ----------------------------------------------------- entitlements and stub
print("== App Store build contents ==")
ents = read("Apps/ContactLogoMacAppStore/ContactLogoMacAppStore.entitlements")
check("com.apple.security.app-sandbox" in ents, "the App Store build is sandboxed")
check("temporary-exception" not in ents, "the App Store build has no temporary-exception entitlement")
check("group.com.contactlogo" in ents, "the App Store build keeps the App Group")
stub = read("Apps/ContactLogoMacAppStore/AutoUpdateStub.swift")
check("import Sparkle" not in stub, "the update stub does not import Sparkle")
check("enum AutoUpdateAvailability" in stub and "final class AppUpdater" in stub,
      "the update stub defines AppUpdater and AutoUpdateAvailability")
for member in ("static let shared", "var canCheckForUpdates", "func start()", "func checkForUpdates()", "var summary"):
    check(member in stub, f"the update stub provides {member}")

print()
if FAILURES:
    print(f"{len(FAILURES)} check(s) failed")
    sys.exit(1)
print("mac-testflight contract: all checks passed")
