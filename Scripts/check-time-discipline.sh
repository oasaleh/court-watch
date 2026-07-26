#!/usr/bin/env bash
#
# Fail the build if date handling leaks out of CourtTime.swift.
#
# The tests prove today's code is correct. This guards tomorrow's: the APIs
# that break 12-hour display and non-Gregorian parsing are the ones a
# developer reaches for first, and both fail silently on a machine configured
# the way the developer's own machine is configured. A future screen picking
# one up would look fine in review and be wrong on a user's device.
#
#     ./Scripts/check-time-discipline.sh
#
# Exit 0 when the app target is clean, 1 when something outside CourtTime.swift
# builds its own date handling.

set -euo pipefail

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Only the app target is scanned.
#
# The test target is excluded on purpose: its controls are deliberately built
# the wrong way, because proving the pinned path is right requires rendering
# the unpinned one alongside it. Scripts/ is excluded because a scan of this
# directory would match this file.
SCAN_ROOT="CourtWatch"

# The one file allowed to do this. It exists so that nowhere else has to.
ALLOWED="CourtWatch/Support/CourtTime.swift"

# The identifiers being searched for are assembled here rather than written
# out, so that widening the scan root by mistake cannot make this script
# report itself.
_date="Date"
_formatter="Formatter"
_style="FormatStyle"
_convenience="formatted"

PATTERN="${_date}${_formatter}\\(|${_date}\\.${_style}|\\.${_convenience}\\("

# grep exits 1 when it finds nothing, which is the success case here, so the
# pipeline is allowed to fail without taking the script down with it.
OFFENDERS="$(
  grep -rnE "$PATTERN" --include='*.swift' "$SCAN_ROOT" 2>/dev/null \
    | grep -vE '^[^:]+:[0-9]+:[[:space:]]*//' \
    | grep -vE "^${ALLOWED//./\\.}:" \
    || true
)"

if [ -n "$OFFENDERS" ]; then
  echo "Date handling found outside $ALLOWED:" >&2
  echo >&2
  while IFS= read -r match; do
    [ -z "$match" ] && continue
    file="${match%%:*}"
    rest="${match#*:}"
    lineno="${rest%%:*}"
    code="${rest#*:}"
    printf '  %s:%s\n      %s\n' "$file" "$lineno" \
      "$(printf '%s' "$code" | sed 's/^[[:space:]]*//')" >&2
  done <<<"$OFFENDERS"
  echo >&2
  echo "Every date and time conversion belongs in $ALLOWED." >&2
  echo "Formatters built anywhere else pick up the device's locale, which" >&2
  echo "renders afternoon slots as 24-hour times and can shift parsed dates" >&2
  echo "by centuries. Add what you need to CourtTime and call that instead." >&2
  exit 1
fi

echo "Date handling is confined to $ALLOWED"
