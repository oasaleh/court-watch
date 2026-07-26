#!/usr/bin/env bash
#
# Build the app for the simulator.
#
#     ./Scripts/build.sh
#
# Extra arguments are passed through to xcodebuild.
#
# The generic destination is deliberate: a plain build needs no booted device,
# and one pass covers both device families.

set -euo pipefail
# shellcheck source=Scripts/env.sh
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"

echo "Building $CW_SCHEME for generic/platform=iOS Simulator"

exec xcodebuild build \
  -project "$CW_PROJECT" \
  -scheme "$CW_SCHEME" \
  -destination 'generic/platform=iOS Simulator' \
  "$@"
