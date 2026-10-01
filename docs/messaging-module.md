# Read-only native messaging module

## Delivered scope

Source-backed SwiftUI conversation list → paged chat transcript → static message detail:

- Conversation rows retain server order, sender/counterparty name, kind, last-message preview, source timestamp, unread count and known mute status
- All / Channels / Direct local filters; Direct includes merchant type 3, Channels includes group type 4; system is type 2
- Local search over displayed names and previews, with 30-row display windows. Filtering searches the complete fetched list before limiting display; Back navigation retains the list snapshot instead of destroying its scroll state
- History starts with cursor 0 / size 30, displays source oldest-to-newest page order and prepends earlier pages using only returned `nextCursor`. Returning from message detail preserves loaded pages and the reading anchor; explicit refresh loads a new latest-page snapshot
- Duplicate message IDs become one row; incoming copies win. Invalid/cross-conversation pages and repeated/cyclic cursors fail without advancing or dropping history
- Own/other message alignment uses the captured signed-in account ID; source group sender names are retained; missing sender identity is not inferred to be the signed-in account
- Literal text; image/avatar placeholders without media requests; safe static location, route/signup and generic card projections; generic result fields in message detail
- Loading / empty / failure / retry / unconfigured / signed-out / invalid-reference / exact `HANGOUT_CLOSED` states; explicit refresh and earlier-page single-flight behavior
- Read-only details use the fetched message snapshot, with an explicit freshness note. There is no invented message-info endpoint
- English and Simplified Chinese labels in `messaging-localizations.json` (`[{key,en,zh-Hans}]`), ready for root catalog merge

This is a read-only migration slice, not full IM parity or a live-server acceptance result.

## Exact retained-source coverage

Inspected Flutter commit `a63e9e91c82a3282e8dd7138f943b1a8cbfc021d` on 2026-10-01. Paths are relative to the retained client root:

- `lib/data/api/im_api.dart`, `conversations`: POST `/api/im/conversations`, empty multipart FormData; authenticated current-user scope; `data` is a bare array. No page, cursor, account, filter or search parameters exist for this endpoint
- `lib/data/api/im_api.dart`, `messages`: POST `/api/im/messages`, multipart fields `conversation_id`, `cursor_id`, `size`; default cursor 0, size 30; `data = {list,nextCursor,hasMore}`. Page list is already ordered old → new. `errorCode` is carried separately from server `msg`
- `lib/core/network/dio_client.dart`: raw `Authorization` token, no Bearer prefix; session-scoped requests
- `lib/data/models/im.dart`: conversation IDs, types 1 direct / 2 system / 3 merchant / 4 group; counterparty `id/nickname/avatar/bizKey`; last message fields; unread; strict nullable 0/1 mute flag; message IDs, conversation IDs, sender fields, types 1 text / 2 image / 3 card; extra JSON; timestamp; page envelope
- `lib/feature/im/im_list_page.dart`: loaded-conversation name/preview search, source order, filters, title fallbacks, image/card previews, unread and mute display. Native group fallback is explicitly “Group conversation” rather than mislabeling an unnamed group as an individual
- `lib/feature/im/im_chat_page.dart`: initial load; earlier-page prepend/dedup; keep same cursor after failure; no concurrent earlier requests; `HANGOUT_CLOSED` terminal state; invalid conversation reference is not empty success. Native earlier-page terminal authorization/closed failures also remove the displayed transcript
- `lib/feature/im/chat_card.dart`: location `name/address/lat/lng`, route/signup `topicId`, generic `title/sub/meta/buttons/result`, missing cardType generic fallback, content-title fallback, and malformed-card placeholder semantics
- `lib/feature/im/chat_review_result_sheet.dart`: optional taskId/bizId/outcome/reason/followUp fields. Native detail uses a List section instead of a custom sheet
- `lib/feature/im/im_time.dart`: inspected, but relative formatting is intentionally deferred because the client source does not establish the server timezone. Native renders the supplied timestamp literally
- `test/feature/im/im_chat_paging_test.dart`: explicit cursor 42 fixture, prepend order, same-cursor retry and single-flight behavior
- `test/data/im_group_channel_test.dart`: group business key retained

### Read-receipt safety finding

