# P1 / S1 / L1 native presentation reuse

Baseline: `7203de129c5daedc1836ea95e3d34d11aca735cb`, tree `6f2284c2e52e23cbb1e13b2b04a9692416d1157b`. Finite source changes only. This is not Apple runtime, production-provider, permission, release, or full three-day UI acceptance.

## Inspected presentation purposes

| Surface | Existing purpose and owner | Decision |
| --- | --- | --- |
| Participation details | Account-history row opens one large sheet; order lifecycle is a child in its NavigationStack | Keep the large sheet. Verification preparation, member template and support are now NavigationLinks inside it. Preserve their existing session/approval implementations. Gameplay remains an explicit root route after the sheet's onDismiss |
| Short selectors / summaries | Existing MerchantOrders and WithdrawalSupport use medium/large. Square report uses medium/large selection and a distinct large confirmation | No redesign or blanket conversion; not changed by this packet |
| Editing / transaction / privacy review | Existing social editor protects dirty drafts and busy review; bank and verification reviews retain sufficient large/default-sheet space | Leave their ownership and discard/confirmation semantics unchanged. Existing tests remain required |
| Public photo gallery | NativeMediaGalleryEntry owns one fullScreenCover; viewer has its own navigation title, close and paging controls | Keep full-screen. Reflow paging vertically at accessibility text sizes; explicit decode failure and retry. Remove the container-wide accessibility ID so controls retain their own IDs |
| Stamp preparation / capture | Preparation and upload/create review are a pushed Form. Only the camera controller is full-screen | Keep that split. Gate stale results before dismissal, restore accessibility focus, and show ProgressView only while uploading/creating |
| Poster preparation / scan | Preparation/review is a pushed Form; NativeQRScanner is the full-screen child | Keep the existing scanner and its permission/unsupported/denied/cancel paths. Add generation/active-scene/capability checks and background cleanup; no new permission request |
| Application status summary / capsule | The separate W1 change owns ActiveDestinationSummary in safeAreaInset, with existing destination/phase data and navigation | Do not create a second session or presentation owner merely to add a pill. This packet adds no ActivityKit, live activity, background task, global overlay or new capsule |
| Settings, sound, support, legal, attributions | Existing Form, native controls/NavigationLinks, one persisted language owner, read-only market, missing-document states | Production settings files are unchanged. Add regressions for Follow System persistence and maximum-text legal navigation in both languages |
| Loading / unavailable / errors | Existing ProgressView and static text/ContentUnavailableView | Preserve the native baseline. Busy media operations have one loading label. Invalid image decoding must exit to retry; disabled capabilities have static explanations. No Shimmer dependency |

## Finite implementation

- `App/PlayerJourneyViews.swift`: selected detail stores its opening scope; queued gameplay route is consumed once and checked both when queued and after dismissal. Scope/auth invalidation clears pending route and return focus. Support/template/verification stay in the current sheet's NavigationStack. Existing order lifecycle and play-session implementations are reused
- `App/NativeMediaGallery.swift`: one authoritative full-screen owner, local focus return to the opening image, cleared on source/scope invalidation; maximum-text paging layout; explicit decode failure instead of a nil-image spinner; close/retry remain native controls
- `App/RoamStampCameraView.swift`: existing full-screen native camera and consent gate retained. Stale callbacks cannot dismiss a newer camera. Camera-disable/background invalidation cancels local work. Only uploading/creating uses ProgressView
- `App/RoamPosterScanView.swift`: existing full-screen scanner retained. Callback generation, foreground and capability checks precede the action. Background/disable invalidation clears transient review/work without resetting a completed terminal result. Only locating/preflighting/submitting uses ProgressView
- `App/ModuleFixtureSupport.swift`: only two additive routing lines; integration must apply hunks, not replace the shared fixture file
- One independent DEBUG fixture, two independent UI test classes and one static regression file. Fixtures use synthetic in-memory readers and rendered color pixels, never a network or camera provider. Scope invalidation is triggered by a real fixture read event, not a timer

## Localization and integration

No production copy or localization key is introduced. `Resources/NativePresentationReuseLocalizations.fragment.json` contains 29 exact existing entries for equality verification only. Do not replace `Localizable.xcstrings`; assert these entries match the integrated catalog and preserve every other key. No dependency, project configuration, provider, grant, entitlement or backend file changes.

