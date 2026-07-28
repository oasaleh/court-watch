#!/usr/bin/env bash
#
# Captures the screenshots used by docs/SCREENSHOTS.md.
#
# The app has no way to be driven from the command line — simctl cannot tap — so
# each shot is produced by temporarily patching the initial state, building, and
# launching straight into it. Every patch is reverted before the next one, and
# the sources are restored from git at the end whatever happens.
#
#     ./Scripts/capture-screenshots.sh
#
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"

CV="CourtWatch/ContentView.swift"
APP_FILE="CourtWatch/CourtWatchApp.swift"
OUT="docs/screenshots"
BUNDLE="${BUNDLE_ID:-com.karkand.CourtWatch}"

mkdir -p "$OUT"

restore() {
  git checkout -- "$CV" "$APP_FILE" 2>/dev/null || true
}
trap restore EXIT

pin_clock() {           # pin_clock <hour> <minute>
  python3 - "$1" "$2" <<'PY'
import sys, pathlib
hour, minute = sys.argv[1], sys.argv[2]
p = pathlib.Path("CourtWatch/CourtWatchApp.swift")
s = p.read_text()
old = "            ContentView(session: session, account: account, favorites: favorites)"
new = f"""            ContentView(
                session: session, account: account, favorites: favorites,
                clock: FixedClock(
                    now: CourtTime.calendar.date(
                        bySettingHour: {hour}, minute: {minute}, second: 0,
                        of: Date()) ?? Date()))"""
assert old in s, "clock anchor missing"
p.write_text(s.replace(old, new))
PY
}

set_filter() {          # set_filter <HH:MM:SS>
  python3 - "$1" <<'PY'
import sys, pathlib
api = sys.argv[1]
p = pathlib.Path("CourtWatch/ContentView.swift")
s = p.read_text()
old = "    @State private var filter = StartTimeFilter.fromNow"
new = ('    @State private var filter = StartTimeFilter('
       f'start: SlotTime(apiString: "{api}"))')
assert old in s, "filter anchor missing"
p.write_text(s.replace(old, new))
PY
}

open_picker() {
  python3 - <<'PY'
import pathlib
p = pathlib.Path("CourtWatch/ContentView.swift")
s = p.read_text()
old = "    @State private var isChoosingFacilities = false"
assert old in s, "picker anchor missing"
p.write_text(s.replace(old, "    @State private var isChoosingFacilities = true"))
PY
}

shoot() {               # shoot <name>
  "$CW_ROOT/Scripts/build.sh" >/dev/null 2>&1

  local app
  app=$(ls -dt ~/Library/Developer/Xcode/DerivedData/CourtWatch-*/Build/Products/Debug-iphonesimulator/CourtWatch.app | head -1)

  for mode in light dark; do
    xcrun simctl ui "$SIM_UDID_IPHONE" appearance "$mode" >/dev/null
    xcrun simctl terminate "$SIM_UDID_IPHONE" "$BUNDLE" >/dev/null 2>&1 || true
    sleep 1
    xcrun simctl install "$SIM_UDID_IPHONE" "$app" >/dev/null
    xcrun simctl launch "$SIM_UDID_IPHONE" "$BUNDLE" >/dev/null
    sleep 9
    xcrun simctl io "$SIM_UDID_IPHONE" screenshot "$OUT/$1-$mode.png" >/dev/null 2>&1
    echo "  $1-$mode.png"
  done
}

xcrun simctl bootstatus "$SIM_UDID_IPHONE" -b >/dev/null 2>&1

echo "Whole day, no filter:"
restore; pin_clock 6 30;                    shoot "day-now"

echo "Filtered from 1 PM:"
restore; pin_clock 6 30; set_filter "13:00:00"; shoot "day-from-1pm"

echo "Filtered from 6 PM:"
restore; pin_clock 6 30; set_filter "18:00:00"; shoot "day-from-6pm"

echo "Evening, few slots left:"
restore; pin_clock 20 15;                   shoot "evening"

echo "Facility picker:"
restore; pin_clock 6 30; open_picker;       shoot "facility-picker"

echo
echo "Done. Sources restored; simulator left in light mode."
xcrun simctl ui "$SIM_UDID_IPHONE" appearance light >/dev/null
