# Ordinary text QA: read the original action receipt

This is a source delivery with an exact integration handoff. Shared Runtime, App
hosts and PBX are unchanged in this branch. Apply `integration.patch` in the
integration owner's checkout to activate the flow. Until then the new receipt
adapter is not connected to the App's recovery buttons.

## Baseline and ownership

- Public `main`: `3971086a1feb3dc765a44153542c1d52eb9e4775`.
- Immediate base: public `codex/qa-text-input-20261108`,
  `9c11addfc82c8ce7c7989247aac4046216b140b5`.
- New branch: `codex/qa-receipt-recovery-20261108`.
- This work owns ordinary `qa.mode=TYPE` recovery only. The default TYPE behavior
  follows the existing form's absent-mode handling. An actual QA object and the
  original `SUBMIT_QA` payload with exactly `input` are both required.
- `HANGMAN`, `PICK`, `SHOT`, other QA modes, reaction challenges, points ledger
  and all backend groups remain outside this change. No other owner's files
  were included. The preserved original QA/word-fill candidates were not edited.

## Source contract and concrete gap

Public backend inspected at immutable commit
[`147754ba8740abf208bda75cf86ed5901cac4c02`](https://github.com/liboyang42-cpu/hengyin/tree/147754ba8740abf208bda75cf86ed5901cac4c02):

- [ApiAdvancedPlayController.java](https://github.com/liboyang42-cpu/hengyin/blob/147754ba8740abf208bda75cf86ed5901cac4c02/chengyinhub-admin/src/main/java/com/chengyinhub/web/controller/api/ApiAdvancedPlayController.java)
  exposes `GET /api/play/advanced/receipt` with `sessionId` and `idempotencyKey`.
- [AdvancedActionReceiptReader.java](https://github.com/liboyang42-cpu/hengyin/blob/147754ba8740abf208bda75cf86ed5901cac4c02/chengyinhub-system/src/main/java/com/chengyinhub/business/service/support/AdvancedActionReceiptReader.java)
  checks the authenticated owner, accessible session and original attempt log.
  It returns `{sessionId: String, idempotencyKey: String, view: Object}`.
  Missing receipts return 404: absence is not proof the original request did not
  execute. Conflicting/unreadable logs return 409. The reader is read-only and
  does not run state progression, expiry or settlement.
  Downloaded source SHA-256:
  `8c90ac7b799f76d452a77fe0e2521fe69c0df8dc5d61a503075b0231252f7baf`.
- [CheckReceiptProjection.java](https://github.com/liboyang42-cpu/hengyin/blob/147754ba8740abf208bda75cf86ed5901cac4c02/chengyinhub-system/src/main/java/com/chengyinhub/business/service/support/CheckReceiptProjection.java)
  preserves server redaction in the returned view. SHA-256:
  `2298efed31b37c6a99d2b87a47ec3bd8c295f076af683e8804a6d6e801f2cb0f`.
- [Existing mini-program host](https://github.com/liboyang42-cpu/hengyin/blob/147754ba8740abf208bda75cf86ed5901cac4c02/chengyinhub-xcx/pages/play/components/advanced-game/index.js)
  reconciles unknown actions through this receipt endpoint and checks the outer
  identity before accepting the view.

At the iOS base, `PlayAdvancedCoordinator.recover()` reads generic session state,
then exposes `retryExact()`. Generic rejection handling also clears pending on a
business rejection, including a read's 404. Generic state/version growth does not
identify the original answer. Adding receipt GET through that same generic error
handler would incorrectly discard the original request when its receipt is absent.

## Resulting flow after the shared patch

1. Keep the existing real TYPE input, frozen review and original
   `SUBMIT_QA`/`input`/review UUID idempotency key from the base branch.
2. If that action is UNKNOWN, both existing recovery surfaces call `recover()`.
   For this specific text pending request it performs one receipt GET containing
   only the original session ID and key. No answer, new UUID or action POST is
   sent by recovery. Calling the old `retryExact()` API is also fenced to GET.
3. Validate exact outer string session ID and key bytes, and original inner
   session/activity/topic/node plus strictly newer action version. The existing
   `PlayAdvancedState` parser and owner/generation/read-lifetime validation still
   run before accepting any view.
4. Clear only the matched pending request. Use the server view unchanged, even
   when the server says the answer failed. A historical receipt cannot replace
   a newer authoritative view. No client success, score or next-node inference.
5. Missing/conflicting receipts, malformed data, cancellation, disabled reads or
   lost transport retain the original pending and UNKNOWN. 401 or owner withdrawal
   hides state, marks stale and retains pending. A changed account cannot dispatch
   recovery or replay the old answer.

`integration.patch` contains exactly four files: the shared Runtime and PBX plus
the two existing UI hosts. `integration-preimages.json` pins every before/after
SHA-256. It is a proposal for the integration owner, not an applied App change.
There are no AppSession/Composition changes, resource additions, capability
enablement, backend changes, CI workflow changes or production defaults.

## Verification actually run

Using Swift 6.0.3 on cloud Linux:

```sh
python3 tools/test_qa_text_receipt_candidate.py --swift /path/to/swift --output /tmp/qa-receipt-tests
python3 tools/verify_qa_text_receipt_integration.py --swiftc /path/to/swiftc --output /tmp/qa-receipt-integration
```

- 11 Swift XCTest cases passed for the real new production decoder/query/failure
  policy. Dependencies are exact extracted production declarations, with source
  and fragment hashes recorded in `portable-test-evidence.json`. This isolated
  run does not execute the service or coordinator.
- Disposable-copy patch application verified all four exact postimages. The real
  checkout's shared bytes remained unchanged.
- `pbx_registration_only` passed; the temporary project's source, AppUnit and
  resource membership matched the existing generator without changing settings,
  target IDs, dependencies, schemes or existing object order.
- `check_scaffold.py` passed on the patched copy: 2,164 Swift files, 10,340 bilingual
  keys, references, scheme and generator equivalence.
- Swift frontend parsing passed for the patched Runtime/hosts and new production
  and test files. This is syntax checking only.
- Five real-coordinator AppUnit tests were added for original receipt GET/server
  failure, 404/409/mismatched key retention and later reconciliation, account
  switch, owner withdrawal during an awaited read, and current 401. They are
  syntax parsed and included in the PBX handoff, but were **not executed**.

The new test runner and verifier do not contact an application backend, run CI,
refresh source-inventory ledgers or edit the shared checkout files.

## Explicit remaining limits

- No Apple SDK/Xcode is present: no Apple type compilation, AppUnit run,
  simulator/device or real App acceptance is claimed.
- No real action, backend state read or production write was sent. Inspecting a
  public source contract does not prove its deployed availability.
- Process restart recovery remains unimplemented in the existing advanced
  coordinator: its pending request is memory-only. This change preserves UNKNOWN
  and owner fencing while that coordinator exists. It does not invent a durable
  answer store or claim a relaunched App can restore the request. The existing
  mini-program's redacted identity journal is separate integration work.
- The existing numeric-only `PlayAdvancedState` ID parser cannot consume IDs
  projected as strings beyond JavaScript's safe integer range. This change fails
  closed with UNKNOWN; it does not broaden the shared parser contract.
- Shared Runtime/PBX/host activation is pending the integration owner. The source
  inventory ledger was already stale on the base branch; it remains unchanged
  under the no-CI-adjustment instruction. No passing current-CI claim is made.
- Public push may automatically trigger configured Xcode Cloud as authorized;
  no workflow was manually started, rerun, changed or inspected for acceptance.
