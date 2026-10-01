# Liftly — Agent Instructions

Shared by every coding agent: Codex reads this file directly, and `CLAUDE.md` imports it.

## Project Overview
Liftly is an iPhone fitness and workout programming app built with SwiftUI. Users build programs of workout days, log sets against the active program's exercises, and track progress and personal records over time.

## Architecture & Conventions
- SwiftUI for all UI; use UIKit only where SwiftUI can't do the job.
- SwiftData persistence with CloudKit sync and a local-only fallback. The schema is `AppDataStore.schema` (`Rack/Shared/AppDataStore.swift`). No Core Data, and no UserDefaults for model data (small flags and `@AppStorage` preferences are fine).
- MVVM: feature view models hold the business logic and persistence commands; views stay presentational. View models that hold view state are `@Observable`.
- Dark mode only: `UIUserInterfaceStyle = Dark` in `Rack/Info.plist` plus `.preferredColorScheme(.dark)`.
- Liquid Glass surfaces and SF Symbols for icons. Follow Apple's HIG, and ask when a request conflicts with it.
- Fitness-friendly: large tap targets (44pt minimum), easy one-handed use.

## Invariants (do not break)
- **Weights are stored in pounds.** Convert for display with `WeightUnit.display(_)` / `WeightUnit.store(_)` (`Rack/Shared/Extensions.swift`); the preference is `@AppStorage("weightUnit")`. Editable weight fields use `WeightDraft` / `WeightInput` (`Rack/Shared/WeightInput.swift`), which parse locale-aware decimals, reject invalid text instead of reading it as zero, and keep the exact stored pounds when the text is unchanged.
- **`LoggedSet.session` is optional**, so Quick Log can log without a `WorkoutSession`. Code that filters by session must handle nil.
- **PRs are tracked per exercise × rep count.** Log and edit sets through `ProgressViewModel.logSet` / `updateSet`, and delete them through `DeletionCoordinator`, whose commit calls `ProgressViewModel.deleteSetsInCommand`. Each path saves the set change and its `isPersonalRecord` flags together. `PersonalRecordBackfillActor.backfillIfNeeded()` repairs historical flags once, after startup maintenance.
- **User writes save explicitly.** Main-context autosave is off. Every create, edit, delete, and reorder goes through a view-model command built on `PersistenceCommandRunner.perform(in:_:)`, which refuses a dirty context, applies the change, saves once, and rolls back on failure. Commands that insert into a to-many relationship use `performInsert(in:refresh:_:)` instead: on iOS 27, rolling back such an insert leaves the parent's relationship unreadable and the next read crashes, so these save through a disposable context. Show returned errors with `.persistenceAlert(isPresented:alert:)`. Never mutate persisted models from views or bind form fields to model properties; keep drafts in `@State`.
- **The schema stays CloudKit-compatible.** Every stored property needs a default value or must be optional, relationships must be optional, `@Attribute(.unique)` is not allowed, and changes must be additive. A violation makes the CloudKit store fail to open, and users silently drop to the local-only fallback.
- **Startup never deletes or replaces the store.** `AppDataStore` tries CloudKit, then local-only at the same location, and otherwise shows a Retry screen. Maintenance starts only after the store opens.
- **Duplicate library exercises merge into the oldest copy.** Startup maintenance (`ExerciseLibrary.reconcile`) keeps the oldest `createdAt`, then the smallest ID, and re-points plans and sets to it, so every device keeps the same copy however much it has synced. Never choose by local reference counts: two devices could each delete the other's survivor, and sets still syncing would lose their exercise.

## Shared Utilities
Check `Rack/Shared/` and the feature's own folder before building a new component.

- **Deletion**: request deletions with `DeletionCoordinator.request(_:)`; never delete immediately or schedule your own timer. The coordinator batches requests behind the Undo toast, pauses while the app is inactive, commits when the Undo window ends or the app moves to the background, and reports failures to `PersistenceAlertCenter`. Each request is announced to VoiceOver, and the Undo window is 4 s, or 10 s while VoiceOver runs. It deletes programs, workout days, planned exercises, and logged sets; a new deletable type needs an `Identity` case and commit logic. Apply `.deletionUndoToast(deletionCoordinator)` to every sheet's root view so failures appear above that sheet.
- **Navigation**: push with `NavigationLink(value:)` or a path append, and resolve screens in one `navigationDestination(for:)` at the stack root: `ProgramsRoute` (`ProgramsView.swift`) and `ProgressRoute` (`ProgressView.swift`).
- **History**: `ExerciseHistoryViewModel` owns paging, refreshes, and the scroll anchor for `ExerciseHistoryView`; views never fetch sets themselves. Its doc comments describe the anchoring rules.
- **Metrics**: set commands only save and publish `LoggedSetChange`; the screen showing metrics (`ExerciseProgressView`) refreshes them itself. A deletion refreshes it even while History covers it, so it never holds a deleted set.
- **Components**: `TimeRangePicker`, `.appBackground()`, `GlassCard`, `PinnedActionBar` (a sheet's primary action above the keyboard), `WeightValidationMessage`, `ReorderableForEach` (touch-and-hold reordering on iOS 27's `reorderable()`, with VoiceOver Move Up/Down), and the Log Set / Edit Set sheets in `LoggedSetSheets.swift`.
- **Haptics**: prefer `.sensoryFeedback`. Use `UINotificationFeedbackGenerator` only when the view dismisses in the same action (Quick Log), because a `.sensoryFeedback` trigger on a disappearing view may never fire.
- **Signposts**: mark latency checkpoints with `PerformanceSignposts.event(_:)`. They appear on Instruments' Points of Interest track, and `Benchmarks/` shows how to stream them.

