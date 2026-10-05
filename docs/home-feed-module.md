# Native home mixed-content feed

## Scope and integration

New module in `Core/HomeFeed*.swift` and `App/HomeFeed*.swift`. It does not replace the template gallery itself: the composition root must make `HomeFeedView` the home tab and keep Discovery's template browser as a separate destination. Add new App and UI test files to Xcode targets and merge `home-feed-localizations.json` using the existing localization workflow. Swift Package automatically picks up Core files and core tests.

Construct `HomeFeedSessionReader(service:currentSession:onUnauthorized:)` from the explicitly configured backend and current account/epoch/token. Guests return nil. Recreate the wrapper with `.id(reader.scope)` on observed session/epoch/token changes so old visible content is removed immediately; reader and view also reject stale completions. On unauthorized, invalidate only the matching captured session. `HomeFeedView` is embedded in the app's NavigationStack and takes a required `(HomeFeedDestination) -> Void` callback. Route `.activity(id)` to the existing ActivityDetailView and `.topic(id)` to the existing TopicDetailView. No duplicate detail screen or play start is created.

For fixtures, route `--uitesting-module home-feed` to `HomeFeedFixtureHostView`. It intentionally uses synthetic destination labels to assert typed dispatch without contacting any backend; production callbacks must use existing detail views. Scenarios are `content`, `retry` (first page fails once), and `empty` via `--uitesting-home-feed-scenario`.

## Verified source mapping

- `app-audit/lib/feature/feed/feed_page.dart`: featured banners; recommended topics; nearby activity section; upcoming activities; separate topic/activity streams; always-present price/date/place rows
- `feed_sections_controller.dart`: recommend topic/list `is_recommend=1`; nearby activity/list `sort_type=2` without GPS; upcoming `is_my=2`, size 6; activity stream is a separate full page, not nearby slice
- `data/api/activity_api.dart`, `topic_api.dart`: public `is_my=0`, keyword/category_id, pageNum/pageSize
- `widgets/home_activity_live.dart`: LIVE is start <= now; source explicitly adds no end-date or ticket-status condition. Topic `betaFlag == 1` drives Beta

The no-GPS nearby fallback is labeled “Activity highlights”, with a time-ordering disclosure. It never implies measured proximity, current city, or a location permission grant. Search/category filters apply to the selected stream; editorial sections remain unfiltered. Both entity types page independently after selecting their stream. Namespaced identities prevent topic ID 7 and activity ID 7 from colliding. A full raw page of duplicates still permits the next page; failed pages do not advance.

No list contract provides currency. Display the amount (including zero) with “Currency not provided”; no USD/CNY/device-market currency inference, no claim of free admission. Date and place remain raw server values or “—”. No host is invented.

## Region/time rules

Offset-aware timestamps and 10/13 digit epoch values identify their own instant. Bare timestamps have no instant unless `sourceTimeZone` was supplied from verified backend configuration. For the legacy CN source, the audited Flutter parser uses China time; only an explicitly selected/verified CN source may pass `TimeZone(identifier: "Asia/Shanghai")`. Default is nil. A future US backend must provide offsets or its documented source timezone. Device language and UI locale never select a timezone. Calendar overflow and invalid offsets are rejected. LIVE is read-only, updates on a one-second TimelineView, and never gates ticket or play eligibility.

## Deliberately remaining outside this module

The source's continue-session section needs a real resume destination and session reads, so it is not represented by a dead CTA. No play/nodes request, login prompt, autoplay, registration/payment, favorite write, location request, arbitrary banner H5 opening, or unverified currency fallback is added. Existing template browsing stays outside this feed. Countdown and source continue-section parity remain later work; the upcoming row preserves server dates and LIVE only.

## Validation status

Added pure core tests for typed collisions, pagination duplicates/order, LIVE boundaries, regional timezone policy, exact read request fields, no GPS/currency payload, distinct upcoming/nearby requests, errors, invalid requests, and stale guest-to-account unauthorized handling. Added XCUITests for typed navigation/back, missing-currency disclosure, retry/paging, and empty state. All Swift compilation, core execution, and simulator execution are UNRUN: this Linux workspace has no Swift/Xcode. JSON localization parsing, UI text localization-key coverage (excluding accessibility identifiers), and git whitespace checks were run locally. Synthetic fixture host integration and actual app navigation remain composition-root work.
