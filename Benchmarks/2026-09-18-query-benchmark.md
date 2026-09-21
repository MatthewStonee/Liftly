# Liftly query benchmark — 2026-09-18

Device: iPhone 18 Pro simulator, iOS 27.0. Store: temporary SQLite SwiftData
store with 50 programs, 49 workouts, 49 planned exercises, and 1,200 logged
sets. See `LargeStoreBenchmarkTests.deletionAndInitialHistoryFetch` in
`RackTests/P2RegressionTests.swift` for the repeatable fixture and measurements.

| Operation | Measured time | Fetched rows |
| --- | ---: | ---: |
| Previous deletion pattern: fetch every collection | 0.012974 s | 1,348 |
| Targeted empty-program deletion commit | 0.004495041 s | 1 requested program |
| Previous history pattern: fetch every exercise set | 0.019366208 s | 1,200 |
| Bounded initial history page | 0.008751084 s | At most 51 |

Times come from one simulator run and are diagnostic, not test thresholds.
The deletion measurements cover different scopes: the previous-pattern value is
four fetches, while the targeted value includes the single command save. The
fetched-row counts and request trace establish that the new paths avoid loading
unrelated collections. The full benchmark report is attached to the passing
Xcode test result at
`/Users/matthew/Library/Developer/XcodeBuildMCP/workspaces/Liftly-18ae3f2e94f3/result-bundles/test_sim_2026-09-18T17-18-57-934Z_pid70340_4f4d9624.xcresult`.
