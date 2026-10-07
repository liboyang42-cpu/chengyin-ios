# Story-template UI budget integration (local candidate)

Status: local tooling integration only. Swift typechecking, SwiftPM, Xcode/Apple SDK, AppUnit, XCUITest, simulator/device, VoiceOver, Dynamic Type and live CN/US execution have not run. No publication or production approval changes are included. This is not release-readiness evidence.

## Exhaustive inventory and unchanged limits

- All 712 prior methods in 147 whole XCTestCase classes remain byte-for-byte present. Six one-method story-template classes bring the live inventory to 718 methods in 153 classes. Shared helper files remain included in the generated UI target.
- All prior observations, estimates, planning floors, provenance and historical plans remain unchanged. The 647 run117 observations and the club observation of 27.351 seconds remain recorded exactly. Its current 300-second source-required planning floor still applies.
- Each new complete method carries a 900-second unmeasured engineering planning allowance. Total effective method cost is 98087.381 seconds.
- Deadline stays 1800 seconds, startup reserve 300 seconds, and maximum allowed duration-profile value 900 seconds. The last is a planning-value validation limit, not a new per-test Xcode timeout. AppUnit keeps its existing 120-second execution allowance.
- Deterministic whole-class LPT forecasts: 67 shards 1907.064 seconds; 71 shards 1826.149; 72 shards 1797.226; 73 shards 1770. Every count 1–153 is recorded and recomputed.
- 72 is the smallest deadline-fitting count. Select 73 to preserve the previous 30-second planning margin rather than relying on 2.774 seconds. Every matrix index, completion output, runner default and CI aggregation gate uses 73. No method slicing, omitted tests, lower costs, enlarged deadline, or reduced startup reserve is used.

## Full-method derivation and its limits

Each journey launches once, opens the chooser three times, previews four times, takes five fresh stored-envelope probes, performs Back/Refresh/Close cancellation, rereads the source on Apply, verifies the exact insertion, rebuilds the coordinator, restores and resaves the stored editor, then reopens read-only.

The end path has 24 tap-helper calls and first/middle paths 27. Each helper has 5 seconds existence plus 5 seconds enabled/hittable wait. Other explicit waits total 115 seconds, producing 355/385 seconds. All methods use 14 reveal calls, each up to 11 viewport iterations and 10 gestures. At an assumed 2 seconds per complete iteration, this allocates 308 seconds. An iteration includes multiple accessibility queries and nested navigation-bar/button scans, not one query.

The planning arithmetic is 90 seconds allocated to launch + 355/385 explicit wait caps + 308 reveal allowance + 117 other-overhead allocation + 30/0 rounding reserve = 900. The 117 seconds is allocated planning capacity, not independently established overhead. It includes three direct navigation-back taps outside the helper count, remaining SwiftUI transitions, framework synchronization, JSON decoding/equality and assertion loops, accessibility queries, restore/resave checks, conditional failure screenshot and termination. Screenshots are failure-only.

Source inspection verifies counts and wait/loop bounds. It cannot establish launch, gesture, synchronization, screenshot or miscellaneous runtime. None of these estimates is a measurement or guaranteed execution upper bound. Apple execution must validate the planning assumptions; a slow or timed-out run must fail and prompt a revised plan.

## Source-required floors and historical replay

The live runner independently verifies a hash-pinned trusted contract for all six complete test-file hashes, declarations, non-test setup/teardown bytes and all three reachable shared-helper files. Old/custom profiles cannot suppress these floors by omitting estimates or plans; low future observations remain stored but cannot reduce the effective 900 seconds. A claimed current plan must retain exact inventory and source-bound provenance. Any protected source/helper remaining requires all six methods.

The frozen club R2 runner, CI gates, workflow, profile and full 712-method UI source index are preserved as fixtures. Existing club assertions run against that exact historical projection, including the original 67 shards and source-floor negative controls. The profile inverse removes only the reviewed six-method layer and verifies the exact prior canonical hash. Current runner tests additionally verify that real historical 712/147 and 710/146 sources retain their exact historical totals; unrelated custom profiles preserve their original observed-duration semantics.

The immutable initial author input remains separate. Any later functional repair is incorporated only by its verified delta, with UI/helper bytes rechecked before final freezing.
