# The app icon

The icon itself is `CourtWatch/AppIcon.icon`, an Icon Composer file. This
folder holds the artwork it is built from, and the notes for rebuilding it.

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

**2. Name it `AppIcon`.** *File ▸ Save*, as `AppIcon`, into the `CourtWatch/`
source folder — see *Putting it in the app* below for why the location
matters. The name matters too: the target's App Icon setting is already
`AppIcon`, so matching it means nothing else has to change.

**3. Drag both SVGs into the left sidebar.** They arrive as two layers inside a
single default group.

**4. Put each layer in its own group.** This is the step that matters, and it
is not optional: **depth comes from groups, not from layers.** Apple renders
one group per plane, back to front, and a layer has no material of its own —
select one and its whole Liquid Glass section is a single *Effects* switch,
with no shadow to reach for.

Click the Add button (**+**) at the bottom of the sidebar and choose *New
Group*. Drag `2-Net` into it. Double-click each group to rename them `Court`
and `Net`, and make sure `Net` sits above `Court` in the list — the sidebar
order is the z-order. Two groups is well inside the limit of four.

**5. Set the background.** Select the **topmost row in the sidebar — the icon's
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

**6. Leave the layers white.** Select each layer in turn; their Fill stays
*Automatic*, which picks the white up from the SVG. That is also what makes the
mono and tinted variants come out right, since those are derived from
luminance.

**7. Give the net some height.** Select the **`Net` group** — not the layer
inside it — and under Liquid Glass raise its Shadow relative to the `Court`
group. Only a little: the net standing very slightly proud of the surface is
what keeps the mark from reading as a window frame, and too much turns it into
a bar hovering over a diagram.

**8. Check every variant.** Use the controls under the canvas to step through
Default, Dark, Clear and Mono on iOS. Mono is the one that usually needs
attention: it throws away colour entirely, so anything relying on the blue to
separate it from the background will disappear.

**9. Check it small.** Set the preview size to the smallest offered. If the
doubles alleys close up, widen them in `1-Court.svg` — the two long lines at
`y="343"` and `y="653"` are the ones to move.

## Putting it in the app

Save the Icon Composer file as `AppIcon.icon` **inside the `CourtWatch/` source
folder** — the one holding `CourtWatchApp.swift` — and not inside
`Assets.xcassets`.

That distinction is the whole of it. An `.icon` file is a package: a folder
holding `icon.json` and an `Assets/` directory. Dropping it into the asset
catalogue looks right and quietly fails, because the catalogue takes the
package apart into loose image sets and a data set, leaving nothing the system
recognises as an icon. The app then launches with a blank white tile and no
warning anywhere to say why.

Nothing else needs doing. The target uses a file-system synchronized group, so
a file placed in `CourtWatch/` is in the build already, and
`ASSETCATALOG_COMPILER_APPICON_NAME` is `AppIcon`, which the filename matches.

To check it worked, build and look inside the product: `AppIcon60x60@2x.png`
and friends should be sitting at the top level of `CourtWatch.app`. If they
are missing, the icon did not compile, whatever the canvas in Xcode shows.

## Editing it later

Select `AppIcon.icon` in the Project navigator and click *Open with Icon
Composer* under the preview. The SVGs here stay the source of truth for the
geometry: change one, then use *Replace* under Composition in the Appearance
inspector to point the layer at the updated file.

Note that Icon Composer copies the artwork into the package when you import
it, so `CourtWatch/AppIcon.icon/Assets/` holds its own copy of each SVG. The
two are only in step because a change is put through both.
