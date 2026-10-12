# P049 roster bucket reading and existing correction return

## Base and exact permitted hunk

Independent base `41571fed5c27d4766d0bebb02e2800d798f1edbd`; no dependency on the13 sealed packets. Root verified that `App/ClubGovernanceViews.swift` at415 andc265 has Git blob `6475024c837dd105f6e9062737c80e2ebd4342ec`, and authorized only the `.roster` branch of `content(_:)`. Every byte outside that branch is preserved, including all other read pages, parent read/session logic and the existing correction form.

The unique master, `MASTER-v10-extracted-text.txt`, P049 lines1668–1671, lists `loadRoster`, `chooseRosterTab` and `correctAttendance`.

Mini revision `f859cd6e2618f618a53f5cd33949259828e86313`:
- `pages/club/event-ops/index.js`, blob `8619be05e9cf8f05b0fde678a30b723b6df6ace8`: lines14–19 define four buckets;61–87 define total and correction-window semantics;1019–1098 load, filter and enter correction.
- `pages/club/event-ops/index.wxml`, blob `1cc5d36acbd475f76309f5b82c5a768ff3cf6552`: lines67–108 show counts, bucket selector, empty category, member rows and correction affordance.

Gap before this packet: native `.roster` displayed all four full lists in succession, without bucket selection, total/count summary, a per-bucket empty state or server correction-window guidance.

## Ordinary flow

The existing ordinary event screen already opens `.roster`. The new content receives the actual accepted parent snapshot and context, so no callback defaults, fixture-only reader or AppSession injection is introduced. The existing read/refresh/error/identity ownership remains unchanged.

The screen shows total attendance roster count, all four bucket counts and a segmented filter: registered, waitlist, arrived and no-show. Only the selected bucket's members are displayed. Names and member IDs are shown together, with a localized unknown-name label where needed. A genuine empty bucket has its own message. The existing parent filter state holds the bucket preference, preserving selection while the parent clears/reloads its snapshot. The preference contains no member data or authority.

Total is exactly registered.count + arrived.count + noShow.count. Waitlist is counted separately. All four arrays and `phoneIncluded=false` are required before projecting anything; missing data is not displayed as zero. This view projects only member ID, name, waitlist state and correction version, never phone/financial fields.

Known server `correctionWindow.operable=false` suppresses correction entries and shows the closed-window notice. Returned nonempty string bounds are shown as server-returned clock strings, without guessing timezone or filling missing bounds. Unknown or absent operability follows Mini's legacy behavior and does not create a new block; the unchanged server preflight remains authoritative.

Waitlist rows never receive an attendance-correction entry. For other buckets, a known nonnegative correctionVersion is required. Missing version remains unknown with a refresh prompt, preserving the existing native contract rather than copying Mini's numeric default0. A genuinely returned version0 remains valid.

A correction row opens the existing `.correctAttendance` form with exact club/activity/member and expectedVersion. Its existing arrived toggle and reason input remain the user's explicit choice; this packet does not turn that existing form into Mini's one-tap mark-arrived action. No command payload, permission, write grant, prepare/confirm behavior or journal is changed. Closing/cancelling the form requests a fresh roster read; the selected bucket is retained.

## Route safety

Each correction entry captures the exact source snapshot, read context, read generation and rendered namespace. Opening checks current account/epoch, authorization generation, reader object, namespace, scope, snapshot equality, and equality of accepted-read and active-read generations. A pending refresh, stale row, changed version, account/authority/reader replacement or double tap cannot open an old target. The projection also refuses to mint routes for a different source context or a member in another bucket.

The existing coordinator still reads roster again when preparing a correction and checks the exact member/version and fresh check-in permission. That remains the only route to any separately authorized write. No actual attendance correction or notification was executed.

## Registration and verification

The fragment registers one new App source, one Core source, one Core test and one AppUnit test file, plus10 bilingual keys. This packet changes only the authorized roster hunk in the existing file. No shared form, existing Core contract, AppSession, PBX, aggregate catalog, CI, shared fixture host or other feature line was edited.

Executed locally:
- 37 focused structural checks: PASS. They cover exact-hunk preservation, ordinary snapshot wiring, count/privacy semantics, bucket-state retention, current-row gates and unchanged contracts.
- Existing governance contract suite:12 checks PASS.
- Four exact Mini Git blobs, including the P050 handoff source; roster source-function oracle PASS for scope payload, four bucket selections/counts, waitlist exclusion, refresh retention/empty bucket, known/unknown window, cancel and correction payload spy, privacy/missing-array rejection and denied-read guard. Transport/modal actions were local spies; no network requests occurred.
- Five Swift files: Tree-sitter syntax parse PASS. This is not Swift typechecking or Apple SDK/runtime verification.
- Before/after patch reconstruction, reverse-apply and all13 earlier packet hashes checked.

Authored12 Core and8 AppUnit cases: **all20 NOT_RUN** because Swift and Xcode are absent. Native build, simulator, UI/VoiceOver checks, screenshots and live-account reads are NOT_RUN. Synthetic authored tests cover current route→existing prepare→cancel→readback, version mismatch and fresh permission denial with zero sends.

Apple acceptance after central registration: ordinary event→roster, all four buckets including empty/long names, correct totals after attendance moves, selected-bucket refresh, known window closure, missing andzero version, current-target correction form/cancel/return readback, stale taps during reload, account/authorization/scope change, Dynamic Type and VoiceOver. No real attendance mutation should be performed without the existing required authorization.

## Separate P050 handoff

The delivery packet’s `evidence/P050-expiry-handoff.md` identifies a pre-existing request-shape discrepancy with exact Mini source and native lines: Mini POST `/api/club/governance/ban` sends `expiresAtEpochMs`; native `.ban` still requires `expiresAt` text. This packet does not repair or exercise it. Backend compatibility remains unverified and belongs to root/sixth.
