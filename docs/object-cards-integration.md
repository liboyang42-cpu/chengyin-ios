# Object cards and badge source migration

## Result and exact scope

Additive files only, under `native-object-cards-new`. No main checkout, production setting, user media, external API, permission, upload, share, renderer package, or licensed asset was changed or accessed.

- Authenticated `POST /api/object-card/list`, **application/x-www-form-urlencoded**, exactly `pageNum=1&pageSize=40&category=<wire value>`. JWT-only ownership; no user ID in request. Numeric/string 200 envelope support and exact nine category wire values.
- This is the entire source *feature*, not the entire historical collection. Source intentionally caps each category at the latest 40. UI labels that cap and reports backend total separately. No pagination or fetch-all endpoint invented.
- Models retain ID/name, frames/source/cutout, validated normalized cutout box, caption, category, place, foil/plain and raw generation status. Rotation uses available 2D frames. Cutout box is metadata and is not applied a second time to already cut-out image URLs.
- Last-successful-filter semantics, loading/empty/failure distinctions, refresh and retry. Back navigation retains successfully loaded category. Task cancellation and generation invalidation prevent delayed publish. Reader snapshots account, epoch and token; same-account relogin changes scope. Stale 401 never expires a newer session.
- Source-style native cards, details, explicit frame buttons and VoiceOver adjustment. Static presentation has no motion to disable. Uses existing card composition with nil artwork URL so no unrestricted AsyncImage fetch can bypass media gate.
- Additive richer badge wall/detail reuses existing ProfileService badge-wall-v2 and medal-wall reads and partial-state handling. Identity category tracks, locked/obtained state, statements/unlock hints, city conditions, achievement condition omission, China-calendar date semantics and static enamel/glow visuals. `/badge` route query normalization is separately available; category track is not mislabeled as rarity on identity details.

## Important source finding: no 3D migration

Audit: `app-audit/lib/feature/p3/badges/badge_detail_logic.dart`, `badge_detail_page.dart`, `badge_wall_logic.dart`, `object_cards/object_cards_page.dart`, `lib/data/models/object_card.dart`, and both APIs. Full source file scan found **zero .glb/.gltf/.usdz/.scn/.obj assets**. The Flutter source explicitly calls the legacy `badge-3d` route a static preview. Object frames are image URLs; no mesh or model URL exists. Therefore this port does not add a renderer, model, reconstruction, GLB support, USDZ conversion, new third-party dependency or invented geometry. A real 3D feature would be a separate requirement needing real source assets, rights, format and renderer decisions.

## Additive integration in main checkout

1. Copy the six `Core/Object*.swift` files, three `App/Object*.swift` files, tests, tools and this document into corresponding main directories. Keep `ProfileBadgesView.swift`: its internal `ProfileBadgeSelection` is reused. No Core model modifications are needed.
2. Merge `Resources/ObjectCardLocalizations.fragment.json` `.strings` into `Resources/Localizable.xcstrings`; preserve unrelated keys. Fragment adds 51 en/zh-Hans keys. The fragment generator writes only the fragment.
3. In `AppSession`, hold `ObjectCardSessionReader(service: nil, currentSession: { ... })` by default. Mirror `currentAccountCollectionSession`: account ID, session epoch and token must come from the same live session. The unauthorized callback must compare the captured snapshot before expiring credentials. Only an explicitly enabled approved API configuration may construct `ObjectCardService` with the existing ephemeral/no-redirect API transport. The core service has no default host.
4. Add an account NavigationLink to `ObjectCardsView(reader: session.objectCardReader).id(session.objectCardReader.scope)` under the existing account/session observation. A recomputing host is mandatory: reader closures alone do not publish session changes. On logout or any epoch change, replace the destination stack/identity so old sheets and detail state cannot persist. Capture selection scope at the row, not at the later destination invocation (already done in these views).
5. Change the `ProfileAccountLinks.swift` badge destination from `ProfileBadgesView(reader: reader)` to `ObjectBadgeWallView(reader: reader)`. This eliminates that path's unrestricted AsyncImage and opts into the richer source preview. Preserve existing ProfileReadScreen host session identity reset. The older view may remain for compatibility but should not be the new route.
6. Optional source `/badge` route: normalize query using `ObjectBadgeDetailParameters(query:fallbackName:)`; construct `ObjectBadgeRoutePreview` with an account/epoch-bound opaque scope and localized fallback name. No new remote detail call is needed. The badge read API does not expose full historical object cards or a mesh.
7. Register `case objectCards` in `ModuleFixture` and `case .objectCards: ObjectCardFixtureHostView()` in `ModuleFixtureRootView`. UI tests use `--uitesting-module objectCards`. This fixture does not load media or call services. It includes source total > displayed count, two frames, queued/failed generation states, empty categories, one-shot failed filter and epoch rotation. Add XCTest source to UI target through the existing generator.
8. Run `tools/generate_project.py` and applicable aggregate checks after integrating; this directory is intentionally not an independently buildable duplicate app.

## Media activation and security

Default `media: nil` in every entry point: no image requests. Optional `ObjectCardBoundedImageLoader(policy:)` uses explicitly approved exact HTTPS origins; no wildcard host fallback. The data delegate rejects every redirect, authentication except platform TLS handling, non-image MIME, unexpected response URL, and oversized Content-Length. Accumulation stops before >12 MiB. Ephemeral session has no cookie store, credential store or URL cache. Image signatures are checked before UI decoding; ImageIO metadata must show positive dimensions totaling <=32 million pixels. Credential-bearing query strings are never displayed, persisted or logged; only source origin appears in metadata.

Only inject the concrete reviewed loader (or a test-only synthetic loader); the protocol itself is not a sandbox for arbitrary implementers. Injection activates image loading automatically on visible rows/selected frames and must stay behind the host's media/live gate. No actual remote test was performed. Stream/cancellation/TLS behavior needs Apple runtime verification before activation. No API token is sent to the media loader.

## Validation (2026-10-02)

- PASS: `python3 tools/check_object_cards.py`: 12/12 supplementary source checks against actual Flutter source and native files.
- PASS: existing pinned Tree-sitter Swift parser: 11 files, zero recovery nodes/diagnostics.
- Authored: 12 XCTest core tests and 3 XCUITest flow tests, synthetic only. Covers exact form contract, cap/status, frames/cutout fallback, invalid data, category/query normalization, media policy, badge dates/tracks, failed filter, stale 401, stale success, cancellation and dormant reads.
- NOT_RUN: Swift typechecking, compilation, `swift test`, Xcode project generation in shared main, XCUITest, Apple SDK availability, screenshot/VoiceOver/Dynamic Type runtime review, stream transport/redirect integration tests. Swift/Xcode/device are unavailable in this environment. Parser/source checks are not compiler or runtime evidence.

## Remaining work

The host integration above is intentionally left to the coordinating main-checkout integration pass. Production API/media configuration stays gated. Device validation remains required. No source-supported 3D implementation is missing; the historical name must not be used as a promise of 3D rendering. The Flutter decorative gathered/scattered overlapping pile is replaced by an accessible native card list; no physics pile simulation is claimed. Source's delayed automatic error-navigation is intentionally replaced with explicit retry so an error does not unexpectedly dismiss an accessible screen.
