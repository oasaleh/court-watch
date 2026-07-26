#!/usr/bin/env bash
#
# Shared environment for the CourtWatch build and test scripts.
# Source this file; do not execute it:
#
#     source Scripts/env.sh
#
# Exports:
#   DEVELOPER_DIR    full Xcode toolchain
#   CW_ROOT          repository root
#   CW_PROJECT       path to CourtWatch.xcodeproj
#   CW_SCHEME        shared scheme name
#   SIM_RUNTIME      the single iOS 26 runtime all destinations resolve within
#   SIM_UDID_IPHONE  iPhone simulator UDID on that runtime
#   SIM_UDID_IPAD    iPad simulator UDID on that runtime
#   SIM_UDID         default single-device target (the iPhone)
#   BUNDLE_ID        product bundle identifier, read from the build settings
#
# Device names may be overridden before sourcing:
#   SIM_IPHONE_NAME="iPhone 17" source Scripts/env.sh

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  echo "env.sh is meant to be sourced, not executed: source Scripts/env.sh" >&2
  exit 1
fi

# xcode-select points at the Command Line Tools on this machine, which cannot
# build for the simulator. Point every xcodebuild/xcrun call at the full Xcode
# instead. This is why no script here calls xcodebuild without sourcing env.sh.
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

CW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CW_PROJECT="$CW_ROOT/CourtWatch.xcodeproj"
CW_SCHEME="CourtWatch"
export CW_ROOT CW_PROJECT CW_SCHEME

SIM_IPHONE_NAME="${SIM_IPHONE_NAME:-iPhone 17 Pro}"
SIM_IPAD_NAME="${SIM_IPAD_NAME:-iPad Pro 13-inch (M5)}"
export SIM_IPHONE_NAME SIM_IPAD_NAME

# Pick one runtime first, then resolve devices inside it.
#
# More than one iOS 26 runtime is typically installed, and device names repeat
# across them -- "iPhone 17 Pro" currently exists three times. A destination
# given by name alone therefore picks an arbitrary machine, which is fatal for
# the 24-hour gate, where the device whose settings were changed must be the
# device the tests run on.
#
# Sort numerically on the version components, not lexically: a future "26.10"
# sorts below "26.2" as text.
SIM_RUNTIME="$(xcrun simctl list runtimes -j | jq -r '
  [.runtimes[] | select(.isAvailable and (.identifier | test("SimRuntime.iOS-26")))]
  | sort_by(.version | split(".") | map(tonumber))
  | last
  | .identifier // empty')"

if [ -z "$SIM_RUNTIME" ]; then
  echo "env.sh: no available iOS 26 simulator runtime found." >&2
  echo "        Install one from Xcode > Settings > Components." >&2
  return 1
fi
export SIM_RUNTIME

_cw_udid_for() {
  xcrun simctl list devices available -j \
    | jq -r --arg rt "$SIM_RUNTIME" --arg name "$1" \
        '.devices[$rt] // [] | map(select(.name == $name)) | .[0].udid // empty'
}

SIM_UDID_IPHONE="$(_cw_udid_for "$SIM_IPHONE_NAME")"
if [ -z "$SIM_UDID_IPHONE" ]; then
  echo "env.sh: no simulator named '$SIM_IPHONE_NAME' on runtime $SIM_RUNTIME." >&2
  echo "        Create one in Xcode, or set SIM_IPHONE_NAME to a device that exists." >&2
  unset -f _cw_udid_for
  return 1
fi

SIM_UDID_IPAD="$(_cw_udid_for "$SIM_IPAD_NAME")"
if [ -z "$SIM_UDID_IPAD" ]; then
  echo "env.sh: no simulator named '$SIM_IPAD_NAME' on runtime $SIM_RUNTIME." >&2
  echo "        Create one in Xcode, or set SIM_IPAD_NAME to a device that exists." >&2
  unset -f _cw_udid_for
  return 1
fi

unset -f _cw_udid_for

# Default single-device target. The time-sensitive gates care about locale
# rendering rather than layout, so they run on one machine.
SIM_UDID="$SIM_UDID_IPHONE"
export SIM_UDID_IPHONE SIM_UDID_IPAD SIM_UDID

# Read rather than hardcode, so renaming the bundle never desynchronises the
# scripts. The leading-space anchor keeps this from matching
# DERIVE_MACCATALYST_PRODUCT_BUNDLE_IDENTIFIER.
BUNDLE_ID="$(xcodebuild -project "$CW_PROJECT" -target "$CW_SCHEME" -showBuildSettings 2>/dev/null \
  | awk -F' = ' '$1 ~ /^[[:space:]]*PRODUCT_BUNDLE_IDENTIFIER$/ { print $2; exit }')"

if [ -z "$BUNDLE_ID" ]; then
  echo "env.sh: could not read PRODUCT_BUNDLE_IDENTIFIER from $CW_PROJECT." >&2
  return 1
fi
export BUNDLE_ID
