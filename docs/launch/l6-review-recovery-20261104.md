# L6 merchant review recovery delivery

Status: partial implementation, **not launch acceptance**. No public issue comment,
PR, workflow dispatch, production access or real transaction was performed.

## Scope and ownership

- Issue: https://github.com/liboyang42-cpu/chengyin-ios/issues/132
- Plan read first: sections 2 and 4 at `eec839502b11f1119a6ede212c768bb3f2de4f29`.
- Public integration base: `eec839502b11f1119a6ede212c768bb3f2de4f29`.
- Independent branch: `codex/l6-review-unknown-readback`.
- Frozen public backend contract: `liboyang42-cpu/hengyin` at
  `58f4cc429b0d0e3035ccdf1bd4a9c3dfd76eb9a4`.
- Sole owner of this specific recovery subflow: this L6 task. No claim to the
  other club, merchant or cooperation subflows is made here.
- Issue 132 had no comments. Public branch inspection found no L6 branch before
  this task. Existing club/merchant/cooperation implementations and original
  writers were inspected rather than duplicated. No private repository was read.

Exact file whitelist:

1. `Core/MerchantReviewReplyRecovery.swift` (new)
2. `Tests/CoreTests/MerchantReviewReplyRecoveryTests.swift` (new)
3. `tools/check_l6_review_recovery.py` (new)
4. `App/MerchantReviewReplyRecoveryView.swift` (new plain native view)
5. `App/MerchantBusinessViews.swift` (three-line recovery entry only)
6. `docs/app-composition/l6-review-recovery.diff` (shared project handoff only)
7. `docs/launch/l6-review-recovery-20261104.md` (this evidence)

AppSession, Composition, Runtime, actual PBX project, CI definitions, manifest,
backend, authentication, permissions and money rules remain untouched.

## Implemented behavior

The existing normal merchant workspace already reaches reviews, its editor,
confirmation and original `MerchantBusinessCoordinator`/writer. Recovery is added
to that reviews page using the existing durable operation journal and reader.

An unconfirmed operation can be reopened after restart. The user can read its
current review state through the original management-list service. Every page
re-fetches merchant access. Account, epoch, authorization generation, journal realm,
exact durable intent, store and permission snapshot must remain current.

Each action reads at most five pages; continuation and refresh are explicit.
Missing, moved or hidden rows do not prove rollback. A failed read, account change,
cancellation or dismissal cannot publish a late row. The displayed result is
invalidated when its context or journal record changes. No recovery action
dispatches a mutation or completes an unknown intent. No tokens or review text
are added to the journal. New native copy follows the app's English/Chinese locale.

## Why UNKNOWN cannot be closed under the frozen contract

Inspected public backend sources:

- `ApiMerchantReviewController.java`: `/api/merchant/reviews/manage`, `/reply`,
  `/reply/update`, `/reply/delete`, `/manage/report`.
- `MerchantReviewServiceImpl.java`: reply replay binds actor, request ID and a
  fingerprint containing original version and content. Delete may return current
  absence as replayed; it does not prove identity of a particular original request.
- `MerchantReviewVO.java`: management rows expose state/version/reply, not the
  original request ID or an authoritative operation outcome.
- `chengyinhub-xcx/pages/merchant/reviews/index.js`: existing review workflow.

There is no read-only review-operation receipt route in the frozen controller.
The existing durable journal intentionally holds operation identity, not the
original version/content. Consequently neither matching text nor a newer version
can settle the original operation. This delivery preserves its lock. A future
backend contract for exact actor/store/request outcome is required to safely
complete UNKNOWN recovery; that endpoint was not invented or called here.

## Verification

Executed:

- `python3 tools/check_l6_review_recovery.py --swiftc <Swift-6.0.3>/usr/bin/swiftc`:
  **12 checks passed**. Compiles the unchanged recovery source plus production
  JSON/access types, record validator and durable journal. Host reader/document
  are explicitly test doubles; this is state-machine evidence, not HTTP acceptance.
- `swiftc -frontend -parse` on both changed App files, new Core file and XCTest
  file: passed. Parsing does not typecheck SwiftUI.
- `git diff --check`: passed.
- `git apply --check docs/app-composition/l6-review-recovery.diff`: passed.
- `python3 tools/check_scaffold.py`: current checkout stops at unregistered new
  files until the handed-off PBX diff is applied. On a disposable copy with that
  diff, registration passed, then the check failed on existing localization keys
  `square.and.arrow.up` and `square.stack.3d.up`. A separate pristine base archive
  reproduced the same localization failure. No check was suppressed or changed.
- Scanned delivered text for private-key markers and common credential prefixes;
  no matches. Test tokens and example domains are synthetic, with no live calls.

Not completed/run:

- Full `swift test --filter MerchantReviewLoadedPagesTests`: attempted on Linux,
  blocked before tests by existing `Core/ClubGovernanceIntentStore.swift:2` import
  of Apple `CryptoKit`. No project dependency was added to get around this.
- The nine new HTTP/XCTest journey tests were authored but **not run**. The first
  exercises original writer timeout, durable reopen, current-state read and
  retained UNKNOWN lock through the real business adapters with a fake HTTP wire.
- Xcode build, simulator/device, screenshots, real test-backend journey, mini-program
  runtime regression, English/Chinese visual checks and CI were not run.

## Delivery and next integration steps

Batch 1 commit: `dd0de9baddec91e1b390bc5f57a3d65559b6979a` (Core, XCTest, portable checker).
All three remote file bodies were fetched and compared byte-for-byte with their
local originals. Blob receipts matched local Git object hashes.

L1 must apply the exact PBX diff to register the two new application sources, then
refresh its own manifest. The source change adds a normal reviews entry but the
app target cannot compile it until those source registrations are applied.
Existing runtime write approvals still depend on L2/L1 composition; this task
does not broaden them. After integration, run the nine HTTP tests and a real
test-backend journey before making an acceptance claim.

Other issue-132 club, membership, merchant application/store/decor/claim,
cooperation, report/appeal, official-event, redemption and settlement flows were
not completed by this subflow. Membership enablement remains an owner decision.
There is no evidence supporting completion of the whole L6 lane.
