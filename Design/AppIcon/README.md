# Liftly iOS 27 App Icon Package

This folder contains the complete editable source and the ready-to-use Apple
Icon Composer document for Liftly's layered Liquid Glass app icon.

## Ready-to-use file

- `AppIcon.icon` — the production Icon Composer document. It contains seven
  full-canvas SVG layers organized into four physical depth groups and is set
  up for the iOS 27 design generation.

Open this file directly in Icon Composer to inspect or tune the material. The
file already includes:

- Automatic blue gradient background based on Liftly's brand blue.
- Automatic vertical specular highlights.
- Individual glass treatment for each physical dumbbell component.
- Refraction with increasing strength and elevation from back to front.
- Controlled translucency so the dumbbell remains legible at small sizes.
- Neutral system shadows.
- Automatic Default, Dark, Mono, clear, and tinted rendering.

## Layer stack

All source SVGs use a 1024 × 1024 canvas. Do not crop them before importing;
their full-canvas coordinates preserve alignment.

| Back to front | Source layer(s) | Icon Composer group |
| --- | --- | --- |
| Background | Composer-generated brand gradient | Icon background |
| Bar | `Sources/01-bar.svg` | Bar |
| Rear plates | `Sources/02-rear-left.svg`, `Sources/02-rear-right.svg` | Rear Plates |
| Middle plates | `Sources/03-middle-left.svg`, `Sources/03-middle-right.svg` | Middle Plates |
| Front plates | `Sources/04-front-left.svg`, `Sources/04-front-right.svg` | Front Plates |

`Sources/00-background.svg` is an optional full-bleed reference background for
non-Apple mockups. The production `.icon` uses Icon Composer's adaptive
background instead.

## Material settings

These values are already stored in `AppIcon.icon` and were verified by
reopening the document in Icon Composer.

| Group | Refraction strength | Height | Translucency | Shadow |
| --- | ---: | ---: | ---: | ---: |
| Bar | 28% | 4% | 14% | Neutral 12.5% |
| Rear Plates | 34% | 8% | 26% | Neutral 13.5% |
| Middle Plates | 42% | 12% | 21% | Neutral 14.5% |
| Front Plates | 50% | 16% | 16% | Neutral 16% |

All groups use **Individual** mode, **Automatic** specular highlights, and no
additional blur. Icon Composer's iOS 27 renderer supplies the final edge,
shadow, translucency, and refraction behavior.

## Preview files

- `Preview/AppIcon-iOS27-Default-1024.png` — native Icon Composer Default export.
- `Preview/AppIcon-iOS27-Dark-1024.png` — native Icon Composer Dark export.
- `Preview/AppIcon Exports/` — all six native appearances: Default, Dark,
  Clear Light, Clear Dark, Tinted Light, and Tinted Dark.
- `Preview/LiftlyIcon-liquid-preview.svg` — editable marketing-style concept
  preview with a richer radial background.
- `Preview/LiftlyIcon-liquid-preview.png` — flattened version of the concept
  preview.
- `LiftlyIcon-composition.svg` — clean combined vector composition without an
  app-icon mask or system glass effects.

The Icon Composer exports are authoritative for how Apple renders the icon.
The marketing-style SVG is only a static visual reference.

## Add the icon to Xcode

The project currently uses `Rack/Assets.xcassets/AppIcon.appiconset`, which has
the same app-icon name and will conflict with `AppIcon.icon`.

1. In Xcode, rename the existing asset set from `AppIcon` to `LegacyAppIcon`
   or remove it from the asset catalog after preserving it in source control.
2. Drag `Design/AppIcon/AppIcon.icon` into the Rack project navigator as a
   normal resource.
3. Enable target membership for the `Rack` target.
4. In the target's app-icon setting, select `AppIcon`. The project already uses
   `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`, so the names match.
5. Build with the current Xcode and inspect the app on an iOS 27 simulator and
   physical device in Default, Dark, Clear, and Tinted Home Screen modes.

Do not copy the individual source SVG files into the app target. They are
design sources only; `AppIcon.icon` packages its own copies under `Assets/`.

## Editing later

Open `AppIcon.icon` in Icon Composer and make changes there. Keep the source
SVGs free of masks, baked shadows, borders, glows, blur, or translucency. If a
shape changes, update its SVG and replace the corresponding image layer in
Icon Composer so Apple's renderer continues to own the Liquid Glass material.
