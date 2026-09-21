# Liftly — Codex Instructions

## Project Overview
Liftly is an iOS fitness and workout programming app built with SwiftUI. Helps users track programs, exercises, sets, reps, and more over time.

## Architecture & Conventions
- SwiftUI for all UI (no UIKit unless SwiftUI can't do it)
- SwiftData for local persistence — schema lives in `Rack/RackApp.swift`
- MVVM — ViewModels are `@Observable`, hold all business logic; Views are dumb
- Dark mode first (`.preferredColorScheme(.dark)` is forced app-wide)
- Liquid Glass UI elements; SF Symbols for all icons
- Prioritize following Apple HIG; Ask when it may not be ideal
- Fitness-friendly: large tap targets, easy one-handed use

## Invariants (do not break)
- **Weights are always stored in lbs internally.** UI converts via `WeightUnit.display(_)` / `WeightUnit.store(_)` from `Rack/Shared/Extensions.swift`. User preference lives in `@AppStorage("weightUnit")`. Any new weight-facing view must go through these helpers — never read/write raw doubles to the user. Editable weight fields use `WeightDraft` / `WeightInput` (`Rack/Shared/WeightInput.swift`): they parse locale-aware, ungrouped decimals, reject invalid text instead of reading it as zero, and reuse the exact stored pounds when the text is unchanged.
- **`LoggedSet.session` is optional.** This is intentional so Quick Log can create a `LoggedSet` without a `WorkoutSession`. Code that filters "sets belonging to a session" must handle nil.
- **PRs are tracked per exercise × per rep count**, not just per exercise. A one-time `backfillPersonalRecords()` runs on app launch to mark historical PRs. New/edit/delete of a `LoggedSet` must go through `ProgressViewModel.logSet` / `updateSet` / `deleteSet`, which fetch the exercise's current sets and save the set change and its `isPersonalRecord` flags together.
- **User writes save explicitly.** Main-context autosave is off. Every create/edit/delete/reorder goes through a feature ViewModel method built on `PersistenceCommandRunner.perform(in:_:)`, which refuses an already-dirty context, applies the change synchronously, saves once, and rolls back on failure. Commands that insert a model into a to-many relationship (logging a set, adding a workout day or planned exercise) use `performInsert(in:refresh:_:)` instead: on iOS 27, rolling back such an insert makes the parent's relationship unreadable and the next read crashes, so these save through a disposable context and reload the parent's relationships on success. Views show the returned `PersistenceCommandError` with `.persistenceAlert(isPresented:alert:)`; failures from delayed work (undo-toast deletions) go to the environment's `PersistenceAlertCenter`, and the frontmost `.deletionUndoToast` host presents them, so the alert appears over an open sheet instead of dismissing it. Never mutate persisted models from views or bind form fields to model properties — keep drafts in `@State`.
- **Startup never deletes or replaces the store.** `AppDataStore` tries CloudKit, then local-only at the same location, and otherwise shows a Retry screen. Maintenance starts only after the store opens.

## Shared Utilities
Check `Rack/Shared/` and nearby feature components before creating new UI components.

### Patterns to reuse
- **Undo-deletion**: schedule deletion via `Task` with ~4s delay, cancelable from `UndoToast`. See `ProgramsView` and `ProgramDetailView`. Destructive actions should follow this pattern, not delete immediately. Every sheet's root view must apply `.deletionUndoToast(deletionCoordinator)`, which shows the toast and presents deletion failures above that sheet.
- **History paging**: `ExerciseHistoryViewModel` owns the range, the loaded window, every refresh and the scroll anchor for `ExerciseHistoryView` — views never fetch sets themselves. All refresh paths go through its `fetchWindow`, which keeps the user's place when the anchored row disappears and returns them to it on Undo; `appear(exerciseID:context:excluding:)` loads on first appearance and refreshes on re-entry.
- **Metrics refresh**: set commands (`ProgressViewModel.logSet` / `updateSet` / `deleteSet`) only save and publish `LoggedSetChange`; they never recompute metrics. The screen that shows metrics refreshes them itself: `ExerciseProgressView` does so on entry, on `LoggedSetChange` for its exercise (immediately, so Quick Log prefills the latest set), and on foreground return, and skips the work while History covers it.
- **Haptics**: `.sensoryFeedback(.impact, ...)` for drag/toast; `UINotificationFeedbackGenerator().notificationOccurred(.success)` for successful logs. Match the surrounding code when adding new interactions.

## Gotchas
- `Button(_:systemImage:role:)` shorthand hits SwiftUI overload resolution bugs — always use explicit label form
- `.glassEffect(.regular.interactive())` on a Button label intercepts taps and breaks the button action — do NOT use `.interactive()` on label content inside a `Button`; use a `ButtonStyle` instead
- Sheet presentation state (`isPresented`) must be plain `@State Bool` on the view — do NOT store it in an `@Observable` ViewModel. After sheet dismissal, the binding chain through `@Observable` can silently fail to re-enable the triggering control.
- View-destination `NavigationLink { Destination() }` inside a pushed screen can lock `NavigationStack` into an endless update loop on iOS 27 — do NOT use it; push with `NavigationLink(value:)` or a path append, and resolve every screen in one `navigationDestination(for:)` at the stack root (see `ProgressRoute` in `ProgressView.swift`). Opening History from a screen pushed with `navigationDestination(item:)` froze the app at 100% CPU.

## Rules
- Always use SwiftData for persistence — no CoreData, no UserDefaults for model storage (UserDefaults is fine for small flags like `"exerciseLibrarySeeded"` or `@AppStorage` preferences)
- All new views go in `Rack/Features/<FeatureName>/`
- Always build and test in simulator after changes
- Don't add third-party dependencies without asking
- Don't hard-code exercise names or data — seed via `ExerciseLibrary` instead

## Testing
Ask before adding a test target.
- Unit-test sources live in `RackTests/` (Swift Testing, `@testable import Rack`), outside the synchronized `Rack/` folder so the app target doesn't compile them.
- Debug builds accept `-LiftlyDebugSaveFailures <n>` and `-LiftlyDebugStoreOpenFailures <n>` launch arguments to simulate persistence failures in the simulator.

## Build Configuration
- Scheme: `Rack`
- Target simulator: iPhone 18 Pro (iOS 27.x)
- iPhone-only (no iPad, no Mac Catalyst) — layouts can assume phone-sized viewports
- Build command: Ask if you should use XcodeBuildMCP tools, never raw `xcodebuild` shell commands

## Open To-Dos
- Tracked in Notion: https://www.notion.so/33def31f82228136a7fbe2bb7b7262e6