## Gotchas
- `Button(_:systemImage:role:)` shorthand hits SwiftUI overload-resolution bugs; use the explicit label form.
- `.glassEffect(.regular.interactive())` on a Button label intercepts taps and breaks the action. Put interactive glass in a `ButtonStyle`.
- Keep presentation state (a `Bool` or an optional item) in the view's `@State`, not in an `@Observable` view model: after dismissal the binding through the view model can silently fail to re-enable the triggering control.
- A view-destination `NavigationLink { Destination() }`, or a `navigationDestination(item:)` declared inside a pushed screen, can lock `NavigationStack` into an endless update loop on iOS 27. Use the route enums above.
- Modifiers that react to a change (`.sensoryFeedback`, `.onChange`) only fire while their view exists; attach them to a view that outlives the value.
- Apply `clipShape` before `.glassEffect`. Inside a `GlassEffectContainer`, a `clipShape` applied after the glass left the Progress row's accent bar unclipped.
- On iOS 27, a `.foregroundStyle` on a y-axis `AxisValueLabel` stops Swift Charts from drawing the label at all; the default is already secondary.
- A compact `DatePicker`'s button reads to VoiceOver as "Date Picker" whatever label the picker has, so keep its visible caption readable. An untouched picker can also rewrite the bound date's exact time: compare dates at the granularity the picker edits.
- State set synchronously in `onAppear` is in a screen's first frame. Work started in a `Task` from `onAppear` lands at least one frame later, so show what the first frame needs before starting async work (Progress lists its rows, then loads stats).
- UI automation that dumps the accessibility tree (XcodeBuildMCP `snapshot_ui`, `capture.py`) makes SwiftUI build that tree on the main thread. The next interactions slow down: a warm Add Exercise open went from 20–86 ms to 0.9–1.4 s. Time interactions with plain taps.
- On iOS 27.0, a `reorderable()` stack in a ScrollView doesn't auto-scroll when the lifted row reaches an edge; it only scrolls to keep the gap visible. Reorder drags never reach `onDragSessionUpdated` or `onDropSessionUpdated`, so there's no hook to add auto-scroll. Simulator screenshots and recordings also omit the lifted row, which the system draws out of process.

## Concurrency
- Swift 5 language mode with `MainActor` as the default isolation and approachable concurrency. Code that runs on a `@ModelActor` (startup maintenance, the PR backfill) and the helpers it calls must be `nonisolated`.
- Data-race checking is off, so the compiler won't catch thread hops. Deliver notifications from background contexts, such as `ModelContext.didSave`, to the main thread yourself.

## Rules
- Screens go in `Rack/Features/<Feature>/`; reusable components go in `Rack/Shared/`.
- Build and test in the simulator after changes.
- Don't add third-party dependencies without asking.
- Don't hard-code exercise data; seed through `ExerciseLibrary`.
- Declare any new required-reason API (such as UserDefaults, file timestamps, or disk space) in `Rack/PrivacyInfo.xcprivacy`; App Store uploads without the declaration are rejected.

## Testing
Ask before adding a test target.
- Unit tests live in `RackTests/` (Swift Testing, `@testable import Rack`) and belong to the `LiftlyUnitTests` target by explicit membership, so a new file needs a project change. Prefer adding suites to an existing file. `Rack/` is a synchronized folder, so new app files join the app target automatically.
- UI tests live in `RackUITests/` (XCTest); see its README.
- CI (`.github/workflows/ci.yml`) builds the `Rack` scheme and runs both test targets on every pull request and push to `main`, on GitHub's `xcode-27` runner with the iPhone 18 Pro simulator. A failing test is retried up to twice. When the project moves to a new Xcode or simulator, update the workflow's `runs-on` and destination to match.
- Debug launch arguments:
  - `-LiftlyDebugStoreOpenFailures <n>`, `-LiftlyDebugSaveFailures <n>`, and `-LiftlyDebugHistoryLoadFailures <n>` fail the first `n` store opens, saves, or history page loads.
  - `-LiftlyUITestFixture <reorder|history|firstRun> <id>` opens an isolated local-only store (no iCloud) seeded for that scenario; `firstRun` has only the exercise library. `-LiftlyUITestUndoSeconds <4–30>` stretches the Undo window for UI automation.

## Build Configuration
- Build and test locally with XcodeBuildMCP without asking; never run raw `xcodebuild` shell commands. Only the CI workflow calls `xcodebuild` directly.
- Scheme: `Rack`. Target simulator: iPhone 18 Pro (iOS 27.x).
- iPhone-only and portrait-only (no iPad, no Mac Catalyst, no landscape); layouts can assume a phone-sized portrait viewport.

## Open To-Dos
- Tracked in Notion: https://www.notion.so/33def31f82228136a7fbe2bb7b7262e6. Statuses can lag the code, so check the code before relying on one.
