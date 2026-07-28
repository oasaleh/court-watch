#!/usr/bin/env bash
#
# Runs the accessibility UI tests.
#
# Held out of Scripts/test.sh on purpose. These launch the app and read the
# accessibility tree of a running screen, which means they take a minute
# rather than a second and they need the real endpoint to answer — neither of
# which belongs in a suite whose whole value is being hermetic and fast.
#
# They exist because no unit test renders anything. A cell that computes a
# perfect VoiceOver label and never applies it passes every test in the other
# target and is silent on a device; this is what would catch that.
#
#     ./Scripts/test-accessibility.sh
#
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"

echo "=== Accessibility UI tests — $SIM_UDID_IPHONE on $SIM_RUNTIME ==="
echo "These drive a launched app against the live endpoint. A failure here may"
echo "mean the labels are gone, or only that the Township is not answering."
echo

# Cleared so the run starts from the empty state and walks in through the
# picker, which is the path the tests assert works.
xcrun simctl spawn "$SIM_UDID_IPHONE" defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true

xcodebuild test \
  -project "$CW_PROJECT" \
  -scheme "$CW_SCHEME" \
  -destination "id=$SIM_UDID_IPHONE" \
  -only-testing:CourtWatchUITests \
  "$@"
