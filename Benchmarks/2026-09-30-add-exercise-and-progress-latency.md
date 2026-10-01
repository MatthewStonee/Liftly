# Add Exercise and Progress latency — 2026-09-30

Device: iPhone 18 Pro simulator, iOS 27.0, Xcode 27.0 (27A266a). Two delays were
seen while recording the marketing video: Add Exercise held its highlight ~1.8 s
before the picker appeared, and Progress showed only its title for ~0.5 s on first
open.

Times come from `PerformanceSignposts` events (`Rack/Shared/PerformanceSignposts.swift`),
streamed with:

```sh
xcrun simctl spawn booted log stream --signpost --style ndjson --predicate 'subsystem == "com.matthewstone.liftly"'
```

Main-thread hangs come from Instruments' Hangs instrument (`xcrun xctrace record
--instrument Hangs --instrument 'Points of Interest' --all-processes`). First frames
come from `simctl io recordVideo`, read at 60 fps. The fixture is
`-LiftlyUITestFixture history <id>`: one exercise with 120 sets, and no exercise library.
Release has no fixtures, so it used the simulator's regular store: the library plus one
test program. Runs vary by hundreds of milliseconds, so these numbers are diagnostic,
not thresholds.

## Progress tab, first open

Before, the tab listed nothing until a `Task` hop and the background stats load had
both finished. Only then could SwiftUI build the list, in a second update.

| Build | Tooling | Appeared → stats start | Stats load | Stats → rows | Title-only screen |
| --- | --- | ---: | ---: | ---: | ---: |
| Debug, fixture | `sample` attached | 272 ms | 49 ms | 527 ms | 848 ms |
| Debug, fixture | Time Profiler | 182 ms | 189 ms | 132 ms | 504 ms |
| Release, 1 exercise | Hangs | 42 ms | 34 ms | 146 ms | 222 ms |

After, `showExercises` lists the rows in `onAppear`, before the first frame. Stats fill
in from the background load, and redacted placeholders cover the gap.

| Build | First Progress frame | Stats shown |
| --- | --- | --- |
| Debug, fixture | Rows with placeholders | 100 ms later |
| Release, 1 exercise | Rows with placeholders | Next frame, 33 ms later |

With the library and two 5-exercise days in Debug, the rows appeared 34 ms after
`Progress appeared`, in the same update, and the stats loaded 31 ms later.

On a store with 20 program exercises and 2,000 sets
(`LargeStoreBenchmarkTests.progressOverviewPhases`), the list phase took 7.6 ms on the
main actor and the stats phase took 30 ms in the background.

## Add Exercise

The table measures tap → the picker's `onAppear`. Before `onAppear`, SwiftUI builds the
sheet's `NavigationStack`. After it, the sheet's first layout and render still hold the
main thread.

| Build | Open | Tap | Tap → picker `onAppear` |
| --- | --- | --- | ---: |
| Debug, fixture | 1st after launch | Plain | 498 ms |
| Debug, fixture | 2nd | Plain | 86 ms |
| Debug, fixture | 3rd | Plain | 20 ms |
| Debug, fixture | Warm | Accessibility snapshot before and after | 856 ms |
| Debug, fixture | Next open after the snapshots | Plain | 1,386 ms |
| Debug, fixture | The one after | Plain | 59 ms |
| Debug, library and two 5-exercise days | 1st after launch, Progress opened first | Plain | 176 ms |
| Debug, library and two 5-exercise days | 2nd | Plain | 33 ms |
| Release, library | 1st, after typing in another sheet | Plain | 473 ms |
| Release, library | 2nd | Plain | 61 ms |
| Release, library | 1st after a cold launch, Hangs tracing | Plain | 1,243 ms |

The cold Release open's main-thread hang lasted 2.43 s, starting at the tap. It was
2.34 s under Time Profiler.

Findings:

- **The ~1.8 s on every open came from the recording automation.**
  `Marketing/Liftly-Launch/source/capture.py` runs XcodeBuildMCP `snapshot-ui` around
  each tap. That accessibility dump makes SwiftUI build its accessibility tree on the
  main thread. Opens made after a dump took 0.86–1.39 s, compared with 20–86 ms without.
- **The first open after launch has a real one-time cost, in Release as well as
  Debug.** A time profile of the cold Release open puts it in framework and runtime
  work, not app code:
  - About a sixth of samples were in Swift protocol-conformance lookup
    (`swift_conformsToProtocolMaybeInstantiateSuperclasses`), plus framework loading.
  - Before `onAppear`, 52 of 109 main-thread samples were creating the sheet's
    `NavigationStack`.
  - After it, the toolbar, `List`, search field, and navigation bar each took 43–49 of
    243 samples. The picker has the app's only `List` and `.searchable`, so it pays
    their first-use cost.
  - App code accounted for 15 of 352 samples, so re-rendering the detail screen isn't a
    factor.
