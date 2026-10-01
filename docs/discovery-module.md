# Native discovery and template browsing slice

## Implemented

This additive, read-only module contains source-backed domain projections, six endpoint methods, native SwiftUI home/template screens, injected readers, an opt-in offline fixture reader, 24 synthetic contract tests, and a separate 70-key English/Simplified Chinese localization merge payload.

The implementation is a first discovery slice, **not completion of the full Flutter feed or template product**. No project, app session, root navigation, shared localization catalog, workflow or Flutter files are edited by this module.

### Root integration

- Merge `docs/discovery-localizations.json` (array of `{key,en,zh-Hans}`) into the shared string catalog. Interpolated entries use `%lld` or `%@`, matching SwiftUI's extracted keys.
- Create `DiscoveryService(configuration:transport:)` only from the same explicitly approved configuration/transport as other services. There is no production host default.
- Conform the root session to `DiscoveryReading`; the six method names in `App/DiscoveryReading.swift` correspond directly to service reads. Capture credential and session epoch before each call; reject superseded responses and expire only matching credentials using the existing session pattern.
- All service token arguments default to nil. Public browsing is permitted anonymously. `isConfigured` means endpoint configured, not authenticated.
- `DiscoveryHomeView(reader:onBannerDestination:)` owns its NavigationStack and is suitable for a root tab. The optional callback receives only `.activity(id)`/`.topic(id)` values; omit it until those destinations are integrated.
- `DiscoveryTemplateBrowserView(reader:)` and `DiscoveryTemplateDetailView(id:reader:)` embed in an existing NavigationStack. Root may expose either directly.
- Regenerate the Xcode project after copying new files. The package already discovers all `Core/*.swift` and `Tests/CoreTests/*.swift` files.
- In DEBUG, `DiscoveryFixtureReader(scenario:)` supplies content/empty/failure/unauthorized/unconfigured/unavailable scenarios. It has no token, host, or remote image URL and is never selected automatically.

## Source traceability

All paths below refer to the retained Flutter checkout, which remains unchanged.

| Native coverage | Source |
| --- | --- |
| Banner form `showType=1`, `linkType=0`, array payload and `picUrl/linkType/dataId/contents` | `lib/data/api/banner_api.dart`, `lib/data/models/banner.dart` |
| Banner navigation only for activity type 3/topic type 4 | `lib/feature/feed/feed_page.dart`, `_onBannerTap` and its `canTap` condition |
| Categories form `parentid=0`, optional `type`, `categoryName` then `name` fallback | `lib/data/api/category_api.dart`, `lib/data/models/category.dart` |
| Play-template list form `keyword`, `pack_type`; data array or data.rows | `lib/data/api/template_api.dart`, `list` and `_list` |
| Play-template detail form `id`, public model fields and unavailable reasons | `lib/data/api/template_api.dart`, `info`; `lib/data/models/template.dart` |
| Separate whole-route template shelf with empty JSON body | `lib/data/api/template_api.dart`, `topicTemplateList`; `lib/data/models/topic_template.dart` |
| Template home with empty JSON body and five independent shelves | `lib/data/api/publish_api.dart`, `templateHomeSections`; `lib/data/models/publish_draft.dart`, `PublishTemplateHomeData` |
| Default route-template tab, separate game filters, category source | `lib/feature/template/template_list_page.dart` |
| Detail order: introduction, rules, materials, location, verification, creator fallback/image | `lib/feature/template/template_detail_page.dart` |
| Verification codes 0–7 and unknown-code fallback | `lib/data/models/validation_method_labels.dart` |

### Preserved behavior and deliberate safety choices

