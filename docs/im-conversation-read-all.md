# P032: explicitly reviewed loaded-conversation read-all

## Source and scope

Directly inspected source at backend commit
`ce61c0bbace743ff835cb297ef41c89b52181636`:

- [Mini-program IM list](https://github.com/liboyang42-cpu/chengyin/blob/ce61c0bbace743ff835cb297ef41c89b52181636/chengyinhub-xcx/subpackageB/pages/im/list/index.js)
- Tree path: `chengyinhub-xcx/subpackageB/pages/im/list/index.js`, blob
  `1f6912406e2a3b524fe6a1776168afe3df35dbfa`.
- The suggested `pages/message/index.js` path does not exist in that commit's
  recursive tree; the actual path above was resolved from that tree before implementation.
- `onReadAll` selects `this.data.list` entries with `unread > 0` and `tabOf(c) !== null`,
  then POSTs `/api/im/read` with each `conversation_id`. It does not use a server bulk
  endpoint. Completion triggers `loadConversations(true)`. Business failure is counted
  separately from success; an HTTP-success callback alone is not proof of acceptance.
- The source selects across its tabs. Type 4 groups are excluded. Its fallback for
  missing/future types is broader than the native typed contract; this slice deliberately
  allows only known types 1/2/3, with explicit positive unread counts. Muted conversations
  remain eligible, matching the source.

Implementation baseline: remote native `1161bf975172091f49ba6b33fe49ce515ff9eca4`
plus the reviewed conversation-row R2 prerequisite and the independent integration
snapshot. The only edited existing path, `App/MessagingHomeView.swift`, has preimage
SHA-256 `a9a024a3a92f3b7f0d9269356d0cddb2fc9182f620e6586383eb055e5d3e071f`.
All development occurred in an independent copy. No shared integration files or remote
branches were changed by this slice.

## User-visible behavior

The normal native Messages list gains a toolbar entry named “Mark all as read” /
“全部已读”. It is unavailable when there are no eligible unread rows or the existing
writer is unconfigured. No production permission or feature gate is enabled.

The review sheet explicitly describes the frozen set as currently loaded conversations,
across categories and search results, excluding groups and unknown types. Search,
segmented filtering, and the 30-row presentation limit do not narrow the source set;
the action does not claim to cover unloaded server conversations. Duplicate IDs are
included once. The review shows the frozen conversation count and the individual names.

Confirmation is explicit and separate from opening the sheet. No write or coordinator
review is created on initialization. The existing read endpoint has no message cutoff;
the review explains that new messages within a selected conversation can also be marked
read when its request is processed.

Requests run sequentially with maximum concurrency 1. There is one finite pass over
the frozen array, with no recursively fetched work, automatic retry, or catch-up loop.
Each item uses the original session-retained `IMExpandedCoordinator`, verifies its
account/epoch/conversation and writer configuration, then verifies the exact reviewed
mutation again after the synchronous review callback. Existing service/transport path
permission checks remain in force at dispatch. No new writer, transport, journal,
endpoint, permission, realtime connection, or implicit on-appearance write is added.

Existing reviewing/submitting/unknown read, mute, and message intents are protected.
They are not replaced or retried by this batch. Unknown outcomes retain the existing
coordinator's original pending mutation. No retry button exists in the batch sheet;
individual actions retain their existing explicitly reviewed retry path.

Each attempted item is reported as server-accepted, rejected/closed, or unknown. Protected,
unavailable and unstarted items remain separately identifiable and count as “Not sent”.
No single failure implies total failure; no receipt implies a zero unread badge. An
unexpected receipt kind is not treated as read success. The final screen reports request
outcomes without ever claiming the whole server inbox is now read.

## Cancellation, stale state and authoritative readback

- Confirm uses a synchronously minted, one-use appearance token. Closing before a queued
  task executes invalidates the token; it cannot restart after Close, a new appearance,
  or an observed revoke/restore of authority.
- Stop and Close prevent all subsequent requests. An already-started request may finish;
  its receipt or unknown mutation stays with the original session owner. The UI never
  resets the coordinator to cancel transport and does not claim network cancellation.
- A changing account, epoch, configured reader, or reader instance retires list reviews.
  Every iteration rechecks current authority. Returning to the list does not restart a batch.
- After any attempted batch settles, including partial and unknown outcomes, its App model
  invalidates the existing `MessagingReadScreenModel` once. The retained list owner checks
  the exact reader instance and account epoch before accepting this invalidation.
- Invalidation is independent of sheet lifetime. Closing while the request is in flight
  still invalidates the same-scope list after its result arrives, without reviving the sheet.
- The visible list performs its existing `messagingConversations()` read. If offscreen,
  only cached-data authority is invalidated; the next normal appearance reads. Only a
  successful authoritative response replaces the list. A failed read uses the existing
  error/retry UI. No unread or mute field is locally changed.
- A replacement reader or account cannot receive the old batch's invalidation. The existing
  list model rejects stale in-flight read completions using its normal generation tokens.

## Integration ownership

Exactly eight paths belong to this slice:

1. `Core/IMConversationReadAll.swift`
2. `App/IMConversationReadAllView.swift`
3. `App/MessagingHomeView.swift`
4. `Tests/CoreTests/IMConversationReadAllTests.swift`
5. `Tests/AppUnitTests/IMConversationReadAllTests.swift`
6. `Tests/ContractChecks/test_im_conversation_read_all.py`
7. `Resources/IMConversationReadAllLocalizations.fragment.json`
8. `docs/im-conversation-read-all.md`

Integrator responsibilities: merge the 19 English/Simplified Chinese fragment keys into
the main string catalog and regenerate the existing Xcode project to include the new
implementation/test files. AppSession, composition, shared MessagingComponents, the main
catalog, PBX, CI and runtime grants are deliberately unchanged.

## Verification

Executed locally in the Linux workspace:

- `python -m unittest discover -s Tests/ContractChecks -p 'test_im_*.py' -v`:
  33/33 PASS (8 new read-all structural checks plus the 25 existing IM checks).
- Tree-sitter 0.26.0 / Swift grammar 0.7.3: all five changed/new Swift files parse with
  zero error/missing nodes. This is syntax evidence only, not Swift type checking.
- `git diff --cached --check`: PASS after final staging.
- The supplementary `tools/check_im_expanded.py` source-audit gate could not run because
  the independent snapshot lacks its required sibling `app-audit/lib/data/api/im_api.dart`.
  It was not bypassed, edited, or counted as passed.

Authored but NOT_RUN:

- 15 Core XCTest cases: eligibility/deduplication/freeze, no-write review/cancel, exact
  read scopes, partial failure/unknown, pending read/mute/send protection, account/read
  revocation, per-owner permission/conversation checks, synchronous review callback
  revocation, in-flight Stop, task cancellation, 500-item bounded serial processing,
  double confirmation, default-off gates and unexpected receipts.
- 10 App XCTest cases: real hosted list readback, partial unknown readback with journal
  retention, failed readback without fabricated zero, queued Close, stale appearance,
  Close during in-flight write, offscreen deferred read, replacement-reader isolation,
  revoke/restore token consumption and repeated Confirm.
- Swift/Xcode compilation, XCTest execution, simulator/device UI, CN/US builds, dynamic
  type, VoiceOver, scroll preservation and live backend acceptance. This workspace has
  no Swift or Apple SDK toolchain. All authored I/O fixtures are synthetic; no real user
  message was read-marked, muted, or sent.

Apple acceptance should exercise small screens/long English, a large frozen list,
interactive dismissal, rapid repeated taps, Stop while a request is suspended, unknown
Close/reopen, identity/source replacement, authoritative nonzero badges after a successful
read receipt, and readback error/retry. This slice has not been pushed or published.