`ImApi.messages` only issues `/api/im/messages`. The Flutter page explicitly invokes a separate `_markRead` → `ImApi.read` → POST `/api/im/read` after load and polling. This module does **not** copy that page side effect and exposes no read-receipt API. Conversation fetch also does not call a mutation in the inspected client. No backend implementation or live server was inspected, so a server-side audit remains a separate acceptance gate; client observations are not proof of backend behavior.

### Defensive decoding differences

The retained client sometimes substitutes missing arrays/maps/IDs or missing kinds. Native rejects missing/null/malformed success data, invalid IDs, negative unread values and ambiguous paging state instead of fabricating an empty history. Missing/unknown conversation and message kinds remain unknown. Documented integer wire fields stay numeric; undocumented string-ID aliases, `rows` list wrappers and alternate endpoint names are not invented. A page with `hasMore=true` requires a positive server cursor. Cursor value ordering is never inferred from message IDs.

## Privacy and non-mutation boundary

- `MessagingService` has exactly two operations: conversations and messages. No send, start/create chat, read receipt, delete, mute, block, report, invite, upload, broadcast-click tracking or card-action dispatch
- No live calls were made during implementation. No production host, credentials, real user data, socket, timer, notification registration or permission change is included
- Service requests use the existing multipart builder and injected ephemeral no-redirect transport; views receive no tokens
- `MessagingSessionReader` captures account + credential + epoch before dispatch and rechecks after success/failure/cancellation. An obsolete 401 cannot expire a replacement account; same-account relogin and changed credentials reject old completions
- Views separately compare account/epoch identities and request generations; the history task also keys and validates the conversation ID when a router reuses its view. Dismissal, refresh and replacement invalidate older completions; static detail checks the captured identity before showing its content
- Root must recreate the account navigation subtree for every session revision. The reader is not an ObservableObject and is not a substitute for root session observation
- No private-content persistence or logging is added. SwiftUI content is marked privacy-sensitive. This does not claim an app-switcher screenshot shield; app-level privacy behavior remains a separate task
- Message text and server strings use literal Text, not localized server keys, HTML, WebViews, Markdown or link routing
- Images and avatars are native placeholders. The module makes zero media requests, including tracking URLs; no URL validation is being misrepresented as permission to fetch
- Source card actions are neither executed nor used for routing. Labels/results are static data. Coordinates are only displayed when finite and within geographic ranges; no map/navigation app is opened

## Root integration

No shared navigation, AppSession, Xcode project, localization catalog, CI or other module files were edited. Merge the new `Core/Messaging*.swift`, `App/Messaging*.swift`, `Tests/CoreTests/Messaging*.swift`, and these two documentation/localization files, then:

1. Add `private let messagingService: MessagingService?` to AppSession. Initialize using the same explicitly configured APIConfiguration and URLSessionTransport as other authenticated readers. Set nil in the unconfigured branch; do not add a production default
2. Construct the reader beside the other AppSession readers, where token/gate access already exists:

```swift
lazy var messagingReader = MessagingSessionReader(
    service: messagingService,
    currentSession: { [weak self] in
        guard let self, let account = self.account, let token = self.token else { return nil }
        return try? MessagingReadSession(accountID: account.id,
                                         epoch: self.gate.currentStamp, token: token)
    },
    onUnauthorized: { [weak self] snapshot in
        guard let self else { return }
        self.expireIfMatching(error: APIError.unauthorized,
                              stamp: snapshot.identity.epoch, credential: self.token)
    }
)
```

The callback runs synchronously on MainActor after exact session matching. Advance epoch on logout, expiration, credential replacement and every new login, even the same account. Never rebuild a session using a cached account or token after authentication ends.

3. Add an authenticated native NavigationLink to `MessagingHomeView(reader: session.messagingReader)` in an existing NavigationStack. No nested release NavigationStack is required. Key the owning account subtree/NavigationStack with `session.sessionRevision`, consistent with the existing profile privacy boundary, so obsolete navigation and conversation metadata cannot survive account changes
4. For a verified existing conversation route, `MessagingHistoryView(conversationID: existingPositiveID, reader: session.messagingReader)` supports a metadata-free entry. Do not invoke club/chat or im/start as “read-only navigation”; those create/enter chats and remain outside scope
5. Merge every bilingual JSON entry into the root String Catalog; regenerate the Xcode project with the existing generator. New Core tests are automatically included by Package.swift. Run applicable aggregate scaffold checks only after root catalog/project integration

