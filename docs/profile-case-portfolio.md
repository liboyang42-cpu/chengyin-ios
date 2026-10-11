# P107 portfolio description and existing images

This second slice layers on the sealed nickname/introduction field editors. It adds Account → Edit profile → Portfolio, a cancellable description draft, existing-image preview, and the existing whole-profile review/save/readback path. It does not add image upload or removal.

## Source contract

MASTER v10 P107 identifies `pages/gerenziliao/gerenziliao` and openPop2/cancel2/confirm2. At source ref `f859cd6e2618f618a53f5cd33949259828e86313`:

- Mini JavaScript copies `casePicsList` and `caseIntroducton` into local scratch. Its description handler and save payload use the exact misspelled field `caseIntroducton`.
- Current Mini WXML exposes images in the portfolio sheet but does not wire its description input. The native description field is an explicitly requested, source-contract-backed addition, not claimed current Mini visual parity.
- `UmsMemberUpdateDTO` defines a String `caseIntroducton` with its getter/setter; `SelfMemberVO` includes the same field in the authenticated self projection.
- `ApiUmsMemberController.updateUserInfo` (652–729) determines the owner through `getAppUserId()`, checks text, and copies `request.getCaseIntroducton()` into the member update. There is no client-selected member ID.
- `UmsMemberMapper.updateUmsMember` (194–235) updates `case_introducton` only when the DTO value is non-null. Omitted/null requests preserve it; an empty string clears it.

The delivery evidence records the exact five source blobs and SHA-256 values. Private source bodies are not part of the native patch or distributable package.

## Behavior and safety

- Missing `caseIntroducton` leaves description editing unavailable but permits existing-image inspection. Explicit response null means editable empty text. Wrong types fail decoding rather than inventing a baseline.
- Open uses the exact current staged value or the snapshot value. Cancel, swipe dismissal and reopen retain the same local-field semantics as nickname/introduction. Done only stages description bytes; there is no independent save.
- `ProfileEditDraft.caseIntroduction == nil` means preserve. An explicit empty string means clear. Description text is not trimmed or Unicode-normalized. Confirming the original value restores nil/no-op.
- Payload encoding uses `caseIntroducton` only for an explicit edit. Untouched descriptions are omitted. Existing avatar, contact QR, casePics and preference preservation remain intact.
- Review checks the original description against a fresh self snapshot. Confirm checks the complete reviewed snapshot and exact description bytes again. Exact changed-description readback is required before a known acknowledgment can unlock. Unknown writes remain locked even if a later read matches.
- Description participates in draft/snapshot byte comparisons, avatar fingerprints, whole-page dirty/exit/reload protection and stale editor detection. Clearing a staged avatar retains the description draft.
- Gallery projection removes blank semicolon entries as Mini does, preserving nonblank bytes, order and duplicates. It never rewrites casePics. At most 100 images are previewed and omitted counts are explicit.
- The existing NativeMediaGallery handles paging, zoom, close, loading/error states and origin-reviewed anonymous reads. A unique field-edit scope retires the view on account/session replacement. The default reader remains disabled; approved reader injection is required for actual image bytes. No new origin, credential, service, endpoint or production capability is enabled.

## Integration and verification limits

Registration/localization: PENDING_PARENT_INTEGRATION. See the registration fragment. It lists seven new strings and two intentional discard-message overrides to cover portfolio text without losing existing unknown-save wording.

Apple: NOT_RUN. Swift, Xcode, app compilation, XCTest execution and native UI execution are unavailable in this Linux environment. Authored tests cover decode/encode/clear/readback, stale ownership, rejected/unknown outcomes, exact Unicode, field cancellation, and existing-image viewer return. They are not execution claims.

The DEBUG `portfolioImages` scenario uses reserved `.invalid` URLs and leaves the reader disabled. It verifies navigation and scratch retention without production image requests; it is not evidence of real image loading.

Targeted source checks, deliberate source mutations, private Mini synthetic execution, backend seam checks, before/after hashes and incremental patch replay are separate evidence. Full CI and historical exact-source admissions are not repaired or claimed by this slice. The prior sealed package remains unchanged.