Regenerate `Questify.xcodeproj` with `python3 tools/generate_project.py` after applying the finite patch, so the independent fixture/test sources are included. The packet intentionally omits the generated project. The exhaustive UI class discoverer finds both new classes automatically; no workflow or shard-router replacement is needed.

## Verification

| Check | Result |
| --- | --- |
| Published baseline manifest before copying | PASS: 1,786 tracked files matched |
| New static P1/S1/L1 regressions | PASS: 12 |
| All public Python contract tests | PASS: 778; SKIPPED: 46; total 824 |
| Tooling tests | PASS: 86 |
| Project generation / scaffold | PASS: deterministic generation, 904 Swift source files, 7,023 bilingual keys |
| Tree-sitter parse of all 8 changed/added Swift files | PASS: 0 recovery diagnostics; not a compiler |
| Parser self-tests | PASS: 14 |
| Existing player-journey source checker | PASS |
| Existing media-destinations standalone source checker | FAILS IDENTICALLY ON BASELINE AND WORK: obsolete fragment assumption for `withdrawal.support.copyWeChat`. Unrelated support file/key/checker not changed |
| Swift compiler, Xcode, Apple SDK type checking | NOT_RUN: absent in Linux |
| All 10 new simulator tests | NOT_RUN |
| Small/main-size screenshots, English/Chinese, normal/accessibility5, light/dark | NOT_RUN; authored cases are not visual evidence |
| Real Reduce Motion, VoiceOver reading/focus return, camera/QR denial and cancellation, device/background behavior | NOT_RUN |
| Existing dirty editor, nested order review and duplicate-submit Apple regressions | NOT_RUN; their production implementations were not changed |

The DEBUG Reduce Motion launch flag only affects app code that reads its existing fixture-aware property; it does not turn on the iOS accessibility setting. The gallery's UIKit zoom already checks the real system Reduce Motion setting. Actual VoiceOver and system-motion validation remains a separate Apple-device/Simulator gate.

## New authored UI cases (all NOT_RUN)

1. Gallery English paging, close, reopen at selected image
2. Gallery Chinese accessibility5 / dark / fixture motion setting, paging and close
3. Malformed image ends at retry and close; explicit retry recovers using fixture bytes
4. Scope changes on the next image read; viewer dismisses and can reopen
5. Disabled media/stamp/poster entry points have no spinner or permission dialog
6. Participation support opens inside the sheet, returns, closes and reopens
7. Gameplay root route occurs after sheet dismissal
8. Participation load failure retries; scope expiry dismisses details
9. Follow System persists across a relaunch/device-language change without changing US market
10. Legal missing-document views scroll/navigate/back/reopen at maximum text in English/light and Chinese/dark

Real-media capture and submission, private data boundaries, source support configuration and transaction receipts are not simulated as production successes. No Apple acceptance claim should be made until the exact integrated commit runs the required cases.

## Independent integration review

The scoped read callback and scope observer no longer both erase participation rows. Accepted rows carry their immutable read scope and are visible only in that scope; the observer immediately clears sheet/focus/pending routes, while the read task owns row replacement. This avoids callback-order dependence when a new-scope read completes synchronously. The existing fast synthetic scope-expiry/reopen UI case remains required; Apple execution is pending.

The standalone media checker now validates used keys against the merged bilingual catalog, preserving its original fragment checks. Copy-WeChat belongs to the existing presentation fragment; missing and blank translated-key negative cases fail. Bank/support behavior is unchanged.

## Current-head reconciliation (2026-10-03)

Reconciled onto `932fb38e657b23bc0a4c6f6293da9f6f42a3eb97` in an isolated checkout. The shared fixture router is three-way merged; later lifecycle/test fixes remain intact. The project is regenerated from the current generator. Ten duration entries remain explicitly unmeasured estimates; no measured timing is overwritten.

Independent review corrected a prior overlay error: the participation row-scope condition had been placed in CompletedPlayHistoryView, where that state did not exist. The condition now belongs only to ParticipationHistoryView. The regression slices the exact participation declaration and row boundary, and a separate check prevents the undeclared state from leaking into completed history. Historical string checks and parser success were insufficient to detect this compiler error. Apple compilation and the complete hosted suite remain mandatory.