## Offline fixtures and root acceptance

`MessagingFixtureHostView(scenario:)` and `MessagingFixtureReader` are DEBUG-only. Scenarios: success, empty, error, closed, unauthorized, unconfigured, pagingError, loading. All content is synthetic; there are no fixture URLs or real personal records. `success` provides 35 conversations and history with text, image placeholder, generic result, route, location, unknown type and literal markup-like text. Page 2 uses cursor 42, then stops. `loading` delays 15 seconds and honors cancellation.

Suggested root fixture route: `--messaging-fixture <scenario>` under the existing DEBUG harness. This module did not modify root routing or add an AppUITests file outside its ownership.

Required simulator assertions:

- Open `messaging.conversation.901`, history rows, a message detail and back; repeat and refresh
- Verify source text is literal and image rows (`messaging.message.image`) cause no image loading
- At most 30 initial conversation rows; `messaging.list.more` reveals rows 31–35; a search must find a row beyond the initial window
- Source filters: 902 is System, 903 Merchant/Direct, 904 Group/Channels; missing/unknown types remain all-only
- History starts with 10…17 and loads ID 1 above them; `messaging.history.earlier` disappears at end. Earlier-page retry on pagingError retains visible messages and requests cursor 42 again
- The initial scroll shows latest; prepending keeps the reader's visible message stable. Validate long content, Dynamic Type and scroll behavior on-device rather than assuming SwiftUI alone proves it
- Generic card 13 → message detail shows result fields and static action labels; no actionable card buttons; route/location cards stay read-only
- Empty conversation list: `messaging.list.empty`. For empty history, mount MessagingHistoryView with the fixture reader and an existing fixture ID directly
- Errors: `messaging.list.error`, retry suffix `.retry`; closed history uses the terminal closed copy and no retry; unconfigured/signed-out never request or loop
- `messaging.fixture.switch` recreates the DEBUG navigation stack; test account switching while loading and while detail is open using root's session fixture hooks as well
- Test leaving during initial/earlier load, repeated retry/refresh, same-account new epoch, logout and stale unauthorized responses. Test English/Chinese, dark mode, maximum accessibility text size, VoiceOver and full navigation dismissal

## Deliberate gaps

Sending/composer, optimistic sends/retries, images/full-screen media, read receipts/unread-total badge, polling/realtime, create chat, group invitations/management, mute/delete/block/report, share/upload, link/card actions/click tracking, route detail hydration, local persistence, and notification/permission flows are not implemented. Existing merchant/cooperation-pool/square shortcuts from the Flutter list are not duplicated here. Raw server time is shown; relative/date formatting is pending a timezone contract.

The list endpoint has no server paging; “Show more” is an honest local rendering window, not a fabricated network-page request. Static message details have no invented freshness claim.

## Verification evidence

- Added 36 synthetic XCTest methods across contract, history, service and session tests: wire fields/types; malformed success; unknown kinds; nullable mute; static cards; literal content; exact multipart endpoints/body/auth; no extra mark-read request; cursor order/dedup/retry/cycles; foreign-conversation rejection; logout/relogin/token changes; stale 401; transport cancellation; empty/unconfigured/guest behavior
- `git diff --check`: passed before handoff
- Temporary-copy project/catalog integration: passed structural checks with 64 Swift references, 393 bilingual catalog keys and deterministic project regeneration. Owned worktree shared files stayed unchanged
- Bilingual JSON parsed, unique keys/nonempty translations checked; all messaging UI localization keys covered; fixture source checked for no URLs; module service endpoints statically restricted to the two read operations
- No Swift, swiftc or Xcode executable is installed in this Linux worktree. XCTest execution, SwiftUI compilation, preview rendering, simulator UI/accessibility and live backend acceptance are **not run**, not passed
- Root must run `swift test`, unsigned simulator build, updated aggregate scaffold/localization checks and the above fixture UI tests on the integrated revision
