# Liftly tests

The shared **Rack** scheme runs both test targets on **iPhone 18 Pro (iOS 27.x)**.
In Xcode, select that scheme and simulator, then choose **Product ▸ Test** (⌘U).
The same suite can run through XcodeBuildMCP.

## Source folders

- `RackTests/`: Swift Testing unit tests, compiled by the existing `LiftlyUnitTests` target.
- `RackUITests/`: XCTest UI integration tests, compiled by `RackUITests` against the `Rack` app.

The unused generated unit-test folder and example test have been removed.
Keep test sources outside `Rack/` so the app target does not compile them.
The UI-test folder is synchronized with its target; unit-test files use explicit
membership in `LiftlyUnitTests`.

## UI coverage

- Accepted and canceled drag reordering, including persistence after relaunch.
- Delayed deletion failures while an edit sheet contains an unsaved draft.
- History range selection, loading failure and Retry, pagination, and Undo.

## What the tests assume

Each test launches with `-LiftlyUITestFixture <reorder|history> <uuid>`, which
opens a unique, local-only SwiftData store under Application Support. No
production store is read or replaced, and a fixture survives that test's own
relaunch so reorder persistence can be checked. Failure injection uses
`-LiftlyDebugSaveFailures` and `-LiftlyDebugHistoryLoadFailures`. The fixture and
both failure switches exist only in debug builds. The delayed-failure scenario also
passes `-LiftlyUITestUndoSeconds 12`, allowing automation to type a draft before
the alert appears. This override is accepted only for an isolated UI-test fixture;
normal app use retains the four-second Undo interval.

The tests query these accessibility identifiers, each of which names exactly one
element: `program.row.<name>`, `workout.row.<name>`, `workout.drag.<name>`,
`deletion.undo`, `progress.exercise.<name>`, `progress.viewAllHistory`,
`history.row/edit/delete.<uuid>`, `history.range.<range>`, `history.list`
(whose value reads "<n> sets loaded"), `history.loadMore`,
`history.initialRetry`, `history.inlineRetry`, and `editSet.weight`. Renaming or
moving one of these breaks a test, so keep them on the element they name.

## Verified run

On September 23, 2026, the shared Rack scheme passed all **115 tests**
(**112 unit tests and 3 UI integration tests**) on iPhone 18 Pro, iOS 27.0,
with zero failures and zero skipped tests. The full run used the scheme's
normal test settings through XcodeBuildMCP.

## Additional manual coverage

These automated scenarios do not replace a VoiceOver pass over history range
controls, history rows, Load More, Retry, and Undo. They also do not validate
live CloudKit synchronization or physical-device behavior.
