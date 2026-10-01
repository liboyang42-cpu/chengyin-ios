# Native Square browsing module

## Scope and source evidence

Implemented in the isolated `native-square-module` worktree based on native `b47b34a`. Audited Flutter source is `a63e9e91c82a3282e8dd7138f943b1a8cbfc021d`, specifically:

- `lib/data/api/square_api.dart`: `listPage`, `info`, `comments`, `_ensureOk`
- `lib/data/models/square_post.dart`: feed enum, both post shapes, picture parsing and comments
- `lib/feature/square/square_list_page.dart`: visible modes, source login gates, cursor pairs
- `lib/feature/square/square_detail_page.dart`: independent comments, threading, page-size continuation
- `lib/feature/square/square_comment_thread.dart`: parent/member-name resolution
- `lib/core/network/dio_client.dart`: raw Authorization token and session boundaries

Native scope: read-only feed, keyword search, mode/context filters, post detail, comments/replies, and independent feed/comment pagination. Native controls are supplied with English and Simplified Chinese catalog additions. No posting, editing, deleting, liking, bookmarking, following, comment submission, reporting, sharing, analytics/dwell mutations, template remix, or location permission request is included.

## Important contract contradiction

The header comment of `square_api.dart` describes post reads as legacy `/api/creativesquare/*`, but the actual `listPage` implementation calls GET `/api/v1/community/feeds/{MODE}`. This module follows the executable source, not that stale header. Neither this implementation nor its fixtures prove those routes are deployed or ready. The older source comments about deployment are historical statements, not current backend verification. No live backend request was made and there is deliberately no speculative fallback to `/api/creativesquare/list`.

### Exact read requests

| Read | Method and source route | Shape |
| --- | --- | --- |
| Feed/search | GET `api/v1/community/feeds/{MODE}` | Query `limit=30`, optional positive `cursor`, optional `cursorScore` paired with cursor, nonempty `keyword`, positive `authorId` |
| Nearby | Same route with `NEARBY` | Required trimmed `cityCode`; no coordinates or fake `CURRENT` value |
| Topic | Same route with `TOPIC` | Required trimmed `topicCode`; requires native signed-in session |
| Community | Same route with `COMMUNITY` | Required positive `communityId`; requires native signed-in session |
| Featured | Same route with `FEATURED` | `collectionCode=CITY_PICK` |
| Detail | POST `api/creativesquare/info` | Multipart `id` |
| Comments | POST `api/comment/list` | Multipart `owner_type=3`, `owner_id`, `pageNum`, `pageSize=50` |

Feed responses use only `data.items`, boolean `hasMore`, `nextCursor`, and `nextCursorScore`. Detail uses `data`. Comments use `data.rows`; continuation follows the source's raw returned page length. `total` is not used. Missing optional feed/comment payloads follow the source's empty defaults; wrong envelope types are errors, not a guessed alternative shape. HTTP 401 or business code 401 are authentication errors. Non-200 business errors retain their server message verbatim; they are never converted into empty success. Raw tokens have no `Bearer` prefix.

The source's unused `isMy` parameter does not generate `is_my`; the native module likewise does not invent it. The service supports all eight source enum routes; the native picker exposes the same six visible modes as Flutter (Latest, Following, Nearby, Topic, Community, Featured). Following, Topic, and Community are sign-in gated. The source's location-to-city workflow is intentionally replaced here by explicit city-code entry; no geolocation, reverse-geocoding integration, or friendly city/topic/community directory lookup is claimed.

## Data and UI behavior

