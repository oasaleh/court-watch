#!/usr/bin/env bash
#
# Captures the accessibility and layout states that no test can observe.
#
# The suite proves what the app computes; it never renders a screen, so the
# things that only exist once one is rendered — a colour that cannot be read,
# a label that truncates at the largest text size, a grid that ignores the
# extra width of an iPad — have to be looked at. This script produces the
# pictures to look at, and puts every simulator setting back afterwards.
#
#     ./Scripts/capture-checkpoints.sh
#
# Output lands in docs/checkpoints/, which is gitignored: these are evidence
# for one review, not documentation, and they are large.
#
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"

OUT="$CW_ROOT/docs/checkpoints"
mkdir -p "$OUT"

# Every setting this script touches, restored whatever happens. A simulator
# left at the largest accessibility text size is a confusing thing to find
# later, and worse, it silently changes what the next run of this script sees.
restore_settings() {
  for udid in "$SIM_UDID_IPHONE" "$SIM_UDID_IPAD"; do
    xcrun simctl ui "$udid" appearance light >/dev/null 2>&1 || true
    xcrun simctl ui "$udid" content_size large >/dev/null 2>&1 || true
    xcrun simctl ui "$udid" increase_contrast disabled >/dev/null 2>&1 || true
    xcrun simctl spawn "$udid" defaults write com.apple.Accessibility \
      DifferentiateWithoutColorEnabled -bool false >/dev/null 2>&1 || true
  done
}
trap restore_settings EXIT

# The clock is pinned so the grid is full rather than showing whatever is left
# of the real day. A two-cell screenshot proves nothing about layout.
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

restore_sources() {
  git -C "$CW_ROOT" checkout -- CourtWatch/CourtWatchApp.swift 2>/dev/null || true
}

# Chooses the facilities for the run, so a screenshot never depends on what
# somebody happened to tap on this simulator last.
#
# Written straight into the app's defaults rather than through the picker,
# because simctl cannot tap. The value is what FavoritesStore writes: a JSON
# array of names, as Data, under one key. Three facilities of different sizes
# — two courts, five, eleven — so the grid shows both a short section and a
# long one.
seed_favorites() {      # seed_favorites <udid>
  local udid="$1" encoded
  encoded=$(python3 -c '
import json
names = ["Falconwing Tennis", "Shadowbend Tennis", "Bear Branch Tennis"]
print(json.dumps(sorted(names)).encode().hex())
')

  xcrun simctl spawn "$udid" defaults write "$BUNDLE_ID" \
    favoriteFacilityNames -data "$encoded" >/dev/null 2>&1 || true
}

launch_and_shoot() {    # launch_and_shoot <udid> <name>
  local udid="$1" name="$2" app
  app=$(ls -dt ~/Library/Developer/Xcode/DerivedData/CourtWatch-*/Build/Products/Debug-iphonesimulator/CourtWatch.app | head -1)

  xcrun simctl terminate "$udid" "$BUNDLE_ID" >/dev/null 2>&1 || true
  sleep 1
  xcrun simctl install "$udid" "$app" >/dev/null
  seed_favorites "$udid"
  xcrun simctl launch "$udid" "$BUNDLE_ID" >/dev/null
  sleep 9
  xcrun simctl io "$udid" screenshot "$OUT/$name.png" >/dev/null 2>&1
  echo "  $name.png"
}

echo "Building once…"
restore_sources
pin_clock 6 30
"$CW_ROOT/Scripts/build.sh" >/dev/null 2>&1
restore_sources

for udid in "$SIM_UDID_IPHONE" "$SIM_UDID_IPAD"; do
  xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1
done

echo
echo "Dynamic Type, iPhone:"
for size in large accessibility-medium accessibility-extra-extra-extra-large; do
  xcrun simctl ui "$SIM_UDID_IPHONE" content_size "$size" >/dev/null
  launch_and_shoot "$SIM_UDID_IPHONE" "type-$size"
done
xcrun simctl ui "$SIM_UDID_IPHONE" content_size large >/dev/null

echo
echo "Differentiate Without Color:"
# Set, but do not trust: the simulator writes the preference and reads it back
# correctly, and SwiftUI's environment does not see it — verified by forcing
# the flag in the view, which produces the solid/outlined treatment as
# designed. So these two shots record the *default* rendering at this size,
# and the setting itself has to be exercised from Settings on a device.
for mode in light dark; do
  xcrun simctl ui "$SIM_UDID_IPHONE" appearance "$mode" >/dev/null
  xcrun simctl spawn "$SIM_UDID_IPHONE" defaults write com.apple.Accessibility \
    DifferentiateWithoutColorEnabled -bool true >/dev/null
  launch_and_shoot "$SIM_UDID_IPHONE" "no-colour-$mode"
done
xcrun simctl spawn "$SIM_UDID_IPHONE" defaults write com.apple.Accessibility \
  DifferentiateWithoutColorEnabled -bool false >/dev/null
xcrun simctl ui "$SIM_UDID_IPHONE" appearance light >/dev/null

echo
echo "Increase Contrast:"
for mode in light dark; do
  xcrun simctl ui "$SIM_UDID_IPHONE" appearance "$mode" >/dev/null
  xcrun simctl ui "$SIM_UDID_IPHONE" increase_contrast enabled >/dev/null
  launch_and_shoot "$SIM_UDID_IPHONE" "contrast-$mode"
done
xcrun simctl ui "$SIM_UDID_IPHONE" increase_contrast disabled >/dev/null
xcrun simctl ui "$SIM_UDID_IPHONE" appearance light >/dev/null

echo
echo "iPad, both orientations:"
for mode in light dark; do
  xcrun simctl ui "$SIM_UDID_IPAD" appearance "$mode" >/dev/null
  launch_and_shoot "$SIM_UDID_IPAD" "ipad-$mode"
done
xcrun simctl ui "$SIM_UDID_IPAD" appearance light >/dev/null

echo
echo "Done. Screens in docs/checkpoints/; every simulator setting restored."
