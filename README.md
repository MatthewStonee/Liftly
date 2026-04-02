# Rack

A personal iOS fitness and workout programming app built with SwiftUI. Rack helps you build structured training programs, log sets and reps, and track your progress over time.

## Features

- **Program Builder** — Create and manage training programs made up of workout days. Add exercises to each day with planned sets, reps, and target weight.
- **Progress Tracking** — View per-exercise progress charts (weight over time), personal records, and a full log of recent sets. Filter by time range to see short or long-term trends.
- **Quick Log** — Log a set for any exercise on the fly, without needing an active workout session.
- **Exercise Library** — Browse exercises filtered by muscle group. Create custom exercises inline when adding to a workout.

## Tech Stack

- **SwiftUI** — All UI, dark mode first
- **SwiftData** — Local persistence, no third-party dependencies
- **Swift Charts** — Progress visualizations
- **MVVM** — ViewModels own all business logic; Views are purely presentational

## Requirements

- iOS 26.2+
- Xcode 26+

## Project Structure

```
Rack/
├── Features/
│   ├── Programs/       # Program list, detail, workout day builder
│   ├── Progress/       # Progress charts, Quick Log
│   └── Exercises/      # Exercise picker + inline creation
├── Models/             # SwiftData models (Program, Exercise, WorkoutSession, etc.)
└── Shared/             # Reusable UI components (GlassCard, StatBadge, etc.)
```

## Getting Started

1. Clone the repo
2. Open `Rack.xcodeproj` in Xcode
3. Select the `Rack` scheme and an iPhone simulator
4. Build and run (`Cmd+R`)

No dependencies to install — the project uses only Apple frameworks.
