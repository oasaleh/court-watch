#!/usr/bin/env bash
#
# Run the suite against a simulator forced into 24-hour time.
#
#     ./Scripts/test-24h.sh
#
# The app must show "2:00 PM" on a device set to 24-hour time. Proving that
# needs a genuinely hostile device, so this script changes a real setting on a
# real simulator rather than simulating one in-process.
#
# Two things keep the gate honest:
#
#   1. The preference is read back after writing, and the run is abandoned if
#      it did not take. Testing a device that was never made hostile would
#      pass while proving nothing.
#   2. The suite itself carries a control that asserts the device rendered
#      "14:00". If the override silently stops working, that control fails and
#      names the premise as the thing that broke.
#
# The setting is always restored, including when the suite fails.
#
# This targets one device on purpose. The question is locale rendering, not
# layout, so a second device family would double the runtime for no signal.

set -euo pipefail
# shellcheck source=Scripts/env.sh
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"

PREF_DOMAIN=".GlobalPreferences"
PREF_KEY="AppleICUForce24HourTime"

read_pref() {
  xcrun simctl spawn "$SIM_UDID" defaults read "$PREF_DOMAIN" "$PREF_KEY" 2>/dev/null || echo 0
}

restore_pref() {
  xcrun simctl spawn "$SIM_UDID" defaults write "$PREF_DOMAIN" "$PREF_KEY" -bool false >/dev/null 2>&1 || true
  echo "Restored $PREF_KEY to $(read_pref) on $SIM_UDID"
}

echo "Booting $SIM_IPHONE_NAME — $SIM_UDID on $SIM_RUNTIME"
xcrun simctl bootstatus "$SIM_UDID" -b

# Installed before the first write, so no failure path can leave the machine
# in 24-hour time.
trap restore_pref EXIT

xcrun simctl spawn "$SIM_UDID" defaults write "$PREF_DOMAIN" "$PREF_KEY" -bool true

actual="$(read_pref)"
if [ "$actual" != "1" ]; then
  echo "test-24h.sh: could not force 24-hour time on $SIM_UDID (read back '$actual')." >&2
  echo "             Refusing to run: the suite would pass without proving anything." >&2
  exit 1
fi
echo "$PREF_KEY = 1 on $SIM_UDID"

# xcodebuild forwards TEST_RUNNER_-prefixed variables to the test process with
# the prefix stripped, so the suite sees COURTWATCH_EXPECT_24H=1 and arms its
# control.
export TEST_RUNNER_COURTWATCH_EXPECT_24H=1

SIM_ONLY=iphone "$CW_ROOT/Scripts/test.sh" "$@"
