# L12 public official-event browse dates

Status: client read/display slice implemented and focused-tested; L12/J15 launch acceptance remains incomplete.

## Owner, baseline and boundaries

Owner: L12 market browse date agent, issue #138, branch `codex/l12-official-device-dates-20261104`.
Public integration baseline: `eec839502b11f1119a6ede212c768bb3f2de4f29`.
Frozen backend: `58f4cc429b0d0e3035ccdf1bd4a9c3dfd76eb9a4`.

Re-read public launch plan sections 2 and 4 and issue #138. At the start, #138 still had no comments/assignees; remote `codex/l12*` had only this agent's already-delivered business-time branch, and no `codex/l6*` branch was found. Existing search-date presets already cover device zones/DST, so they were not duplicated. Claim is recorded here because public comments are prohibited by the current task. This branch is independent of the first L12 time-parser branch.

Exact write whitelist:

- `Core/OfficialEventDetailPresentation.swift`
- `Tests/CoreTests/OfficialEventDetailPresentationTests.swift`
- `Tests/CoreTests/OfficialMarketBrowseTests.swift`
- `docs/launch/l12-official-device-dates-20261104.md`

No SwiftUI layout/copy, shared session/composition/runtime/project/CI/manifest file, authentication, permission, payment, server or dependency was changed.

## Problem and resulting path

An event beginning at `2026-07-05T00:30:00Z` displayed July 5 on a Los Angeles device because the detail projection fixed its calendar to Shanghai. It now displays July 4 on that device, and continues to display July 5 in Shanghai. Server timestamps, event status, countdown, duration, participation rules and all request semantics stay unchanged. Zone-free text does not become a guessed instant.

Actual existing normal-entry source path:

1. `App/SessionHomeFeedView.swift` opens `OfficialEventsBrowserView` with the session reader.
2. `App/OfficialEventsBrowserView.swift` loads public events and links to `OfficialEventDetailView`.
3. `App/OfficialEventDetailView.swift` reads event detail and invokes `OfficialEventDetailPresentation(event:now:)`; its new default uses the current device time zone, so no new host injection is needed.
4. Existing `OfficialEventService` builds `GET api/official/events` and `GET api/official/events/{id}`. The frozen public backend `ApiOfficialEventController.java` has those exact mappings. The public mini-program `pages/activity/official-detail/index.js` uses `chinaParts`; native device display intentionally follows launch L12 time-zone requirements instead of retaining that fixed-zone presentation. Mini-program and backend sources were not modified.

There is no new mutation here: retries and reopening issue the same GET. Transaction UNKNOWN recovery is outside this read-only slice and is not claimed.

## Validation

Official `swift:6.0-jammy`, Swift 6.0.3, image digest `sha256:95f6ef898992dc840b35517e780f6f6db9661432775ab0b33cc0a531ea749bdb`. Test container uses `--network none`.

Result: **15 tests passed, 0 failures**: 10 existing detail tests and 5 market browse tests. The latter cover:

- guest list → detail request, server-data decoding, CN/US projection;
- exact GET paths, city query, no Authorization/body or mutation;
- network failure propagated, explicit retry, new reader/reopening and changed device zone;
- US DST fold, year boundary, half-hour zone and invalid/text dates;
- unchanged countdown, CTA and every fact except the displayed date range.

An isolated temporary SwiftPM package copied the following complete production files byte-for-byte, without stubs or editing their implementation:

`OfficialEventDetailPresentation.swift`, `OfficialEventContracts.swift`, `OfficialEventService.swift`, `APIConfiguration.swift`, `AuthRequestBuilder.swift`, `AuthService.swift`, `Account.swift`, `OfficialPrivatePresentation.swift`, `OfficialActionContracts.swift`, `OfficialEventSyntheticFixtures.swift`.

The package's test target copies both whitelisted test files. Its only dependency is its own `QuestifyCore` target, and it is run with `swift test -j 2`. All 10 production and 2 test copies were compared against the worktree after the successful run. Existing auth/action files were compiled only as transitive dependencies, never modified or called by this slice. No auth/payment action or business network request was made.

`git diff --check` passed. Existing Xcode source registration already includes the modified presentation; new Core tests are discovered by SwiftPM. L1 owns any required current-CI manifest refresh after integration.

## Remaining evidence and restricted work

These are transport-fixture and Core tests, not a real deployed-backend or UI/device acceptance run. No approved test deployment is wired in the integration base (`RegionalLaunchConfiguration` supplies no reviewed deployment). Real backend, simulator/device, English/Chinese screen, clean-install/restart and full repository tests were not run; CI was not dispatched. Reopening is tested by creating a new reader and re-reading, not by killing an app process. No private source, PR, public comment, production write or real transaction was involved.

Whole L12 remains open: Apple/SMS/email authentication, payment/StoreKit/channel selection, permissions and new dependencies are restricted under the current task. Other still-undelivered L12 work includes currency/tax definitions, market gating, security/review pages, privacy declarations, backend bilingual errors, real business-zone contracts and CN/US login/browse/order acceptance. This safe slice does not establish that those independent tasks are done.

## Delivery and local cleanup

Push this slice to its independent branch in code/test and documentation batches. Fetch the resulting branch head and compare every changed file blob with local bytes before cleanup. Only those verified files, with no later uncommitted edits, may be removed locally under the user's cleanup rule. GitHub commits remain the recoverable source; do not commit cleanup deletions or remove unrelated files, logs, receipts or unverified work.

First code/test batch `7efc2db72c5903f2f8c258ec34706fc185d517e2` was pushed, fetched back, and all three changed blobs matched local bytes.
