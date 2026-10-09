# CI138 branch-history fixture lifetime candidate

## Evidence and scope

Baseline commit: `4bf6667f8c5d9d2d59a8063d7d54eaef7a338865`. Exact published tree: `82e9abd1afa6180815ef7ea5ea314d6eb692e036`. This candidate was built from an isolated archive of that tree. The reference checkout's local HEAD was not used as the baseline.

CI138 UI24 failed `PlayBranchHistoryFlowTests.testChineseMaximumTextUnknownNodeAndRefreshReplaceOldHistory` at line 42. The immediate empty-history fixture action was tapped, the ordinary history sheet reopened, and the original recorded rows remained instead of the required empty state. The test's original absence assertion was not reached. Retained Chinese screenshots show recorded history, so this was not simply an offscreen empty label. There are no retained recorder-identity or action-count diagnostics establishing the exact causal path in that run.

The published DEBUG Host initializes an ordinary stored recorder and owner every time SwiftUI reconstructs its value, but retains its model and handshake with `@State`. Its immediate refresh action configures the latest value's recorder, then loads the retained model, whose service may still own the original recorder. This is a concrete dependency-lifetime hazard consistent with the CI result. The retained handshake closure already captures a matched owner/recorder/model, which explains why its separately passing paths do not rule out the immediate-action defect.

## Candidate repair

The DEBUG Host retains one `PlayBranchHistoryFixtureState`. That instance owns the original session holder, recording transport, normal read-only coordinator and handshake. All fixture actions read that retained graph. Immediate refresh still configures exactly `[]`, route session 502/version 0 and awaits the normal model load. Neither gameplay nor production history presentation is changed.

A new mount gets a new graph and the original recorded scenario. Host disappearance still cancels the handshake; sheet dismissal semantics are unchanged. There is no timer, forced dismissal, network transport, new capability or alternate gameplay action. The optional AppUnit observer follows the existing public-merchant fixture's `UIViewRepresentable` pattern. It is absent by default, has no visible/accessibility surface, and reports the actual mounted graph and redraw revision. Its phase input allows the regression to wait for the normal read to reach ready without a sleep.

## Authored Apple regressions

The existing eight AppUnit entry methods and their assertions remain; two call additional helpers:

- Mount the actual `PlayBranchHistoryFixtureHost` in a window, wait for a ready-state observation, and force its parent to reconstruct it twice at the same identity.
- Require the fixture, recorder, coordinator, handshake and session to remain identical. Invoke the same immediate-refresh method as the toolbar. Require exactly the next nodes/route GET pair on the original recorder, empty presentation at session 502/version 0, and retirement of the original selection.
- Cancel a queued owner switch, replace the old history, arm another switch, remove the mounted fixture, and verify the actual disappearance callback observes canceled intent.
- Re-enter the fixture and require a distinct graph, clean handshake, original owner 9001/epoch 1 and recorded session 501/version 2. Refresh it and require the retired recorder's request count to remain unchanged.
- Keep write capability disabled and reward/ending absent. Existing standalone handshake tests still cover both consumed actions and suspended-read cancellation/cleanup.

The callbacks use bounded XCTest expectations with explicit failed-readiness guards and window teardown. They do not modify existing UI methods or their wait limits.

## Verification limits

Local Python ownership checks reject the published split-lifetime source and accept the candidate. Mutation controls reject removing state ownership, constructing a new action graph, mismatching the service/session closure, removing cancellation, and omitting the discriminating mounted assertions. These are structural source red/green checks, not executed SwiftUI reproductions. Tree-sitter parses the changed Swift files; it does not typecheck them.

Swift, Xcode and an Apple simulator are unavailable on this executor. Apple AppUnit/typecheck/runtime and a rebuilt complete UI24 run remain **NOT_RUN**. This is a locally checked candidate, not a claim that CI138 is resolved. Acceptance still requires the actual mounted AppUnit helpers and the unchanged complete `PlayBranchHistoryFlowTests` / `PlayBranchHistoryLifetimeFlowTests` to execute on a rebuilt Apple revision, including the previously unreached empty-state, row-absence and return checks.

All pre-existing UI assertions and source bytes, production model/presentation code, project membership, workflow files, budgets, measurements and protected hashes are unchanged. No push or remote CI rerun was performed.

## Historical critical-source projection

The old planning validator correctly rejected the two intentionally changed Swift
files because `critical_sources` pins their complete original bytes. No historical
pin was changed. The small caller now verifies the new adapter's complete byte hash
and passes its projected bytes through the original comparison.

The separate adapter binds both full current Swift files, both full historical
preimages, its contract, and the new Python proof files. It first verifies the current
pair and proof inputs, then applies exact byte-offset/text inverse spans and requires
equality with the full preimages and their original hashes. Every file comparison
uses `read_bytes`, so CRLF conversion cannot be silently normalized. Changed, missing,
moved, duplicated or truncated components, mixed old/new pairs, removed assertions,
and changed inverse offsets are rejected by dedicated negative controls.

A genuine historical checkout without any adapter artifacts still passes only its
raw original critical bytes through the unchanged comparison. Partial adapter
removal fails closed; absence of all adapter inputs cannot authorize current or
unknown source bytes. Existing UI/profile history, method inventory, time estimates,
measurements, workflow and original `critical_sources` values remain untouched.
