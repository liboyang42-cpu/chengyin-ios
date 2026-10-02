# Account collections: favorites and owned coupons

## Delivered slice

Authenticated favorite-topic pagination and coupon collection / metadata details, with independent view state and failures. Uses native SwiftUI navigation, refresh, search submission, a status filter menu, system empty/loading/error states, Dynamic Type, adaptive colors, and bilingual strings. Favorite topic cards use the shared full-bleed image + bottom scrim component; there is no white outline or bundled portrait.

The coupon detail rereads the current owned collection and selects one exact history ID. It does not treat a cached row as a current status receipt. No coupon metadata-detail endpoint is present in the audited Flutter API; the QR issuance endpoint is not used as a substitute. Past, invalid, and unknown-status coupons can be inspected as metadata only. Unknown states stay unknown, and expiry is never recalculated using device time.

No writes, unlike toggle, share URL, new addresses, default-address changes, code issuance, QR rendering, redemption, publishing, payment, or live requests are part of this slice. CouponCode/qrcodeUrl/token are not decoded into the model, retained, or rendered. Source amounts/currency were not invented. All fixtures are synthetic and contain no contact PII or image network URLs.

## Audited source, Flutter revision a63e9e91

- `lib/feature/account/my_likes_page.dart`: guest gate, 10-item pagination, generation reset, and topic route `/topic/{id}`
- `lib/data/api/topic_api.dart`: `likeList` uses POST `/api/topic/like_list`, multipart `pageNum` / `pageSize`, `data.rows` with bare `data` list compatibility
- `lib/data/models/topic.dart`: exact topic summary fields; existing native `TopicSummary` is reused
- `lib/feature/coupon/my_coupons_page.dart`: own coupon list, All / Unused / Used / Expired filters; invalid records visible only in All
- `lib/data/api/coupon_api.dart`: `myReceivedList` uses POST `/api/coupon/myrecvlist`, multipart optional nonempty `keyword`, and a bare `data` array. No synthetic `/info` endpoint
- `lib/data/models/coupon.dart`: `useStatus` 0 unused, 1 used, 2 expired, 3 invalid; other/missing codes remain unconfirmed here. `couponDescription` falls back to `note`. Date-day text preserves the service's calendar day
- `lib/feature/account/address_list_page.dart` / `address_edit_page.dart` and `lib/data/api/address_api.dart`: this is the same participant table and endpoints, not an independent shipping-address book. Native `ProfileParticipant`, `ProfileParticipantsView`, and `ProfileParticipantDetailView` already read contact fields and the `province` + `detailAddress` saved-address projection. The batch deliberately does not duplicate that domain or add another address navigation entry

Strict read behavior: absent/null/malformed collection payloads produce malformed-response errors rather than fabricating a successful empty state. A missing or duplicate requested coupon history ID is unavailable. Literal server failure messages are preserved; authorization status is checked before payload/message decoding. Retry is a fresh read only.

## Parent integration (shared files intentionally untouched)

1. Add all new `Core/AccountCollection*.swift` and `App/AccountCollection*.swift` files to the generated Xcode project through the normal project generator. Swift Package test discovery already includes the new core tests
2. Retain one `AccountCollectionSessionReader` in AppSession, with `AccountCollectionService(configuration:transport:)`, the existing ephemeral no-redirect transport, and a live `currentSession` closure creating `AccountCollectionReadSession(accountID:epoch:token:)`. The epoch must advance on logout, expiry, and same-account relogin. Forward current `.unauthorized` results to the guarded session handler; credentials stay in the reader
3. Insert `AccountCollectionAccountLinks(reader:onOpenTopic:)` in AccountView's Form. Connect `onOpenTopic` to the existing `TopicDetailView` / session topic reader through real parent navigation. Do not add a stub destination. The two destinations expect an enclosing NavigationStack
4. Ensure the account host observes session changes and applies `.id(reader.scope)` to the collection navigation subtree. The reader's scope changes for account, epoch, credential and guest transitions. Do not place credentials in a navigation key
5. Shared dependency: `App/QuestifyImageEntityCard.swift`, supplied by the parent. No copy is included in this isolated handoff
6. Merge `docs/account-collection-localizations.json` into the String Catalog without replacing other keys
7. DEBUG fixture routing: add `case accountCollections` to ModuleFixture and route it to `AccountCollectionFixtureHostView()`. Fixture argument: `--uitesting-account-collection-scenario content|empty|failure|couponFailure|favoriteFailure|pageFailure|unauthorized|unconfigured|guest|unavailable|refreshed|sessionChange`
8. Include `AccountCollectionFlowTests` in the normal Apple UI shard/admission configuration. No project, catalog, root, workflow, or existing account file was edited in this handoff

Favorites support raw-page continuation, ID de-duplication, one active next-page read, later-page errors preserving rows, retrying the same page, refresh winning over an old next-page completion, and cancellation/scope guards. Coupon list and detail each have separate fresh-read models; a failed coupon read never changes favorite state. Only the currently visible screen refreshes on app foregrounding.

## Verification and remaining gates

Local checks on 2026-10-01:

- PASS: 5 dependency-free Python contract/structure/localization tests
- PASS: JSON localization manifest is valid, all new literal and computed localization keys are covered
- PASS: strict Tree-sitter 0.26.0 / Swift grammar 0.7.3 parse of all 11 new Swift files, zero recovery nodes
- Added: 20 Swift domain tests for exact endpoint/body/header contracts; envelope failures; malformed IDs/status; code-field exclusion; dates/status/filter semantics; independent domains; stale account/epoch/token/401 results; current unauthorized callbacks; query omission; exact owned-detail rereads; single-flight pagination; refresh/cancellation/scope guards
- Added: 11 XCUITests covering favorites routing/pagination/retry, coupons list/filter/detail/back/reopen, independent-domain failure, latest detail status, unavailable and guest/empty/config states, logout privacy, Chinese text, and dark/large-text reachability
- NOT RUN: Swift compilation, `swift test`, XCUITest, actual VoiceOver, simulator or device rendering. This Linux workspace has no Swift/Apple toolchain. Parser results are syntax diagnostics only; Apple CI remains authoritative. The fixture entry/catalog/shared-card integration must land before the UI tests are runnable
- No live backend requests, commit, push, PR, local Mac or local Codex work occurred
