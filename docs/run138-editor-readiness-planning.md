> Superseded integration note: the current runner now dispatches through the strict entry layer. UI52 adds35 seconds and the approved UI37/UI40 increment adds80, so the final current delta is275. See `run138-ui37-ui40-readiness.md` and the final candidate plan. The original +160 proposal below is retained as historical derivation.

# Source-bound Run138 readiness cost candidate

This is an independently runnable planning layer. No current profile, historical hash/value, shared reveal helper, active runner, workflow or 1800-second deadline is changed. Nothing in this document is an Apple measurement.

## Exact new work

Four complete methods each add one reveal, at most ten gestures and eleven viewport/target evaluations. There are no new explicit waits. Reuse the existing engineering allowance of three seconds for one query-plus-gesture slot: one second for the viewport/target query phase and two seconds for dragging/settling. Charge all eleven slots, including the terminal evaluation, as complete slots. That is 33 seconds for review. The root Form path also performs two initial AX lookups, charged at two seconds each, yielding 37 seconds. Round each increment upward to 40 seconds. These are conservative planning assumptions, not hard wall-clock bounds. AX latency remains unmeasured.

No speculative saving is credited for shorter subsequent scrolling, compact DEBUG chrome, early Run138 failure times, or historical timings from an incomplete journey. All old complete-method floors remain counted.

- UI1 complete review: 150 + 40 = 190 seconds, migrated intact to `ProjectEditReviewReadinessFlowTests.testLocalEditReviewAndCancelledConfirmation`.
- UI1 whitelist: 150 + 40 = 190 seconds, remains in its original class.
- UI33 selected cover: effective historical 908 + 40 = 948 seconds. The retained old comment/raw estimate of 900 is not rewritten.
- UI35 current review: effective historical 906 + 40 = 946 seconds. Its retained old comment/raw estimate is also unchanged.
- UI56 gap direction: zero added operations and zero added cost. Same existing reveal/tap, same ten-gesture bound and waits; only direction at fresh chapter entry changes. Full helper before/after bytes are pinned.

Total increment: 160 seconds. New over-900 exceptions are scoped only to the exact UI33 948-second and UI35 946-second method/source identities. The original 908/906 exceptions remain untouched in historical input.

## Complete classes and partition

The original ProjectEditFlowTests cost is 1440 seconds. Moving its complete 150-second review journey out and adding 40 seconds to whitelist yields 1330 seconds. The new review class costs 190; UI33 costs 948; UI35 costs 946.

The original 79-way deterministic class partition is reused. All 736 methods execute once in 163 classes. Maximum current group load is 1465.141 seconds; with the unchanged 300-second startup reserve it is 1765.141, below the unchanged 1800-second deadline. The complete candidate total is 104865.381 seconds. The candidate plan records every resulting group and cost.

Without moving the complete review method, UI1 would cost 1520 plus 300 startup = 1820 seconds. More groups cannot fix an oversized indivisible class. No estimate was squeezed to avoid that fact.

## Files and preservation

- `tools/run138_editor_readiness.py`: validates every current UI source, changed App/project file, untouched profile, copied helper and complete method; restores exact previous source; invokes the original cost chain; adds all four 40-second allowances and partitions complete classes.
- `tools/run138_editor_readiness_contract.json`: pinned current/previous UI inventories, identity hashes, method-body hashes, original floors, scoped new assumptions/exceptions, and unchanged limits.
- `Tests/ContractChecks/fixtures/project_editor_readiness.json`: full source hashes and exact inverse spans for every scoped source change, including the moved method, new class, project wiring and direction-only helper.
- `tools/tests/test_run138_editor_readiness.py` and `Tests/ContractChecks/test_project_editor_readiness.py`: source/geometry, migration, added-cost and negative mutation controls.

The original 736 identities, all original assertions and full original helper bytes are restored before historical planning is called. The inverse never erases the new work from the current cost result. Unknown source, missing/duplicate spans, missing class, changed helper, weaker maximum-text assertion, altered profile, widened exception, changed deadline/reserve or uncharged operations fail closed.

The independent DEBUG history-fixture lifetime projection can compose: this layer does not freeze the implementation bytes of `branch_history_handshake_planning.py`, whose own reviewed source guards still apply. Its strict App fixture inverse is used by the original chain when present.

## Reproduction and activation boundary

Run `python3 tools/run138_editor_readiness.py --output candidate-plan.json` and `python3 -m unittest Tests.ContractChecks.test_project_editor_readiness tools.tests.test_run138_editor_readiness -v`.

This candidate does not modify `run_ui_shard.py`, `ci_gates.py`, the old profile, old assertions or workflow. Existing guards deliberately reject actual new source until a reviewed entry adaptation is activated. That adaptation must dispatch the current source to this layer, leave exact restored historical input on the original path, and give unchanged historical assertions an exact prior-source context. The adapter itself needs strict before/after binding. Applying only the source patch is not a claim that active CI is ready.

Apple compilation and full-method execution remain unperformed. Root review and final combined-current validation are required before integration or publication.
