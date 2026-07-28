# The app icon

Two layers, ready to drag into Icon Composer:

| File | What it is |
|---|---|
| `1-Court.svg` | The court: doubles boundary, singles sidelines, service lines |
| `2-Net.svg` | The net, on its own plane so it can sit above the court |

Both are 1024 × 1024, white shapes on a transparent canvas, built as filled
rectangles rather than strokes. There is deliberately **no background, no
gradient and no shadow** in either file — Apple asks for those to be left out
so they can be set on the Liquid Glass material instead, where you can see
what they do across every appearance at once.

## Making the icon

**1. Open the tool.** In Xcode: *Xcode ▸ Open Developer Tool ▸ Icon Composer*.

**2. Name it `AppIcon`.** *File ▸ Save*, into this folder, as `AppIcon`. The
name matters: the target's App Icon setting is already `AppIcon`, so matching
it means nothing else has to change.

**3. Drag both SVGs into the left sidebar.** They land as two layers. Order is
back to front, so `1-Court` belongs underneath `2-Net`; the leading numbers
are there to make that ordering survive an alphabetical import.

**4. Set the background.** Select the **topmost row in the sidebar — the icon's
own filename**, above every group. This is the only thing that carries the
background; a group offers just Opacity and Blend Mode, and a layer's fill
recolours that shape rather than what sits behind it. If the inspector is
showing a *Mode* control reading Individual or Combined, you have a group
selected, not the icon.

With the icon selected, open the Appearance inspector, set Color to *All* and
Fill to *Gradient*. A court blue reads well and, unlike green, cannot be
confused with the green and red the grid itself uses to mean free and booked:

- from `#4082D0` at the top
- to `#1E549E` at the bottom

**5. Leave the layers white.** Select each layer in turn; their Fill stays
*Automatic*, which picks the white up from the SVG. That is also what makes the
mono and tinted variants come out right, since those are derived from
luminance.

**6. Give the net some height.** Select `2-Net`, and under Liquid Glass raise
its shadow or translucency a little relative to the court. Only a little — the
net standing very slightly proud of the surface is what keeps the mark from
reading as a window frame.

**7. Check every variant.** Use the controls under the canvas to step through
Default, Dark, Clear and Mono on iOS. Mono is the one that usually needs
attention: it throws away colour entirely, so anything relying on the blue to
separate it from the background will disappear.

**8. Check it small.** Set the preview size to the smallest offered. If the
doubles alleys close up, widen them in `1-Court.svg` — the two long lines at
`y="343"` and `y="653"` are the ones to move.

## Putting it in the app

Drag `AppIcon.icon` into the Project navigator, into the `CourtWatch` group,
with *Copy items if needed* ticked and the `CourtWatch` target checked.

Nothing else needs changing. `ASSETCATALOG_COMPILER_APPICON_NAME` is already
`AppIcon`, and Xcode uses an Icon Composer file in preference to an asset
catalog of the same name. `Assets.xcassets/AppIcon.appiconset` can then be
deleted; it is empty anyway, which is why the app currently launches with a
blank white tile.

## Editing it later

Select `AppIcon.icon` in the Project navigator and click *Open with Icon
Composer* under the preview. The SVGs here stay the source of truth for the
geometry: change one, then use *Replace* under Composition in the Appearance
inspector to point the layer at the updated file.