- Legacy flat posts and nested `post`/`media`/`references` envelopes are decoded with the audited field precedence
- Read display fields include text, image URLs or object keys, author badges/verification/level, club, linked content, route progress, safety notices, counts and timestamps
- Image URL arrays, JSON-array strings, and ASCII/Chinese comma/semicolon delimiters are supported
- Image media precedes legacy `pics`; `MAP_SNAPSHOT` is separate; only the first reference is used, matching Flutter
- Supported association types map to activity/topic/route; unknown types never gain a made-up `dataType`
- `viewerCanComment` keeps source absent-means-true semantics in the model, but no comment mutation UI is exposed
- Unknown server labels/messages remain verbatim. Known safety labels and native controls are localized
- Bad/missing/nonpositive IDs fail decoding instead of entering navigation with invalid resource identity. This is deliberate native hardening over Flutter's ID-zero fallback
- Only absolute HTTPS image sources without userinfo are rendered. Relative storage object keys show an honest unavailable placeholder; no storage host, asset-signing flow, or coordinates are invented
- Comment reply naming prefers a loaded parent, then a loaded author with `repliedToMemberID`; an unknown person is not fabricated. Root/reply/orphan ordering mirrors the source
- Page rows deduplicate by post/comment ID. Feed continuation uses the complete cursor ID/score pair, detects repeated/cyclic cursors, and preserves loaded content with an explicit continuation notice if the next cursor is unusable
- Comment page advancement depends on raw server row count, even when duplicates reduce the visible count
- First-page failures, empty results, unconfigured service, guest gates, unauthorized reads, unavailable detail, incremental page failure, and comment-only partial failure have distinct UI states
- Search is committed on Search/Return. Clearing the field resets the query. Responses are scoped to both the query and request generation
- Detail and comments load independently. A comments failure preserves the post and can be retried without refetching it. A missing post does not display orphan comments
- Session reader compares account, epoch, credential, and opaque scope before returning success or expiring authentication. An old response or guest 401 cannot expire a replacement account
- Views guard in-flight results with generation, resource/query and scope; navigation disappearance invalidates pending UI updates

## Integration instructions (shared files intentionally untouched)

1. Merge new `Core/Square*.swift`, `App/Square*.swift`, the Square tests and this documentation into the main native checkout
2. Add private `SquareService?` initialization beside existing services in `AppSession`, with the already-approved optional configuration and shared transport. Do not create a default backend URL
3. Build `SquareReadSession(accountID:epoch:token:)` from the current account, session gate stamp and private token
4. Retain `SquareSessionReader(service:currentSession:onUnauthorized:)` on `AppSession`. The unauthorized callback must first check that the current `SquareReadSession` equals the captured one, then call the existing epoch/credential-aware expiry helper
5. Host `SquareBrowserView(reader:onClose:)` in an environment-observing wrapper, with `.id(session.squareReader.scope)` so account/epoch/token transitions immediately clear navigation and personalized data
6. Add that wrapper to the intended Square entry. The module is not independently inserted into the root navigation here
7. Add DEBUG fixture selector `square` to `ModuleFixtureSupport` and route it to `SquareFixtureHostView`. UI tests launch `--uitesting-module square --uitesting-square-scenario <scenario>`
8. Merge `docs/square-localizations.json` by key into `Resources/Localizable.xcstrings` (English and `zh-Hans`), preserving existing entries
9. Regenerate the project and run aggregate checks only from the integration checkout. Add `SquareFlowTests` to the appropriate UI verification shard when authorized

No shared session/root/catalog/project/workflow file was edited by this worker. No commits, pushes, PRs, live backend calls, Mac access or simulator runs were made.

## Offline verification

Available DEBUG scenarios: `content`, `empty`, `failure`, `unauthorized`, `unconfigured`, `unavailable`, `partial`, `pageFailure`, `invalidCursor`, `delayed`. Every scenario uses synthetic offline data. The core fixture enum is inert data only; the fixture reader/host is gated with `#if DEBUG`.

Added 21 pure Swift XCTest methods covering source requests, gates, envelopes, model aliases, media/references, replies, both pagination styles and session races. Added 9 XCUITest methods covering pagination/detail/back, partial error retry, pagination retry, unavailable detail, Chinese empty state, search/clear, delayed search replacement, guest gate and configuration/auth states.

Cloud checks completed:

- `python3 -m unittest discover -s Tests/ContractChecks -p test_square_structure.py -v`: 5/5 static checks passed
- `git diff --check`: passed for tracked diff; added-file whitespace checked separately
- Synthetic JSON fixtures and localization JSON parsed successfully

Swift/Xcode are not installed in this cloud environment. The added Swift tests and simulator UI tests are authored but **not run**. Static checks do not establish Swift compilation, simulator rendering, accessibility, physical-device behavior, live endpoint readiness, or full migration acceptance. Those gates remain pending in the integrated checkout with an approved Apple toolchain.
