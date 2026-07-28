# Court Watch — Screens

Tennis court availability for The Woodlands Township, on iOS 26.

Every shot is from the real app against the live availability endpoint, captured
on an iPhone 17 Pro simulator. Reproduce them with:

```bash
./Scripts/capture-screenshots.sh
```

The clock is pinned per shot so the whole day is visible — the app normally hides
hours that have already ended, which would make most of these two cells wide.

---

## The day, unfiltered

Every court at your chosen facilities, all sixteen hours, no horizontal
scrolling. The header answers the question before you read a single cell:
**2 of 5 free at 7 AM**.

Green is open, red is taken. The hour ruler labels every few columns — the stride
is computed from the measured cell width, so raising the text size thins the
labels out rather than letting them collide.

| Light | Dark |
|---|---|
| ![Unfiltered, light](screenshots/day-now-light.png) | ![Unfiltered, dark](screenshots/day-now-dark.png) |

---

## Filtered from 1 PM

Choosing an hour narrows the day. The active filter is named in the toolbar
control that sets it, so a quiet-looking afternoon can never be mistaken for a
fully booked one.

Picking an hour is treated as an instruction rather than a preference: it reaches
back past the current time if you ask it to, and the app never claims the day is
over while a filter is set.

| Light | Dark |
|---|---|
| ![From 1 PM, light](screenshots/day-from-1pm-light.png) | ![From 1 PM, dark](screenshots/day-from-1pm-dark.png) |

---

## Filtered from 6 PM

Fewer columns means wider cells, so each one writes its own hour and the ruler
steps aside. Same data, same rules — only the width changed.

| Light | Dark |
|---|---|
| ![From 6 PM, light](screenshots/day-from-6pm-light.png) | ![From 6 PM, dark](screenshots/day-from-6pm-dark.png) |

---

## Late in the day

Unfiltered at 8:15 PM. Only the hours still to come are shown, and a slot lives
until its hour *ends* — at 8:15 the 8 PM row is still there, because a court free
until 9 is still worth walking to.

| Light | Dark |
|---|---|
| ![Evening, light](screenshots/evening-light.png) | ![Evening, dark](screenshots/evening-dark.png) |

---

## Choosing facilities

Twenty-seven facilities, eighty courts. You pick **places**, not court numbers —
choosing Shadowbend shows all five of its courts.

Search folds apostrophes on both sides, so `Harper's` typed on the software
keyboard finds `Harper's Landing Tennis Court` even though iOS inserts a curly
apostrophe and the data holds a straight one.

| Light | Dark |
|---|---|
| ![Facility picker, light](screenshots/facility-picker-light.png) | ![Facility picker, dark](screenshots/facility-picker-dark.png) |

---

## Notes on the design

**Colour is the primary channel, but never the only one.** With iOS's
*Differentiate Without Color* enabled, the fills give way to solid, outlined and
hatched treatments plus symbols — three different amounts of ink, which survive
greyscale and every form of colour blindness.

**Times are always 12-hour**, even on a device set to 24-hour time, and always in
US Central regardless of where the phone is. Minutes are dropped from the hourly
slots (`10 PM`) but kept on timestamps (`Updated 10:17 PM`), where they carry
information.

**Nothing here requires signing in.** Availability was measured to be identical
signed in and out — 0 of 80 courts differed across 1,280 slots — so the account
screen is entirely optional.
