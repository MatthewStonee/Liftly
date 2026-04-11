# Rack — Claude Code Instructions

## Project Overview
iOS fitness and workout programming app built with SwiftUI. Helps users track programs, 
exercises, sets, reps, and progress over time.

## Architecture
- SwiftUI for all UI
- SwiftData for local persistence
- MVVM pattern — ViewModels handle all business logic, Views are dumb
- No logic in View files

## Core Data Models
- `Exercise` — name, muscle group, equipment type
- `WorkoutSet` — reps, weight, linked to Exercise + Workout
- `Program` — collection of workouts forming a weekly plan

## Key Features (build in this order)
1. Program/routine builder
2. Add exercises and sets to a workout
3. Progress charts per exercise (weight over time)

## Rules
- NEVER modify .pbxproj files — create Swift files, I'll add them to 
  Xcode manually
- Always use SwiftData for persistence, no CoreData or UserDefaults 
  for model storage
- All new views go in /Features/<FeatureName>/
- Always build and test in simulator after changes

## UI/UX Guidelines
- Dark mode first
- SF Symbols for all icons
- Liquid Glass UI elements.
- Follow Apple HIG — no custom nav patterns
- Fitness-friendly: large tap targets, easy one-handed use

## Simulator
- Default: iPhone 17 Pro Max
- Scheme: Rack

## What NOT to do
- Don't add third-party dependencies without asking
- Don't use UIKit unless SwiftUI can't do it
- Don't hard-code any exercise names or data



## Current Status (last updated April 2, session 3 — full summary below)

App is a 2-tab SwiftUI/SwiftData app (Programs + Progress). All files building cleanly.

### Data Models
- `Exercise` — name, `MuscleGroup` enum (with `.color` + `.sfSymbol`), `Equipment` enum
- `Program` → `WorkoutTemplate` → `PlannedExercise` (cascade delete)
- `WorkoutSession` + `LoggedSet` — `LoggedSet.session` is optional to support Quick Log without a session

### Features Built
- **Programs tab** — list, create, rename, delete program; program detail with workout days; workout day detail with planned exercises (add, edit sets/reps/weight, rename day, delete day)
- **Progress tab** — exercise list with PR + set count; per-exercise detail with Swift Charts line chart, 5 time-range filters, recent sets log; Quick Log FAB to log a set without a workout session; edit/delete logged sets via tap or context menu
- **Shared** — `ExercisePickerView` with muscle group filter chips and inline exercise creation

### UI Conventions
- All backgrounds: `LinearGradient([Color(0.04,0.06,0.18), .black])` applied inside NavigationStack on content (not on NavigationStack itself — iOS 26 overrides it)
- "Create" actions use a `+` toolbar button (`.primaryAction`) — do NOT use FABs via `safeAreaInset`; iOS 26 system gesture gate at the bottom edge makes them unreliable
- Rename + Delete actions share an `ellipsis.circle` toolbar menu (see `ProgramDetailView`, `WorkoutTemplateDetailView`)
- Exercise rows use a 4pt colored left bar (`MuscleGroup.color`) — bar is a plain `Rectangle()` inside the HStack with `.clipShape(RoundedRectangle(cornerRadius: 20))` on the card so corners flow with the container
- Reusable components in `Shared/GlassCard.swift`: `GlassCard`, `GlassButton`, `PrimaryButton`, `StatBadge`, `FABButtonStyle`, `.glassBackground()`, cross-platform stubs (`titleDisplayMode`, `keyboardType`, `fullScreenCover`)
- `Button(_:systemImage:role:)` shorthand causes overload errors — use explicit `Button(role:) { } label: { Label(...) }` form
- All glass components use `.glassEffect(.regular, in: ...)` (iOS 26 native API) — no more `.ultraThinMaterial` or manual stroke overlays
- Ternary expressions in `.foregroundStyle()` must use the same concrete type on both branches — mixing `HierarchicalShapeStyle` (`.tertiary`) and `Color` (`.blue`) causes a build error; use `Color.secondary.opacity(0.4)` instead of `.tertiary` when the other branch is a `Color`
- To clip a colored bar to a card's rounded corners: put the bar as a plain `Rectangle()` inside the HStack, then call `.clipShape(RoundedRectangle(cornerRadius: 20))` on the card — do NOT use `UnevenRoundedRectangle` or overlays, the clip shape handles the corners automatically

