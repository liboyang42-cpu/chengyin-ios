# Reviewed route map, camera focus and branch-history integration

This candidate is based on development commit `7dd74b54a9aff8260198e5c00bc2feaac68337fe`, tree `4145c2a180e313844efbc5491e81893ccbe60b93`. It includes exactly the first three queued feature packages: route map `923e53c`, its camera-focus dependency `27755da`, and current-run branch history `ce7b163`. Later archive, attributes, chapter album, thoughts, opening and mode-2 work is excluded.

## Behavior and authority review

- The map uses the existing personal city-orientation host and existing node destination. It is an illustrative straight-line map with an equivalent list, not walking directions or a new location capability. Hidden nodes are absent; locked rows lose name, address and coordinate. Only an eligible current or completed node can open an existing task.
- A task already opened from the map retains its destination while the original coordinator is reviewing/submitting. This preserves review cancellation and entered answers. That exception does not create a fresh interaction context or authorize a new tap. Coordinator replacement, owner changes, changed snapshots and fresh reads retire the selection.
- Camera actions bind the exact read and visible view lifetime. They are one-shot. Missing coordinates and unsupported polar/date-line extents leave the camera unchanged and show a list/task fallback. Inspection never changes the current node or starts navigation.
- Branch history uses the current authoritative route state already read by the normal runtime. It never merges earlier history, adds a request, exposes hidden node names, navigates to a historical node or alters progression. Missing/malformed/oversized logs stay unavailable. Original server order and repeated edges are retained; bad-row gaps remain visible. Times are bounded and timezone-neutral.
- Existing session, mutation, media and production permission factories are unchanged. The new dedicated history string table is registered with the exact supported localization helper, rather than weakening the dynamic-key audit. The common catalog retains every old key/value and original ordering and adds only 36 keys.

## Whole-method UI planning

The authors' independent proposals were not measurements. The combined review explicitly expands all launches, helper calls and waits. The selected engineering assumptions are 90 seconds per fixture launch, the sum of explicit wait caps, two seconds per possible reveal-loop iteration, and 60 seconds for remaining whole-method work including setup/teardown and conditional failure evidence; totals round upward to ten seconds. None of these assumptions is a measured duration or guaranteed runtime bound.

New totals are route-map 2,230 seconds, camera-focus 2,370 seconds, and branch-history 1,550 seconds: 6,150 seconds across 18 complete methods. Multi-launch methods include all launches. No old measurement, estimate, provenance, plan, reserve or deadline is reduced.

Each of the three new multi-method classes would exceed the whole-class scheduling limit or prior margin under these assumptions. Only those unpublished scheduling wrappers are split into two direct XCTest classes each. All 18 original method declarations and every helper body are retained byte-for-byte, apart from the class name and empty separator lines. No method, journey, assertion, loop, wait or screenshot is split or deleted. The exact mapping and original source snapshots are retained in `tools/tests/fixtures/player_map_history/whole-method-migration.json`.

The combined source has 736 methods in 159 indivisible classes. Total complete-method cost is 104,237.381 seconds. Exhaustive deterministic recomputation finds 77 shards first meet the unchanged 1,800-second deadline; 78 preserve the prior 30-second margin at 1,770 seconds including the unchanged 300-second startup reserve. The per-method maximum remains 900 seconds.

## Historical preservation and negative controls

The entire prior 73-shard profile is reconstructible exactly, including all 647 retained observations. Its original 20 budget test bodies run unchanged against exact frozen source/profile fixtures; the 67-shard and older projections remain reachable. The new 20 live budget checks separately validate all 736 methods, every current class, the complete workflow outputs and all current floors.

The new source-required floor contract is SHA-pinned independently of caller profiles. Old profiles, erased current plan/provenance, lower observations, renamed/missing new classes, missing/changed helper files and corrupt contracts cannot lower current-source floors. Genuine byte-exact historical source/profile pairs remain supported, as do unrelated custom test suites. Current profile provenance and whole-method derivations must match the trusted source record.

## Execution limit

Swift typechecking, Apple SDK builds, Core/AppUnit/XCUITest execution for these three additions, screenshots, actual MapKit camera behavior, VoiceOver, physical devices and live account/provider acceptance are NOT_RUN in this Linux review. Run 129 results apply to the parent commit only. The current running CI is not cancelled or displaced by this candidate: publication is held for coordinating-owner scheduling after review and Library preservation.
