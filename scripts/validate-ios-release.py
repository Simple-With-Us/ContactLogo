#!/usr/bin/env python3
"""Validate the archived/exported iPhone identity before TestFlight upload."""

import argparse
import datetime
import json
import plistlib
import re
from pathlib import Path

BUNDLE_ID = "com.contactlogo"
TEAM_ID = "CC8UTF7ATG"
PROJECT_YML = Path(__file__).resolve().parents[1] / "project.yml"


def project_marketing_version(text):
    """The iPhone target's MARKETING_VERSION, read from project.yml.

    project.yml is the single source, so read it.  ContactLogo keeps one
    MARKETING_VERSION in settings.base for every target.
    """
    match = re.search(
        r"^settings:\n(?:(?!^[^ \n]).*\n)*?\s+MARKETING_VERSION:\s*\"?([0-9]+(?:\.[0-9]+)*)\"?",
        text,
        re.MULTILINE,
    )
    if not match:
        raise ValueError("MARKETING_VERSION not found in project.yml")
    return match.group(1)


MARKETING_VERSION = project_marketing_version(PROJECT_YML.read_text())


def validate(info, profile, entitlements, build_number, distribution=False):
    def require(condition, message):
        if not condition:
            raise ValueError(message)

    identifier = f"{TEAM_ID}.{BUNDLE_ID}"
    require(info.get("CFBundleIdentifier") == BUNDLE_ID, "unexpected app bundle identifier")
    require(info.get("CFBundleVersion") == build_number, "unexpected app build number")
    require(info.get("CFBundleShortVersionString") == MARKETING_VERSION, "unexpected app version")
    require(info.get("CFBundleSupportedPlatforms") == ["iPhoneOS"], "app is not an iOS device build")
    require(info.get("CFBundlePackageType") == "APPL", "bundle is not an app")
    require(TEAM_ID in profile.get("TeamIdentifier", []), "unexpected provisioning team")
    require("iOS" in profile.get("Platform", []), "profile is not for iOS")
    profile_entitlements = profile.get("Entitlements", {})
    require(profile_entitlements.get("application-identifier") == identifier, "profile bundle mismatch")
    for label, values in (("profile", profile_entitlements), ("signature", entitlements)):
        require(values.get("com.apple.developer.team-identifier") == TEAM_ID, f"{label} team mismatch")
        require(values.get("application-identifier") == identifier, f"{label} bundle mismatch")
        # ContactLogo declares an App Group and associated domains for future
        # shared-container / Universal Link work; unlike HogHunter they are
        # expected here when the portal has them provisioned, so they are not
        # asserted absent.
    expires = profile.get("ExpirationDate")
    require(isinstance(expires, datetime.datetime), "profile expiration missing")
    if expires.tzinfo is None:
        expires = expires.replace(tzinfo=datetime.timezone.utc)
    require(expires > datetime.datetime.now(datetime.timezone.utc), "profile has expired")
    if distribution:
        require(not profile.get("ProvisionedDevices"), "export profile is device-limited")
        require(not profile.get("ProvisionsAllDevices"), "enterprise export is not allowed")
        require(profile_entitlements.get("get-task-allow") is False, "export profile permits debugging")
        require(entitlements.get("get-task-allow") is False, "export signature permits debugging")
        require(profile_entitlements.get("beta-reports-active") is True, "export is not an App Store beta profile")
    return {
        "bundle": BUNDLE_ID,
        "version": MARKETING_VERSION,
        "build": build_number,
        "team": TEAM_ID,
        "distribution": distribution,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--info", type=Path, required=True)
    parser.add_argument("--profile", type=Path, required=True)
    parser.add_argument("--entitlements", type=Path, required=True)
    parser.add_argument("--build-number", required=True)
    parser.add_argument("--distribution", action="store_true")
    args = parser.parse_args()
    try:
        values = [plistlib.loads(path.read_bytes()) for path in (args.info, args.profile, args.entitlements)]
        result = validate(*values, args.build_number, args.distribution)
    except (ValueError, OSError, TypeError, AttributeError) as error:
        parser.exit(1, f"release identity validation failed: {error}\n")
    print(json.dumps(result, sort_keys=True))


if __name__ == "__main__":
    main()
