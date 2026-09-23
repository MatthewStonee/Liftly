# Liftly

A personal iOS fitness and workout programming app built with SwiftUI. Liftly helps you build structured training programs, log sets and reps, and track your progress over time.

## Features

- **Program Builder** — Create programs made up of workout days, and give each exercise planned sets, an exact, ranged, or to-failure rep target, and an optional target weight. Your first program becomes active automatically; switch programs any time.
- **Progress Tracking** — See the active program's exercises with per-exercise charts of weight over time, personal records per rep count, and weekly volume. Filter by time range, or page through an exercise's full history.
- **Quick Log** — Log a set for any exercise in the active program, without starting a workout session.
- **Exercise Library** — Browse the built-in library by muscle group or search it, and create custom exercises while adding one to a workout.
- **Undo** — Deleting a program, day, exercise, or set can be undone for a few seconds; leaving the app saves the deletion.
- **iCloud Sync** — Data syncs through CloudKit, and stays on the device if iCloud is unavailable.

## Tech Stack

- **SwiftUI** — All UI, dark mode only, with Liquid Glass surfaces
- **SwiftData** — Persistence with CloudKit sync and a local-only fallback; no third-party dependencies
- **Swift Charts** — Progress visualizations
- **MVVM** — ViewModels own the business logic; views stay presentational

## Requirements

- iOS 27.0+ (iPhone, portrait only)
- Xcode 27+

## Project Structure

```
Rack/
├── Features/
│   ├── Exercises/      # Exercise picker and custom exercise creation
│   ├── Programs/       # Program list, program detail, workout days
│   ├── Progress/       # Progress list, exercise detail, history, set sheets
│   ├── Settings/       # Units and default rep target
│   └── Startup/        # Store opening, recovery, and the app root
├── Models/             # SwiftData models and the exercise library seed
└── Shared/             # Persistence commands, deletion undo, shared UI
RackTests/              # Unit tests (Swift Testing)
RackUITests/            # UI integration tests (XCTest)
```

## Getting Started

1. Clone the repo
2. Open `Rack.xcodeproj` in Xcode
3. Select the `Rack` scheme and an iPhone simulator
4. Build and run (`Cmd+R`)

Run the unit and UI tests with **Product ▸ Test** (`Cmd+U`) on the iPhone 18 Pro (iOS 27) simulator. See [RackUITests/README.md](RackUITests/README.md) for the UI-test fixtures.

No dependencies to install — the project uses only Apple frameworks.
