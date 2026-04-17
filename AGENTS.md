# Rack — Codex Instructions

## Project Overview
iOS fitness and workout programming app built with SwiftUI. Helps users track programs, exercises, sets, reps, and progress over time.

## Architecture & Conventions
- SwiftUI for all UI (no UIKit unless SwiftUI can't do it)
- SwiftData for local persistence — schema lives in `Rack/RackApp.swift`
- MVVM — ViewModels are `@Observable`, hold all business logic; Views are dumb
- Dark mode first (`.preferredColorScheme(.dark)` is forced app-wide)
- Liquid Glass UI elements; SF Symbols for all icons
- Follow Apple HIG; no custom nav patterns
- Fitness-friendly: large tap targets, easy one-handed use
- All new views go in `Rack/Features/<FeatureName>/`

## Data Models
SwiftData `@Model` classes in `Rack/Models/`.

- `Exercise` — name, `MuscleGroup` enum (with `.color` + `.sfSymbol`), `Equipment` enum
- `Program` → `WorkoutTemplate` → `PlannedExercise` (cascade delete; each level has `orderIndex` for drag-to-reorder)
- `WorkoutSession` + `LoggedSet` — session has cascade delete over its logged sets
- `ExerciseLibrary` — seeds 60 exercises on first launch via a `"exerciseLibrarySeeded"` UserDefaults flag. To re-seed during dev: flip the flag or reset the app. Don't hand-add exercises thinking the library is empty.

### Invariants (do not break)
- **Weights are always stored in lbs internally.** UI converts via `WeightUnit.display(_)` / `WeightUnit.store(_)` from `Rack/Shared/Extensions.swift`. User preference lives in `@AppStorage("weightUnit")`. Any new weight-facing view must go through these helpers — never read/write raw doubles to the user.
- **`LoggedSet.session` is optional.** This is intentional so Quick Log can create a `LoggedSet` without a `WorkoutSession`. Code that filters "sets belonging to a session" must handle nil.
- **PRs are tracked per exercise × per rep count**, not just per exercise. A one-time `backfillPersonalRecords()` runs on app launch to mark historical PRs. New/edit/delete of a `LoggedSet` must go through `ProgressViewModel` methods so the `isPersonalRecord` flag is demoted/promoted correctly.

## Implemented Features
- **Programs tab** — list, create, rename, delete program (with undo); program detail with workout days; workout day detail with planned exercises (add, edit sets/reps/weight, rename day, delete day); drag-to-reorder days and exercises
- **Progress tab** — exercise list with PR + set count; per-exercise detail with Swift Charts line chart, 5 time-range filters, recent sets log; Quick Log FAB to log a set without a workout session; edit/delete logged sets via tap or context menu
- **Settings tab** — weight unit preference (lbs / kg), persisted via `@AppStorage`
- **Shared** — `ExercisePickerView` with muscle group filter chips and inline exercise creation

## Shared Utilities
Check `Rack/Shared/` before building a new card/button/row.
- `GlassCard`, `GlassButton`, `PrimaryButton`, `StatBadge`, `FilterChip` — reusable glass UI components
- `ReorderableForEach` — drag-to-reorder list utility
- `UndoToast` — undo toast modifier
- `Extensions.swift` — `WeightUnit` enum, Double formatting helpers

### Patterns to reuse
- **Undo-deletion**: schedule deletion via `Task` with ~4s delay, cancelable from `UndoToast`. See `ProgramsView` and `ProgramDetailView`. Destructive actions should follow this pattern, not delete immediately.
- **Haptics**: `.sensoryFeedback(.impact, ...)` for drag/toast; `UINotificationFeedbackGenerator().notificationOccurred(.success)` for successful logs. Match the surrounding code when adding new interactions.

## Gotchas
- Custom `ProgressView` struct shadows SwiftUI built-in — our type is `ProgressTabView`
- `Button(_:systemImage:role:)` shorthand hits SwiftUI overload resolution bugs — always use explicit label form
- `.glassEffect(.regular.interactive())` on a Button label intercepts taps and breaks the button action — do NOT use `.interactive()` on label content inside a `Button`; use a `ButtonStyle` instead
- Sheet presentation state (`isPresented`) must be plain `@State Bool` on the view — do NOT store it in an `@Observable` ViewModel. After sheet dismissal, the binding chain through `@Observable` can silently fail to re-enable the triggering control.

## Rules
- NEVER modify `.pbxproj` files — create Swift files, user will add them to Xcode manually
- Always use SwiftData for persistence — no CoreData, no UserDefaults for model storage (UserDefaults is fine for small flags like `"exerciseLibrarySeeded"` or `@AppStorage` preferences)
- All new views go in `Rack/Features/<FeatureName>/`
- Always build and test in simulator after changes
- Don't add third-party dependencies without asking
- Don't hard-code exercise names or data — seed via `ExerciseLibrary` instead

## Testing
No tests currently. Don't invent speculative tests — if a change genuinely needs coverage, flag it and ask before adding a test target.

## Build Configuration
- Scheme: `Rack`
- Target simulator: iPhone 17 Pro (iOS 26.x)
- iPhone-only (no iPad, no Mac Catalyst) — layouts can assume phone-sized viewports
- Build command: use XcodeBuildMCP tools, never raw `xcodebuild` shell commands

## Open To-Dos
- Tracked in Notion: https://www.notion.so/33def31f82228136a7fbe2bb7b7262e6
