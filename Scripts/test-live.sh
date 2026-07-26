#!/usr/bin/env bash
#
# Run the one live check against the real availability endpoint.
#
#     ./Scripts/test-live.sh
#
# This makes REAL REQUESTS to a public system that belongs to The Woodlands
# Township, fronted by an F5 ASM web application firewall. It is not part of
# any gate, no other script calls it, and nothing runs it automatically. Run it
# deliberately, rarely, and when you actually want to know whether the API has
# changed — not as a habit.
#
# One device only. This checks the network contract, not layout, so running it
# on a second simulator would double the load on someone else's server for no
# additional signal.
#
# The rest of the suite is hermetic and stays that way: the live test is
# disabled unless COURTWATCH_LIVE=1 reaches the test process. xcodebuild strips
# the TEST_RUNNER_ prefix when forwarding an environment variable into the
# runner, which is why it is spelled that way below.

set -euo pipefail
# shellcheck source=Scripts/env.sh
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"

echo "Running the live availability check against the real endpoint."
echo "This makes real requests to a public system. One run, one device."
echo

SIM_ONLY=iphone TEST_RUNNER_COURTWATCH_LIVE=1 \
  exec "$(dirname "${BASH_SOURCE[0]}")/test.sh" "$@"
