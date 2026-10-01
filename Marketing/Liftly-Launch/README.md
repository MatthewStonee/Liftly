# Liftly — Make every set count

A 24-second vertical marketing video at 1080 × 1920, 30 fps, with an original instrumental score. The copy remains understandable with sound off.

## Deliverables

- `Liftly-Marketing-Vertical.mp4` — final video with music.
- `liftly-silent.mp4` — silent master for alternate audio.
- `review/` — storyboard frames, decoded final-video frames, and technical verification.
- `source/` — editable native Swift renderer, audio synthesis script, and export script.
- `assets/` — original icon copy, source-derived dumbbell geometry, real simulator screenshots, and original score.

## Edit

| Time | Story |
| --- | --- |
| 0–4 s | Original icon reveal; “Make every set count.” |
| 4–9 s | Workout programming: programs, workout days, and exercises. The seven original SVG components assemble into the dumbbell mark. |
| 9–14 s | Actual Log Set screen; “Log it. Keep moving.” |
| 14–20 s | Actual exercise progress screen with a slow push in; “See your strength grow.” |
| 20–24 s | Liftly brand card; “Make every set count.” |

## Asset provenance

- Icon: `Design/AppIcon/Preview/AppIcon-iOS27-Default-1024.png`, copied unchanged to `assets/liftly-icon.png`.
- Dumbbell: all seven `Design/AppIcon/Sources/01-*` through `04-*` SVG layers. `assets/dumbbell-layers.json` preserves their rectangle geometry, radii, colors, and source paths for the renderer.
- Navy backdrop and blue accent follow the current app background and icon assets.
- Screenshots: the current `Rack` scheme built with XcodeBuildMCP, running on iPhone 18 Pro / iOS 27. Screens captured at 1206 × 2622 using the existing isolated `history` fixture, ID `marketing-20260929`. They show synthetic demo data, labeled in the video. No production workout store was used.
- The phone surround and all title graphics are marketing compositions. The planning chapter is explanatory typography; the logging and progress screens are authentic captures.
- Music: generated locally by `source/score.py`, using sine waves and seeded noise. No sampled recordings, licensed stock tracks, or voiceover.

The current source and README support the advertised features. No App Store listing, launch date, price, coaching, or guaranteed fitness outcome is claimed.

## Re-render

From the repository root, on macOS with the Swift toolchain and Python + NumPy:

```sh
python3 Marketing/Liftly-Launch/source/score.py
swiftc -module-cache-path /tmp/liftly-swift-cache -O Marketing/Liftly-Launch/source/render.swift -o /tmp/liftly-render
/tmp/liftly-render "$PWD/Marketing/Liftly-Launch"
swiftc -parse-as-library -module-cache-path /tmp/liftly-swift-cache -O Marketing/Liftly-Launch/source/finalize.swift -o /tmp/liftly-finalize
/tmp/liftly-finalize "$PWD/Marketing/Liftly-Launch"
```

Use `--preview` with the renderer to generate the five storyboard frames only. Re-rendering needs no simulator; the captured assets are included. `source/capture.py` records the local XcodeBuildMCP capture helper used during production and is machine-specific. It takes an accessibility snapshot before and after every tap, which stalls the app for up to ~1.4 s per interaction, so record footage where timing shows with plain taps (see `Benchmarks/2026-09-30-add-exercise-and-progress-latency.md`).

No app source, schema, project settings, or test targets were changed. The simulator build succeeded; no app tests were needed for these standalone marketing artifacts. The renderer and export are verified separately in `review/verification.txt`.
