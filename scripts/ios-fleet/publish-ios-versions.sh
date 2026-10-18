#!/usr/bin/env bash
# publish-ios-versions.sh - hosted-runner stand-in (ContactLogo, CL-204).
#
# ship-testflight.sh calls this after a successful upload to update the public
# fleet iOS version manifest (Simple-With-Us/ai-fleet-coordinator,
# site/ios-versions.json).  That publish needs a token this repo's workflow
# does not hold, and the Mac copy of the script also runs an icon preflight
# against Mac-only paths.  So on the hosted runner this exits 1 on purpose:
# ship-testflight.sh then logs "version-manifest publish failed (non-fatal)"
# instead of claiming a publish that did not happen.  To refresh the manifest
# entry by hand, run /Users/jay/apps/ios-fleet/publish-ios-versions.sh on the
# Mac with the shipped --version and --build.
echo "publish-ios-versions: not published from a hosted runner" >&2
exit 1
