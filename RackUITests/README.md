# Liftly UI tests

`LiftlyUITests.swift` is ready to run but has no target yet: `Rack.xcodeproj`
contains only the `Rack` app and the `LiftlyUnitTests` unit-test target. Agents
don't edit `.pbxproj`, so create the target in Xcode once:

1. **File ▸ New ▸ Target… ▸ iOS ▸ UI Testing Bundle.**
   - Product Name: `RackUITests`
   - Target to be Tested: `Rack`
   - Team/organization identifier: same as `Rack`.
2. Xcode creates a `RackUITests` group with two template files. **Delete both**
   (Move to Trash) — this folder already holds the real test source.
3. **Add `RackUITests/LiftlyUITests.swift` to the target**: drag it into the
   `RackUITests` group with "Copy items if needed" unchecked, or select the file
   and tick `RackUITests` in the File Inspector's Target Membership.
   Keep the file outside the synchronized `Rack/` folder, like `RackTests/`, so
   the app target never compiles it.
4. **Product ▸ Scheme ▸ Edit Scheme… ▸ Test**: add `RackUITests` to the test
   targets so the shared `Rack` scheme runs unit and UI tests together.
5. Run the scheme on **iPhone 18 Pro (iOS 27.x)**, the same simulator the unit
   tests use.

## What the tests assume

Each test launches with `-LiftlyUITestFixture <reorder|history> <uuid>`, which
opens a unique, local-only SwiftData store under Application Support. No
production store is read or replaced, and a fixture survives that test's own
relaunch so reorder persistence can be checked. Failure injection uses
`-LiftlyDebugSaveFailures` and `-LiftlyDebugHistoryLoadFailures`. The fixture and
both failure switches exist only in debug builds.

The tests query these accessibility identifiers, each of which names exactly one
element: `program.row.<name>`, `workout.row.<name>`, `workout.drag.<name>`,
`deletion.undo`, `progress.exercise.<name>`, `progress.viewAllHistory`,
`history.row/edit/delete.<uuid>`, `history.range.<range>`, `history.list`
(whose value reads "<n> sets loaded"), `history.loadMore`,
`history.initialRetry`, `history.inlineRetry`, and `editSet.weight`. Renaming or
moving one of these breaks a test, so keep them on the element they name.

## Checking the source without a target

Until the target exists nothing compiles this file, so type-check it directly
after editing:

```bash
PLAT=$(xcrun --sdk iphonesimulator --show-sdk-platform-path); SDK=$(xcrun --sdk iphonesimulator --show-sdk-path); xcrun swiftc -typecheck -sdk "$SDK" -target arm64-apple-ios27.0-simulator -F "$PLAT/Developer/Library/Frameworks" -I "$PLAT/Developer/usr/lib" RackUITests/LiftlyUITests.swift
```

## After the target exists

Run the full `Rack` scheme through XcodeBuildMCP, then do a VoiceOver pass over
the history range controls, history rows, Load More, Retry and Undo — VoiceOver
grouping is what these identifiers depend on, and only a manual pass catches a
regression there.
