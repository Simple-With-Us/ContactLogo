#!/usr/bin/env python3
"""Static contract for the ContactLogo for Mac TestFlight pipeline (CL-203).

The pipeline has several parts that only fail together, and each failure shows
up late: after a merge, in a macOS job that takes ten minutes to reach the
upload.  This check runs in CI on every pull request and fails fast on the
mistakes that would otherwise produce a green PR followed by a rejected upload
or a merge that never ships:

  * the workflow must fire on a push to main that touches the Mac native tree,
    must be dispatchable, must fetch full history, must ship through the fleet
    script with the mandatory What to Test note, and must never set the rate
    gate override as a standing value;
  * the App Store target must not link or compile Sparkle, must use the update
    stub, and must carry no temporary-exception entitlement;
  * the profile map, project.yml, the registry and the workflow must agree on
    the bundle id, the profile name, the scheme and the source paths.

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


# ---------------------------------------------------------------- workflow
print("== workflow ==")
wf = read(".github/workflows/mac-testflight.yml")
wf_code = "\n".join(code_lines(wf))
on_block = block(wf, "on:", 0)
push_block = block(on_block, "  push:", 2)

check("branches: [main]" in push_block, "push trigger is limited to main")
for needed in (
    "Apps/ContactLogoMac/**",
    "Apps/ContactLogoMacAppStore/**",
    "Sources/**",
    "project.yml",
    ".github/workflows/mac-testflight.yml",
):
    check(f"- '{needed}'" in push_block, f"push paths filter covers {needed}")
check("workflow_dispatch:" in on_block, "workflow_dispatch is available")
check("schedule:" in on_block, "a scheduled catch-up exists")
check("ios-scheduled-ship-gate.sh" in wf_code, "the scheduled catch-up carries the path gate")
check(wf_code.count("fetch-depth: 0") >= 2, "the gate and the ship checkout full history (fetch-depth: 0)")
check("scripts/ios-fleet/ship-testflight.sh" in wf_code, "the ship goes through the fleet ship script")
check(re.search(r'IOS_TF_RELEASE_NOTES:\s*"1"', wf_code) is not None, "What to Test is published (IOS_TF_RELEASE_NOTES=1)")
check(re.search(r"IOS_TF_MIN_INTERVAL_SEC\s*[:=]", wf_code) is None, "the rate-gate override is never set as a standing value")
force_lines = [i for i, ln in enumerate(wf_code.splitlines()) if "--force-ship" in ln]
lines = wf_code.splitlines()
guarded = all(
    any('FORCE_SHIP" = "true"' in lines[j] for j in range(max(0, i - 4), i)) for i in force_lines
)
check(len(force_lines) == 1 and guarded, "--force-ship appears once, only behind the per-run force_ship input")
check("force_ship:" in block(on_block, "  workflow_dispatch:", 2) and "default: false" in block(on_block, "  workflow_dispatch:", 2),
      "force_ship defaults to false")
check("github.ref == 'refs/heads/main'" in wf_code, "only main uploads")
check("ios-fleet-pin.sh --check" in wf_code, "the ship verifies the tooling pin")
check("mac-appstore-gm-prepare.sh" in wf_code, "the ship imports the signing identities")
gate_prefixes = re.findall(r"--path-prefix '([^']+)'", wf_code)
check(
    set(gate_prefixes) == {"Apps/ContactLogoMac/", "Apps/ContactLogoMacAppStore/", "Sources/", "project.yml"},
    "the scheduled gate watches the same source paths as the push filter",
)

# ------------------------------------------------------------- project.yml
print("== project.yml ==")
spec = read("project.yml")
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
mac = apps.get("contactlogo-mac", {})
profile_map = json.loads(read("scripts/ios-fleet/mac-appstore-profiles.json") or "{}")
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