- Home `bannerList/latestList/recommendList/mustPlayList/hotList` retain their own semantics. Rows are not merged and then reused to fabricate sections.
- Route templates remain a separate entity. Missing verification status stays experimental; preview-only stays labeled as such. Category matching tokenizes the exact comma-separated `categoryIds` field rather than substring matching. Selecting a category puts matching templates first and keeps others visible.
- Play filters distinguish all formats (no `pack_type`) from explicit single-location format (`pack_type=0`). Search uses the verified list API; no pagination is invented.
- Template detail preserves rich public text fields and creator-story fallback. It does not model question answers/correct answers or fabricate secret data.
- Nullable duration and players do not become “0 minutes” or “0 people.” Unknown pack types have no invented label. Topic duration accepts source string/numeric representations and removes one recognized unit suffix before localization.
- Business/gateway failures do not appear as successful empty shelves. HTTP 401 and envelope 401 take precedence over malformed payloads and optional server messages. A detail's missing/deleted/offline refusal has no retry button; under-review/unknown can retry.
- Valid success responses may have absent/null list fields, matching Flutter. Malformed container types and non-positive/missing object IDs are rejected, instead of manufacturing zero IDs or silently dropping malformed rows.
- The native home API propagates load failures. Flutter's `templateHomeSections` currently catches all errors and returns empty home data; hiding those failures is intentionally not carried over.
- Loaders use request generations and task cancellation checks. Independent home/banner loads and topic/game states cannot overwrite one another. Every reload clears stale data; successful route-topic data stays cached when changing tabs. Filtered-game results currently reload when returning to that tab, unlike Flutter's broader provider cache.
- Titles, status, field labels, controls and notices are localized. Server-authored text is displayed as content. Source image URLs must be absolute HTTPS and contain no URL user/password; others show a native placeholder. No session credentials are attached to artwork requests.

## Known gaps and source ambiguities

- Full feed sections remain outstanding: recommended public topics, upcoming countdowns, nearby/activity streams, public topic pagination, continuing play sessions, joined-registration fallback and fixed invitation/action banner.
- Player/merchant-specific entry points, template publishing, use/adopt/copy-to-draft, validation, draft editing, management, payments and mutations are intentionally absent. Read-only notices explain this on previews/details.
- Play-template category filtering is withheld. Flutter's own `template_api.dart` documents that it sends `categoryId` while backend expects `category_id`, so the visible filter historically did not work. This module does not invent a corrected wire contract or falsely advertise filtering; product/server verification is needed before enabling it.
- Whole-route template field shapes are source-projected; `topic_template.dart` itself warns there is no live payload sample. No live contract claim is made here.
- `template_topic_shelf.dart` comments call for keeping other categories visible, but the current selected-category `tailList` expression is empty. Native browsing implements the documented keep-others-visible intent; exact bug-for-bug UI parity is not claimed.
- The route template preview uses only shelf fields; there is no invented route-template-detail endpoint. Full chapters and configuration are not available.
- Banner types 0/1/2 and unknown values are display-only, consistent with the currently handled feed navigation. Native H5/single-page rendering is not added.
- Relative asset URL resolution, customized artwork, source-perfect spacing, Home current-user decorations and full source visual parity remain outstanding.
- Root navigation/session integration and UI test launch wiring belong to the integration batch. This module supplies components and fixtures but cannot claim those routes are reachable until wired.

## Verification

Available in this Linux workspace:

- `git diff --check`: passed (additive worktree contains only permitted new files)
- Localization static-key coverage and bilingual merge-payload validation: passed, 70 entries
- Xcode project/catalog integration and scaffold checks: passed in an isolated temporary copy only: 36 referenced Swift source files, 158 merged bilingual keys, deterministic project regeneration; shared files untouched
- Static JSON parsing: passed for all 40 synthetic JSON literal fixtures
- 24 XCTest methods written for wire methods/paths/body formats, optional credentials, token-header rejection, gateway/envelope auth precedence, error-vs-empty semantics, home section identity, nullable fields, rich detail, category tokens, code tables, scalar duration variants and terminal states

`swift`, `swiftc` and `xcodebuild` are absent from this execution environment. Swift tests, actual SwiftUI compilation, UI tests, screenshots, simulator/device accessibility and live backend validation have **not** run here. Root's approved macOS CI must run `swift test` and unsigned simulator builds before treating this batch as compiled. No live requests, test accounts, production hosts, commits, GitHub actions or user-Mac work were performed by this module worker.
