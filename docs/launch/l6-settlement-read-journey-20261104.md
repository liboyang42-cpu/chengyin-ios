# L6 cooperation settlement read journey

Status: read journey implemented and covered by fake-HTTP tests. **Not whole-L6
acceptance, an Xcode build, or a live-backend acceptance claim.**

## Ownership and baseline

- Issue: https://github.com/liboyang42-cpu/chengyin-ios/issues/132
- Sole owner of this specific subflow: this L6 task. No public claim comment was
  posted because this task prohibits public comments.
- Base: `integration/launch-20261204` at
  `eec839502b11f1119a6ede212c768bb3f2de4f29`, verified latest before work and delivery.
- Branch: `codex/l6-coop-settlement-read-journey`.
- Backend contract: public `liboyang42-cpu/hengyin` at
  `58f4cc429b0d0e3035ccdf1bd4a9c3dfd76eb9a4`.
- Read launch-plan sections 2/4 and issue 132; checked public L6 branches, the
  empty issue comments and current task history. The previously delivered review
  recovery branch is separate and is not a dependency of this branch.
- Inspected existing settlement readers/screens and reused them. No other current
  L6 owner or competing settlement-read branch was found. Private repositories and
  the user's computer were not accessed.

Exact file whitelist:

1. `Core/CoopSettlementDetailModel.swift`
2. `App/CoopSettlementDetailView.swift`
3. `Tests/CoreTests/CoopSettlementReadJourneyTests.swift`
4. `tools/check_l6_settlement_journey.py`
5. `docs/launch/l6-settlement-read-journey-20261104.md`

The two changed application sources already belong to the Xcode target; no PBX,
AppSession, Composition, Runtime, CI, manifest, permission or financial-rule change
is required or included. L1 still owns its normal integration/manifest refresh.

## Complete user journey within this scope

1. Use the normal cooperation workspace's host finance list or merchant business
   settlement list. Existing entries in `CoopFinanceProfitView` and
   `CooperationFlowWorkbench` still open `CoopSettlementDetailView`.
2. The detail reads the original `CoopFlowReading` service again, rather than
   authorizing or displaying a retained navigation row. Finance selects `topicId`;
   merchant ledger selects the settlement `id`. Every row is validated and all
   source identities must be unique before selection. Duplicate IDs cannot choose
   an arbitrary first amount.
3. The existing server-provided amount, breakdown, status and dates are rendered
   through the existing English/Chinese views. Unknown income remains unavailable;
   this change does not calculate a balance or change settlement rules.
4. A transient read error can keep the same record visible with the existing
   stale-error notice. Explicit retry reads the original route again. Permission
   errors, missing records, malformed payloads and ambiguous identities remove
   the old detail.
5. The new read lifecycle binds reader identity, an opaque exact-session scope,
   source and record ID. A token change within the same account/epoch rotates the
   scope. Account, endpoint/reader and record changes cannot reuse old content.
6. Page exit/background retires the adapter and clears private detail. Return or
   a newly created journey reads current server state again. Cancellation and
   older overlapping responses cannot replace a newer successful read.

This is intentionally a read-only journey: there is no original mutation to retry,
persist or reconcile. A payout action or a claim that an earlier write succeeded
is outside this flow. Neither a POST used by a read endpoint nor a credited status
causes a financial write.

## Frozen contract evidence

- `ApiCoopController.java`: `/api/coop/finance` returns host topics, adjustments and
  `isOwner`; `/api/coop/mybiz` requires server `MerchantPermission.FINANCE_READ`
  and resolves the current merchant owner before returning settlements.
- `chengyinhub-xcx/pages/coop/settlement-detail/index.js`: finance selects a topic;
  ledger selects a settlement. The source distinguishes initial failure, missing
  record, stale read failure and permission failure.
- Existing iOS `CoopFlowService`/`CoopFlowSessionReader`, `CoopFinanceProfit`,
  `CoopSettlementDetailModel` and the two normal list entries were inspected.

No backend, server permission, authentication or money rule was edited.

## Executed verification

`python3 tools/check_l6_settlement_journey.py --swift <Swift-6.0.3>/usr/bin/swift`

Result: **25 tests, 0 failures**:

- 6 existing detail-model tests.
- 8 new read-lifecycle tests (also available to the ordinary Core XCTest target).
- 11 fake-HTTP journey tests: normal host list/detail; merchant list/detail;
  transient HTTP failure/retry; HTTP 401 and captured-session expiry; same-epoch
  token replacement; dismissal/reentry; duplicate and malformed response; permission
  and missing record; overlapping reads; cancellation; reconstructed journey.

The portable checker creates a temporary Swift package. It compiles verbatim
production read methods, JSON values, request builder, session reader, actual App
adapter, amount presentation/parser and lifecycle. To avoid unrelated Apple-only
writer dependencies on Linux, the temporary service container includes only its
two read fields/constructor and omits mutation methods/configuration. No service
read method, parser, adapter or expected assertion is replaced. The fake is at
`HTTPTransport`. Test-only access helpers never enter the app. This is stronger
than a fixture-only state check, but is not a full app-target compile.

Other checks:

- `swiftc -frontend -parse` on both modified application sources and new XCTest:
  passed.
- `git diff --check`: passed.
- Shared-file diff: empty.
- `python3 tools/check_scaffold.py`: target membership checks pass; the existing
  baseline localization assertion fails for `square.and.arrow.up` and
  `square.stack.3d.up`. The preceding L6 delivery reproduced those same failures
  on a pristine archive of this exact base. Neither failure was suppressed.
- Delivered text scanned for private-key markers and common credential prefixes:
  no matches. All test accounts/tokens and example domains are synthetic.

## Limits and handoff

Not run: full app/Core suite (Linux lacks the base's Apple `CryptoKit`), Xcode or
SwiftUI typecheck/build, simulator/device navigation, English/Chinese visual review,
real test-backend calls, mini-program runtime regression, CI or production calls.
The portable checker typechecks the actual Foundation-only App adapter, but it
does not typecheck the SwiftUI view model/view. Those remain native validation work.

Two batches publish the code/tests and then this report on the independent branch,
with `[skip ci]` and no PR. Remote contents are fetched and compared byte-for-byte
against the five-file whitelist. The verified task-owned checkouts/toolchain are
then removed according to the user's cleanup instruction. Unsubmitted work is
never deleted.

Code/test batch: `cffc3b55fffe3bf896d7553ec8d392f2ab298d56`. The four remote
file bodies were fetched and compared byte-for-byte with the local originals;
each blob receipt also matched its local Git object hash.

All other L6 write journeys, including the previously documented review UNKNOWN
receipt-contract gap, remain outside this delivery and are not marked accepted.
