# P107 read-failure explanation recovery

Scope: P107 `retryLoad` / `saveInfo`, PA01 load/error/retry and session cleanup, F-ACCOUNT-001. This is a narrow error-presentation increment, not whole-profile parity or backend acceptance.

## Source and event mapping

The actual Mini `pages/gerenziliao/gerenziliao.js` `getUserData` preserves `res.msg` in the initial load error detail; `saveInfo` preserves rejected-save explanation. Its WXML binds those details to `cy-state-shell` / `cy-inline-error`. The native editor already has a literal `Text(verbatim: remote)` and rejected-write presentation, but the four read-failure exits of `ProfileEditCoordinator` discarded explicit `ProfileReadFailure.message`.

| Native phase | Existing status kept | Increment |
| --- | --- | --- |
| Initial load / reload | loadFailed / refreshFailed; unknown when locked | Present nonblank explicit server explanation after current-session/request/cancellation guard |
| Prepare review read | loadFailed | Same; no confirmation/write on failed read |
| Confirmed pre-write recheck | loadFailed | Same; consumed review cannot automatically retry POST |
| Post-dispatch readback | unknown | Same; acknowledged/unknown pending state is unchanged |

No networking error description, reflection, HTTP body parsing or new request is introduced. Nonblank server text is preserved exactly and rendered as literal text. Whitespace-only or absent server messages fall back to the existing localized status. Existing new-request and session-reset clearing remains unchanged. The original read/session guards run before publication, including when an unauthorized callback changes session.

Read failures retain the prior snapshot; the unchanged App model only overwrites a draft after a successful load. Retry reads cannot dispatch a write. An acknowledged write unlocks only on matching successful readback; an unknown write remains locked even after fields match.

## Remote admission scope

The product and appended Core XCTest sources reuse the reviewed read-error leaf. The remote admission changes only ten paths: this document, Core/ProfileEditCoordinator.swift, Tests/CoreTests/ProfileEditTests.swift, tools/check_profile_read_failure_contract.py, Tests/ContractChecks/test_profile_avatar.py, Tests/ContractChecks/test_profile_reload_discard.py, Tests/ContractChecks/test_profile_read_failure_remote_admission.py, tools/run138_editor_readiness_contract.json, its runner's contract digest pin, and tools/tests/test_gitleaks_configuration.py (historical contract input only).

The current contract appends four unique Coordinator inverse spans to the original five and preserves its original before hash. Only current support hashes and the matching runner pin change. Projection implementations, CI dispatch, source-index expectations, cost models and budgets remain unchanged. Historical readers preserve their original expected values and assertions. A separate current-stage gate rejects old source; historical input restoration does not count as new behavior validation.

## Verification and boundaries

The unchanged thirteen Python source checks are exposed through normal ContractChecks unittest discovery. Nine additional remote admission cases cover actual central validators, complete old contract/runner restoration, the historical reader inverses, nested frozen checker and Core XCTest hashes, current-source rejection, and copied-input dependency registration. Source mutations are negative controls; they do not execute Swift behavior.

Twelve new in-memory Swift XCTest methods are authored for initial/reload/prepare/pre-write/post-write failures, acknowledged versus unknown writes, read-only retry, text filtering, clearing, token replacement, cancellation and unauthorized callbacks. Every original Core XCTest byte remains as the complete prefix before the append.

Swift compilation and XCTest execution, Apple builds, simulator/device UI, VoiceOver, localization rendering and live service acceptance are **NOT_RUN** in this source-only verification. Existing remote avatar and reload failures must retain their exact baseline identities. Every changed protected input must also be checked independently because an earlier failure can hide a later mismatch. No aggregate repository success, backend acceptance, publication or CI completion is implied.

No App navigation, PBX, catalogs, shared product contracts, environment, permission, media upload or deployment changes are included. Avatar and all other capabilities retain their original defaults.

Remaining P107 work includes independently authorized phone-binding/media/works/QR contracts and device/service validation; this increment grants none of those capabilities.

The scanner configuration test retains all nine original methods, historical finding records and line numbers, line hashes, 92-entry ignore inventory, and scanner/workflow assertions. Only its historical contract input is restored through the exact current runner pin, bounded inverse, and complete original contract hash. Actual scanning still receives full current files; no ignore or scanner rule changes are included.
