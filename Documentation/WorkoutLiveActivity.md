# Workout Live Activity

Liftly's Live Activity is a reference to a saved workout day. It does not log sets,
mark exercises complete, create sessions, or change the active program.

## Use

Open any workout day and choose **Show on Lock Screen**. The activity shows
exercise names together whenever they fit. Tap its content to open that day in
Programs. Previous and Next appear only when the day needs multiple pages.
Choose **Stop Live Activity** to remove the card immediately. Showing another
day manually requires confirmation and reuses the existing activity.

The Lock Screen and expanded Dynamic Island show a names-only overview with a
compact day/count header. At the default text size, up to ten names appear in
five rows and two columns, in saved order from left to right and top to bottom.
Odd counts leave the last cell blank. Long names use an ellipsis; accessibility
labels include the supplied name and position. There are no set, rep, or weight
targets in the display or payload.

Scaled footnote row heights determine capacity within a 160-point budget.
Paging reserves 44-point controls and uses fewer names per page. At xxxLarge
and above, the layout switches to one column. Header and control typography
are capped at the default size, while exercise names follow Dynamic Type.
For days of ten or fewer exercises, all names are supplied so text-size changes
can restore the whole-day overview without fetching. Longer days supply up to
ten names starting at the selected position. The extension renders these values
without opening SwiftData; stored workout data and weights are unchanged.

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

Updates follow successful saves, locally observed store changes, and foreground
return. The names-only projection does not depend on the weight-unit preference. Projection uses a fresh context, so unsaved drafts and
pending Undo deletions cannot alter the reference. A committed deletion updates
the page or ends the activity. Failed refreshes keep the last page and show
**Refresh needed**. Relaunch recovers existing activities and removes duplicates;
it never restarts one the system or user dismissed.

Operations are serialized across awaits. The ActivityKit client retains the last
submitted state because `Activity.content` can lag updates. Each rendered page
also supplies its version and anchor: a restored object can catch up to a newer
render, while rapid taps from an older render use the latest submitted version.
Older activity payloads decode with version zero and their original starting
position as the window start. Their two supplied names remain pageable until
a refresh replaces the payload. Display strings are
bounded without changing source data, and the combined encoded attributes and
content are checked against a 3,800-byte budget, leaving headroom below 4 KB.

No model schema changes, additional test target, third-party dependency, push
service, background timer, or location service were introduced.

## Validation

Use the shared **Rack** scheme with XcodeBuildMCP on iPhone 18 Pro, iOS 27.
The existing `ProgramCommandTests.swift` includes `WorkoutActivityTests` for
names-only projection, unchanged weights, nil relationships, long names/payloads,
nine/ten-name overviews, larger-text capacity, legacy payloads, overflow windows,
page boundaries, rapid taps, refresh failures, saved edits, Undo/deletion,
start conflicts, store failures, restoration, entities, and links.

The existing UI target includes manual start/switch/stop, empty days, relaunch,
cold/warm links, missing destinations, native Notification Center paging, and
compact/expanded Dynamic Island checks.

On October 1, 2026, XcodeBuildMCP built the app and extension on iPhone 18 Pro,
iOS 27. All 160 unit tests passed. After the boundary guard was added, all 25
Live Activity unit tests passed again in a focused run. Native UI scenarios
passed across focused runs for nine/ten-name overviews, eleven-name overflow
paging, manual start/switch/stop/empty days/relaunch, and cold/warm/missing links.
The larger-text scenario also passed at system XXXL and the largest accessibility
size, reaching all ten names with tappable 44-point controls. The simulator's
original text-size preference was restored afterward.

Native screenshots were visually checked for nine/ten-name Lock Screen and
expanded Island layouts, overflow first/last pages and Island controls, and
single-column larger-text pages. Extra Island insets keep names and counts clear
of the rounded corners. Earlier UI assertions were corrected because SpringBoard
reports disabled remote controls as enabled; tapping one follows the card's
content deep link. The boundary scenario now returns from the linked workout
and confirms that its page did not change. Coordinator tests additionally cover
boundary intents as no-ops. The unrelated drag/history UI suite was not rerun
for this presentation change, and no physical-iPhone validation was performed.

The isolated `-LiftlyUITestFixture liveActivity <unique-id>` seeds library
exercises into Push Day, Other Day, Empty Day, Nine Exercises, Ten Exercises,
and Eleven Exercises. Their day UUIDs end in 001 through 006, respectively;
the fixture never opens the production store.

Before shipping, complete these physical-iPhone checks:

- Lock Screen and compact, expanded, and minimal Dynamic Island; long names,
  nine/ten-name whole-day overviews, overflow paging, and offline use.
- Larger text, including accessibility sizes: single-column paging reaches every
  exercise, names remain readable, and controls remain tappable. Returning to
  default text restores all nine/ten names without paging.
- VoiceOver: exercise names and position announcements, Previous/Next labels and boundaries,
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
