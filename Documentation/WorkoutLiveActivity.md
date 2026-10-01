# Workout Live Activity

Liftly's Live Activity is a reference to a saved workout day. It does not log sets,
mark exercises complete, create sessions, or change the active program.

## Use

Open any workout day and choose **Show on Lock Screen**. Use Previous and Next
to browse its exercises. Tap the activity's content to open that day in Programs.
Choose **Stop Live Activity** to remove the card immediately. Showing another
day manually requires confirmation and reuses the existing activity.

The Lock Screen and expanded Dynamic Island show stacked exercise targets.
The normal page contains two exercises; larger text uses one. The extension
receives only the visible window, including a second row for text-size changes.
It renders supplied values without opening SwiftData. Weight formatting uses
the user's preference; stored pounds are never converted or rewritten.

## Gym automations

In Shortcuts, create two personal automations:

1. **Arrive** at the gym → **Show Workout Day on Lock Screen** → select a day.
2. **Leave** the gym → **Stop Workout Live Activity**.

Choose the gym boundary and **Run Immediately**. The Settings guide in Liftly
explains this setup. Users configure these automations on their own phone.
Liftly requests no location access and stores no gym coordinates. Weekday
branching belongs in Shortcuts; the action always uses the selected day.

Repeated starts of the same day refresh it and preserve the current page.
An automatic start for another day keeps the existing activity. Repeated stops
succeed harmlessly. Day entities use UUIDs and show the program as a subtitle.

## Implementation

- `LiveActivityShared/`: ActivityKit values, strict URL parsing, and paging intent.
- `LiftlyLiveActivity/`: WidgetKit extension, with the app's iOS target and team.
- `Rack/Features/LiveActivity/`: saved-data projection, serialized coordinator,
  App Entities and Shortcuts actions, manual controls, and setup guide.
- `AppDataStore.shared`: common foreground/headless store opener, preserving
  CloudKit/local fallback and the existing recovery behavior.

Updates follow successful saves, locally observed store changes, unit changes,
and foreground return. Projection uses a fresh context, so unsaved drafts and
pending Undo deletions cannot alter the reference. A committed deletion updates
the page or ends the activity. Failed refreshes keep the last page and show
**Refresh needed**. Relaunch recovers existing activities and removes duplicates;
it never restarts one the system or user dismissed.

Operations are serialized across awaits. The ActivityKit client retains the last
submitted state because `Activity.content` can lag updates. Each rendered page
also supplies its version and anchor: a restored object can catch up to a newer
render, while rapid taps from an older render use the latest submitted version.
Older activity payloads decode with version zero. Display strings are
bounded without changing source data, and the combined encoded attributes and
content are checked against a 3,800-byte budget, leaving headroom below 4 KB.

No model schema changes, additional test target, third-party dependency, push
service, background timer, or location service were introduced.

## Validation

Use the shared **Rack** scheme with XcodeBuildMCP on iPhone 18 Pro, iOS 27.
The existing `ProgramCommandTests.swift` includes `WorkoutActivityTests` for
projection, units, rep targets, nil weights/relationships, long names/payloads,
page boundaries, rapid taps, refresh failures, saved edits, Undo/deletion,
start conflicts, store failures, restoration, entities, and links.

The existing UI target includes manual start/switch/stop, empty days, relaunch,
cold/warm links, missing destinations, native Notification Center paging, and
compact/expanded Dynamic Island checks.

On September 30, 2026, XcodeBuildMCP built the app and extension on the iPhone
18 Pro simulator. All 156 unit tests passed, including 21 Live Activity tests.
The full Rack run passed 160 of 162 tests: the existing drag test and the native
paging test failed their UI waits. Both passed a focused rerun after the expanded
Island layout adjustment and settled-animation assertions. The full suite was
not rerun after that adjustment. Native screenshots were visually checked for
the first and last Lock Screen pages and compact/expanded Dynamic Island;
expanded controls were also checked for hittability and 44-point height.

The isolated `-LiftlyUITestFixture liveActivity <unique-id>` seeds library
exercises into Push Day, Other Day, and Empty Day. Its day UUIDs end in 001,
002, and 003, respectively; it never opens the production store.

Before shipping, complete these physical-iPhone checks:

- Lock Screen and compact, expanded, and minimal Dynamic Island; long names,
  all rep target types, absent weights, pounds/kilograms, and offline use.
- Larger text, including accessibility sizes: one-row paging reaches every
  exercise, targets remain readable, and controls remain tappable.
- VoiceOver: exercise/target announcements, Previous/Next labels and boundaries,
  range announcement, and content deep link.
- Shortcuts action discovery and UUID lookup with duplicate day names; missing
  days, unavailable store, authorization disabled, repeated/conflicting starts,
  repeated stops, and saved local edits.
- Arrive/Leave automations while Liftly is foregrounded, backgrounded, and
  terminated; locked-phone starts/paging/stops; departure removes the card.
- System/user dismissal is respected after relaunch; iOS's activity lifetime
  limit and an ended residual card can be dismissed with Stop.
- Committed exercise/day/program edits and deletion refresh; Undo leaves the
  reference intact; remote edits refresh once observed locally.

Simulator tests do not establish actual gym-trigger timing, locked-phone
execution, physical VoiceOver usability, or suspended CloudKit delivery.

Platform references: [LiveActivityIntent](https://developer.apple.com/documentation/appintents/liveactivityintent),
[ActivityKit lifecycle and limits](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities),
and [Shortcuts travel triggers](https://support.apple.com/guide/shortcuts/apd8ebfc4e8e/ios).
