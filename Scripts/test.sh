#!/usr/bin/env bash
#
# Run the unit test suite on the iPhone and the iPad simulator.
#
#     ./Scripts/test.sh                   both device families
#     SIM_ONLY=iphone ./Scripts/test.sh   iPhone only
#     SIM_ONLY=ipad   ./Scripts/test.sh   iPad only
#
# Extra arguments are passed through to xcodebuild.
#
# Reading the output correctly matters here. A fully green Swift Testing run
# still prints:
#
#     Executed 0 tests, with 0 failures (0 unexpected) in 0.000 seconds
#
# That line comes from the XCTest harness and says nothing about Swift Testing.
# Gating on it reports success for a suite that never ran. The trustworthy
# signals are the "Test run with N tests ... passed" line and the exit status:
# 0 passed, 65 a test failed, 66 the scheme has no working test action.

set -euo pipefail
# shellcheck source=Scripts/env.sh
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"

LABELS=()
UDIDS=()
case "${SIM_ONLY:-both}" in
  iphone) LABELS=("iPhone"); UDIDS=("$SIM_UDID_IPHONE") ;;
  ipad)   LABELS=("iPad");   UDIDS=("$SIM_UDID_IPAD") ;;
  both)   LABELS=("iPhone" "iPad"); UDIDS=("$SIM_UDID_IPHONE" "$SIM_UDID_IPAD") ;;
  *)
    echo "test.sh: SIM_ONLY must be iphone, ipad or both (got '${SIM_ONLY}')" >&2
    exit 2
    ;;
esac

# How many test functions exist on disk.
#
# Commented-out lines are dropped first so that prose mentioning the attribute
# cannot inflate the count. A parameterized test counts once, matching how the
# summary line reports it.
DECLARED="$(
  cat "$CW_ROOT"/CourtWatchTests/*.swift 2>/dev/null \
    | grep -vE '^[[:space:]]*//' \
    | grep -cE '(^|[[:space:]])@Test([[:space:]]|\(|$)' \
    || true
)"

echo "$DECLARED @Test function(s) declared in CourtWatchTests/"

failed=0

for i in "${!UDIDS[@]}"; do
  label="${LABELS[$i]}"
  udid="${UDIDS[$i]}"
  log="$(mktemp -t "courtwatch-test-${label}")"

  echo
  echo "=== $label — $udid on $SIM_RUNTIME ==="

  set +e
  # The UI tests are held out of this run. They drive a launched app against
  # the real endpoint, so they are neither hermetic nor quick, and this suite
  # is both by design. Scripts/test-accessibility.sh runs them on purpose.
  xcodebuild test \
    -project "$CW_PROJECT" \
    -scheme "$CW_SCHEME" \
    -destination "id=$udid" \
    -skip-testing:CourtWatchUITests \
    "$@" 2>&1 | tee "$log"
  rc=${PIPESTATUS[0]}
  set -e

  if [ "$rc" -ne 0 ]; then
    echo "FAIL: the suite failed on $label ($udid), xcodebuild exit $rc" >&2
    echo "      Full log: $log" >&2
    failed=1
    continue
  fi

  # Count the tests, not the suites: tests declared inside a struct report as
  # "N tests in 1 suite", and the suite number drifts as files are added.
  ran="$(grep -oE 'Test run with [0-9]+ test' "$log" | grep -oE '[0-9]+' | tail -1)"

  if [ -z "$ran" ]; then
    echo "FAIL: no 'Test run with N tests ... passed' line on $label." >&2
    echo "      The Swift Testing suite did not run. Full log: $log" >&2
    failed=1
    continue
  fi

  if [ "$ran" != "$DECLARED" ]; then
    echo "FAIL: $label ran $ran test(s) but $DECLARED are declared on disk." >&2
    echo "      A test file is probably not reaching the test target." >&2
    echo "      Full log: $log" >&2
    failed=1
    continue
  fi

  echo "OK: $label ran $ran test(s), matching the $DECLARED declared on disk"
  rm -f "$log"
done

exit "$failed"