### Gotchas
- Custom `ProgressView` struct shadows SwiftUI built-in — our type is `ProgressTabView`
- `Button(_:systemImage:role:)` shorthand hits SwiftUI overload resolution bugs — always use explicit label form
- Curly quotes in Swift string literals cause parse errors — use `\"`
- `.glassEffect(.regular.interactive())` on a Button label intercepts taps and breaks the button action — do NOT use `.interactive()` on label content inside a `Button`; use a `ButtonStyle` instead
- FABs via `safeAreaInset(edge: .bottom)` are unreliable on iOS 26 — system gesture gate at the bottom edge causes "Gesture: System gesture gate timed out" and dropped taps. Use toolbar buttons instead.
- Sheet presentation state (`isPresented`) must be plain `@State Bool` on the view — do NOT store it in an `@Observable` ViewModel. After sheet dismissal, the binding chain through `@Observable` can silently fail to re-enable the triggering control.

## Session 3 — April 2

### What was done
- **Fixed Programs tab FAB** — investigated and resolved through several iterations:
  - Moved `.glassEffect` out of Button label and into `FABButtonStyle` (label was intercepting taps)
  - Moved `.sheet` outside `NavigationStack` to fix "works once then stops" after dismissal
  - Moved `showingCreateProgram` from `@Observable` ViewModel to `@State` on the view (Observable binding chain was silently failing after sheet dismiss)
  - Switched from `DragGesture(minimumDistance: 0)` to toolbar button after diagnosing "System gesture gate timed out" log — iOS 26 system gesture zone at the bottom edge makes `safeAreaInset` FABs unreliable
  - Final solution: standard `+` toolbar button (`.primaryAction`), matching Apple HIG
- **Added delete program** — `ProgramDetailView` toolbar button replaced with `ellipsis.circle` menu containing Rename + Delete Program, matching the pattern already used in `WorkoutTemplateDetailView`. Includes confirmation alert and dismiss-on-delete.

### Open To-Dos
- None — all known issues resolved this session.

## Session 4 — April 3 (branch: ui/stitch-redesign)

### What was done
- **Google Stitch UI redesign** — translated 4 HTML/Tailwind designs into native SwiftUI across all main screens:
  - **ProgramsView** — active program promoted to a large hero bento card (gradient overlay, "CURRENTLY ACTIVE" pill, name + stats). Inactive programs shown in "Other Programs" list with icon+name+stats rows. "Set Active" moved to long-press context menu.
  - **ProgramDetailView** — nav title switched to `.inline`; new hero section with "PROGRAM" label + large program name + 2-col stat cards (Days / Exercises). `WorkoutTemplateRow` redesigned: larger name, dot indicator (blue if has exercises, dim if empty), circle arrow button. "Add Workout Day" uses `PrimaryButton`.
  - **WorkoutTemplateDetailView** — `PlannedExerciseRow` updated: muscle group shown above exercise name in small uppercase + color-matched. Exercise name promoted to `.title3.bold()`. "Add Exercise" uses `PrimaryButton`.
  - **ProgressView** — weekly volume bento card added at top of list (computed from all `LoggedSet` in last 7 days). `ExerciseProgressRow` redesigned: full-height color bar clipped to card corners, muscle group label above name, "LAST PR" + "SETS" stat pair.

### Open To-Dos
- None — branch ready to review and merge.

## Session 5 — April 4 (branch: ui/stitch-redesign)

### What was done
- **Long exercise name truncation fix** — `ExerciseProgressView` was using `.titleDisplayMode(.large)` which iOS truncates to a single line. Switched to `.titleDisplayMode(.inline)` for the nav bar and added the exercise name as a large wrappable `Text` at the top of the scroll content, so any length name displays fully.

### Open To-Dos
- Tracked in Notion: https://www.notion.so/33def31f82228136a7fbe2bb7b7262e6
