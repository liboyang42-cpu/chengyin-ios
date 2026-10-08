# P032 conversation-row read / mute actions

## User-visible scope

Ordinary Account → Messages retains its existing conversation rows, segmented filter,
search and navigation. A native trailing swipe or touch-and-hold menu now opens the
review sheet for mark-read or mute/unmute. Full swipe never dispatches. Confirm is
explicit. If the writer is unavailable the controls remain disabled; this change
adds no production grant, default host, new writer, media operation or push/realtime
permission.

A current exact acknowledgment invalidates the account/source-bound shared list
read owner. A visible list handles that invalidation in its own current appearance;
an offscreen list rereads on its next appearance. The shipping read owner calls
`messagingConversations()` and replaces the list only with the successful server
response. No local unread reset or mute toggle is fabricated. Read failure shows
the existing error/retry state. The search/filter state stays outside the reloaded
subtree. Scroll position after successful replacement still needs device acceptance.

## Source evidence

The sole master plan's P032 explicitly names `onRowRead`, `onRowMute` and the
mini-program page `subpackageB/pages/im/list/index` (W01/W09/W11 client parity).
The source was directly fetched from the connected repository at
`ce61c0bbace743ff835cb297ef41c89b52181636`:

- [Mini-program IM list](https://github.com/liboyang42-cpu/chengyin/blob/ce61c0bbace743ff835cb297ef41c89b52181636/chengyinhub-xcx/subpackageB/pages/im/list/index.js), blob `1f6912406e2a3b524fe6a1776168afe3df35dbfa`: `onRowRead` uses POST `/api/im/read` with `conversation_id`; `onRowMute` uses POST `/api/im/mute` with `conversation_id` and `muted` equal to 1/0.
- [Backend IM controller](https://github.com/liboyang42-cpu/chengyin/blob/ce61c0bbace743ff835cb297ef41c89b52181636/chengyinhub-admin/src/main/java/com/chengyinhub/web/controller/api/ApiImController.java), blob `6cb94f055837144df2d4474c030d480c9662ad3f`: both POST handlers take the current `getAppUserId()` and return the existing AjaxResult envelope.
- Existing native `IMExpandedService` already implements these exact paths/fields.
  This slice reuses `IMExpandedCoordinator`; service, transport, permission gates,
  existing session caches, text/media send paths and private token handling are unchanged.

Implementation base: source tree `7f169a9a79b41ea6c475b1f41fddd04f7801c6e1`,
verified local snapshot of published native `9209deff`. The in-progress shared batch
was inspected read-only; implementation lives in a separate copy.

## Account / interrupted action behavior

- Only a currently loaded list row with matching reader identity, account epoch and
  coordinator conversation may create a review. Unknown muted values are not
  silently treated as false.
- Opening or closing a review has no network side effect. Duplicate confirmation
  cannot dispatch twice while the owner is submitting.
- A timeout/unknown result retains the existing owner's original mutation. Reopening
  from a different row button shows that original read/mute operation. Retry uses
  that exact mutation only after the explicit retry button.
- A pending message send cannot be replaced or retried by the row flow. A different
  conversation/account/epoch cannot consume its receipt.
- Only the matching current read/mute receipt requests list refresh. Unknown,
  rejection, cancellation, mismatched receipt or lost identity does not clear a badge.
- This is the existing in-memory session owner, not a new persistent journal or a
  claim of crash/relaunch recovery. No delete or mark-all operation is added.

## Integration ownership

Changed existing files: `App/MessagingHomeView.swift`, `App/MessagingComponents.swift`.
New implementation: `App/IMConversationRowActionsView.swift`, `Core/IMConversationRowActions.swift`.
New tests: matching Core/AppUnit Swift files and
`Tests/ContractChecks/test_im_conversation_row_actions.py`.
New bilingual catalog fragment:
`Resources/IMConversationRowActionsLocalizations.fragment.json` (7 keys).

The integrator must merge this fragment into the shared catalog and run the existing
project generator to include the new files. The main catalog, PBX project,
AppSession, AppCompositionRoot and CI are deliberately not edited by this slice.

## Verification status

Executed on dot's Linux cloud computer:

- `git diff --check`: PASS.
- New 8 Python integration assertions plus existing 9 IM expansion, 4 IM visibility
  and 4 IM history-bridge checks: 25/25 PASS. These are structural checks, not Swift execution.
- Pinned Tree-sitter 0.26.0 / Swift grammar 0.7.3: five changed/new Swift files parse
  with zero recovery nodes. `MessagingComponents.swift` has one pre-existing grammar
  diagnostic at line 43's multi-trailing-closure Label syntax. Baseline and changed
  bytes produce the identical diagnostic; the new refresh hook adds none. This is
  not an all-file parser pass and does not establish Swift type correctness.
- Authored: 11 Core XCTest cases and 21 App XCTest cases. Four original App cases
  cover hosting/readback or action scope, twelve R1 cases cover queued/in-flight
  ownership, and five R2 cases cover closed-sheet receipt/cache invalidation. Hosted
  tests use a real `UIHostingController` / `MessagingReadScreen` with synthetic
  readers. The first three hosting tests now use the shipping receipt-to-list-owner
  invalidation callback, with no test-side revision increment. None of these Swift
  cases has run in this Linux workspace.
- Swift/Xcode build, XCTest execution, UI screenshots, CN/US simulator coverage,
  VoiceOver/Dynamic Type and live backend/device acceptance: NOT_RUN; no Swift or
  Apple SDK toolchain is available in this workspace.

Apple acceptance should cover normal list navigation, left swipe and long-press,
Cancel/Close and interactive sheet dismissal, repeated taps, unknown close/reopen
with original intent, explicit same-intent retry, account switch while submitting,
server rejection, successful/failed list reread, search/filter retention, long English,
large type, small screens and VoiceOver actions.

## R1: dismissed UI / queued-work repair

R0 is preserved unchanged separately. R1 addresses two review holds without extending
feature scope or adding a new source path:

1. `IMConversationRowReviewModel` creates a one-use token synchronously in the
   currently rendered Confirm/Retry button action. It binds the appearance UUID,
   operation and exact pending mutation. `perform` can only consume that token,
   checks it before dispatch and after completion, and never creates a lifetime.
   Close invalidates the token immediately; disappearance also retires it. The
   session coordinator's unknown/submitting record is preserved. A dismissed retry
   cannot dispatch later, and an old completion cannot request a list refresh or
   overwrite a reopened sheet. Denied/cancelled tokens cannot revive after authority
   returns; a new user action is required.
2. `MessagingReadScreenModel<Value>` is the actual shared shipping read owner inside
   `MessagingComponents.swift`. Appearance, source-reader identity, account epoch,
   configuration, input revision and request token are tracked together. Appearance
   and input binding occur synchronously in UI lifecycle/input handlers. Automatic,
   receipt-triggered, toolbar, error-retry and pull-to-refresh reads all consume a
   pre-created token; queued tasks never call `appear` or `updateInput`. Old queued
   work cannot revive a departed screen, bind a replacement reader or clear a newer
   revision's loading state. Late success/failure cannot replace newer results.
   Already-started underlying reads may continue running; this repair invalidates
   their right to publish into the current snapshot and does not claim network
   cancellation. The suspended-success/failure test explicitly resumes that old
   read after a newer revision has completed and verifies the newer snapshot stays.

The twelve R1 App-model tests cover queued unknown retry after close, old/new sheet
appearances, queued confirmation, in-flight completion after close, queued initial
read after departure, replacement appearance, same-account successive revisions,
late read success/failure, changed account/source reader, cancelled queued read and
revoked-then-restored authority for read/retry tokens. These tests exercise the
shipping models directly, rather than implementing an independent test-side guard.

The main catalog, PBX and shared session/composition paths remain untouched. R1's
updated acknowledgment text no longer claims a list refresh is still running when a
receipt becomes visible after reopening an interrupted sheet.

## R2: accepted receipt after closing the sheet

The frozen R1 remains preserved separately. R2 fixes a verified functional hole:
Confirm was already in flight, Close retired the sheet correctly, then a definite
server acknowledgment arrived. R1 dropped the UI callback and could leave the
still-mounted list showing its cached pre-action state.

R2 separates two responsibilities in the shipping model:

- An exact same-scope accepted receipt invokes the weak retained list owner's
  invalidation callback, even when the originating sheet has closed. Unknown,
  rejected, stale-scope or mismatched outcomes do not invalidate or patch badges.
- Sheet completion still requires its original display token. The old task returns
  false for a departed sheet and cannot update or revive its view state.

The normal list now owns `MessagingReadScreenModel<[MessagingConversation]>` and
passes that same instance to `MessagingReadScreen`. `invalidate` verifies the exact
reader object and account epoch, retires outdated snapshot/read publication rights,
and records an invalidation revision. It does not create an appearance, task, request
token or network request. A currently displayed `MessagingReadScreen` handles the
revision using its own captured appearance/input token; an offscreen owner has no
appearance and starts no read until normal return. Already-started old reads may
continue, but cannot overwrite the refreshed snapshot.

Five R2 shipping-model tests cover:

1. Close while confirmation is in flight, then acknowledged receipt: the still-mounted
   real `MessagingReadScreen` rereads without simulating parent reappearance; the
   dismissed review model remains idle with no appearance.
2. Close and leave the list before acknowledgment: only the cache is invalidated;
   return to the list starts its next read.
3. Closed-sheet unknown result: cached unread/muted values remain unchanged and no
   read is started.
4. A receipt for an old reader/account cannot invalidate a replacement snapshot.
5. Invalidating a pre-mutation in-flight read revokes publication rather than claiming
   network cancellation; explicitly finishing that old read cannot replace new data.

## Next verified gap (not implemented)

P032 `onReadAll` exists in the same mini-program source and loops the existing
`/api/im/read` over visible unread conversations, then rereads the list and distinguishes
complete/partial failure. The native list still has no bulk-read entry. This is a
separate user-visible follow-on using the existing API, requiring its own bounded
review and per-conversation partial/unknown handling. `/delete` also exists, but its
recovery and deletion semantics have not been reviewed for this slice.
