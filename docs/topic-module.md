# Native Topic browsing slice

## Scope and evidence

Bounded implementation against retained Flutter `lib/data/api/topic_api.dart`, `lib/data/models/topic.dart`, and `lib/feature/topic/topic_detail_page.dart` (including footer precedence, chapter story and paywall). This is not full Topic migration or backend acceptance.

Source denominator: two read operations (public paginated `list` and player `info-to-user`), nine payload projections (summary, detail, chapter, node, template, merchant, ticket, registrant, comment), seven UI paths (paged discovery/search/filter, unavailable/error/retry, detail metadata, available chapter/node story, locked-story notice, ticket/session readback, review readback), and identity/cancellation/pagination guards. This denominator, not test count, describes the slice. All API and model projections are authored; UI intentionally only exposes the bounded read paths.

- `POST /api/topic/list`: multipart `is_my=0`, `pageNum`, `pageSize`; optional `keyword`, `category_id`, `is_recommend=1`. Never private `is_my=1`. Nested `data.rows` precedes root `rows` fallback. Raw server page length determines continuation, not deduplicated display count. A full last page requires a next-page probe. IDs deduplicate while source order is retained.
- `POST /api/topic/info-to-user`: multipart `id`. Response ID must match the requested route and name must not be empty. HTTP/envelope authorization precedes payload decoding. Null/mismatched/unavailable detail never becomes a blank successful screen. Empty malformed objects and invalid IDs are rejected.
- Safe divergence from permissive Flutter decoding: malformed typed arrays/objects and nonpositive route/chapter/node/template/ticket IDs fail closed; no malformed payload is used for navigation. Source list/detail omit explicit code checks, whereas native requires HTTP success plus `code=200`.
- Uses `minAmout` wire spelling, `imgUrl/picUrl` and description aliases, ordered `chaptersList/nodes`, `omsTicketList`, `commentList`. `TopicTemplate` is descriptive metadata only, never an answer payload.
- Amounts are optional Decimal. Null/missing is never zero/free; zero is retained as a known amount. There is no currency code in these source projections, so UI displays plain amount without an invented currency symbol.
- Source purchased state takes precedence over lifecycle. Lifecycle 1/2 remains not on sale. Merchant-closed notice is independent and blocks new purchase eligibility. Self-play is gated by `selfPlay == 1`, not a non-null price. These are explanatory states, not authorization to purchase.
- Locked count uses total minus supplied unlocked count (or chapter count fallback), clamped at zero. Paywall appears only for `storyLocked && lockedChapterCount > 0`. No endpoint is called to fetch hidden chapters, unlock or establish a play session.

## Integration API

Integrated into the migration branch with a retained session reader, an observable sheet host from Discovery, DEBUG fixture routing and shared catalog/project references.

1. Construct a stable `TopicSessionReader(service:currentSession:onUnauthorized:)`. The service may be nil when not configured. Use the verified current account, monotonic session epoch, and exact current token in `TopicReadSession`; return nil for guest access. No synthesized credentials or fallback user ID.
2. Embed `TopicBrowserView(reader:categoryID:pageSize:)` for the public list (it owns a NavigationStack), or push `TopicDetailView(id:reader:)` from a route link. Production defaults pageSize to 10.
3. The host must observe session changes and cause this subtree to reevaluate whenever account, epoch or token changes. Reader `scope` is an opaque UUID that changes on every observed session change, including token rotation with the same account/epoch. The host must advance the epoch on each session transition, including logout then login to the same account. Do not recreate a reader for each render.
4. Merge `docs/topic-localizations.json` into the shared String Catalog. Add owned files using normal project generation. No root catalog edits are included here.
5. Debug-only integration: add `ModuleFixture.topic`, with `case .topic: TopicFixtureHostView()`. UI tests launch `--uitesting-module topic`; optional `--uitesting-topic-scenario unavailable` targets unavailable detail. Additional scenarios: empty, failure, unauthorized, unconfigured, closed.

Every read captures optional guest/authenticated session plus scope, compares account/epoch/token after success and failure, and checks task cancellation. A stale unauthorized response does not invalidate the new session. Current unauthorized response calls the injected callback only for the matching authenticated snapshot. View generations prevent search, refresh, page, navigation and overlapping request completions from overwriting newer state. Cached detail and chapter content is hidden immediately on scope mismatch when the host rerenders. Credentials never enter view navigation keys, logs, fixtures or UI.

## Intentionally deferred source behaviors

All like/cancel/refund/pricing/review/upload/transfer/graduate/recruitment-authoring operations, merchant projection fallback, favorites/private lists, ticket wallet navigation, booking/payment, self-play purchase, Play.nodes/start, audio playback, artwork fetching, map geometry, and creator/merchant management stay outside this slice. Images/audio/coordinates and registrant records are decoded when present but no third-party media fetch, audio player, map, member navigation or participant list UI is activated. The detail's primary text and supplied story chapters are native SwiftUI List content. No decorative fake action or dead button claims those deferred workflows exist.

## Verification

Authored domain tests exercise exact requests, guest headers, envelope precedence, errors, invalid requests/IDs, aliases and nullable prices, ordered nested projections, source gate matrix, locked-count fallback, raw-page continuation/dedup, guest-to-user transitions and account/epoch/token stale success/401 guards. Debug fixtures have no endpoint, transport, credentials or real records. Two authored XCUITests cover pagination → detail → chapter/back plus locked story, and unavailable detail/retry.

Local environment has no Swift or Xcode. Swift domain tests and iOS build/UI tests are **authored but unrun locally**; root macOS CI after integration is required. Python JSON parsing, localization coverage and source safety checks are run locally. No live calls, purchases, uploads, commits, pushes, PRs or user-computer tasks were performed during module authoring. Source UI parity beyond this bounded slice and device/accessibility acceptance remain open.
