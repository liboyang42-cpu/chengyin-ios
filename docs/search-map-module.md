# Search and map native migration slice

## Implemented and integrated

A distinct global-search entry in the Home toolbar opens `SessionGlobalSearchView`. The existing Home activity/topic feed filtering remains separate. Source page families are `feature/search/search_page.dart`, `search_result_page.dart`, `search_filter_sheet.dart`, `city_node_search_page.dart`, and `feature/map/map_page.dart`, `map_controller.dart`, `map_scene_mapper.dart`, `route_preview_sheet.dart`.

- Global search fans out across topic, activity, club and merchant sources, keeping independent failure and guest-gated states. Counts and type chips are based on visible first-page rows. Empty query without category makes no request; topic/activity requests are capped at the source's first 12 each. There is no invented all-pages promise.
- Source date/price fallback filters are applied locally only to topics/activities. Topics have no source price filter; missing dates/prices remain visible. Native text-entry dates additionally reject invalid calendar days and reversed ranges. The source 0–1000 slider range is retained without implying a currency conversion.
- Search history remains local, bounded to ten and deduplicated. The native adapter uses device-only Keychain storage with a regional/deployment/account namespace, no query upload. Fixtures/unconfigured views use memory only. Storage failures are visible and do not block search.
- City search independently reads 50 activities and authenticated city nodes within the source 20 km radius. Sort, category, keyword, merchant tag and city role retain the source's distinct parameters. Missing-coordinate activities stay in the list; missing/zero-pair city POIs never become pins. A node failure does not hide activity results.
- Nearby map uses the separate 2 km/50 route-node source and optional reverse-city result. City fallback/rate-limit is not reported as a failed node list. Nearby route node IDs never become city POI IDs. Valid `topicId` can open the existing topic detail; otherwise the native sheet shows only the source stop/address data.
- Typed topic/activity/club destinations reuse the existing native domains. Merchant IDs open the existing verified `public-detail` contract in a native public merchant detail view, never the merchant console. Flutter search itself routes by `memberId` to public-user pages; this slice intentionally supplies proper merchant detail rather than misrouting a merchant ID to that user domain. Public-user-home parity remains separate.
- City POI detail uses `/api/city/nodes/{poiId}` and validates returned identity. Merchant references can open merchant detail. `templateId` is displayed as a template reference and is never treated as a topic ID. Favorite/check-in/validation mutation flows are not added.
- Native MapKit rendering is opt-in and uses supplied/manual centers only; it contains no device-location API, map-pan upload or current-position annotation. Synthetic UI fixtures do not mount MapKit or fetch tiles/artwork.
- Route preview supports walking/driving/transit mode selection, injected route geometry/steps and a truthful local dashed straight-line fallback. The fallback has no invented ETA or instructions. No real location, live directions provider, turn-by-turn tracking or external Maps launch is mounted. This is not full source directions/guidance parity.

## Contracts and session safety

Exact audited reads:

| Route | Method/body |
|---|---|
| `/api/category/list` | POST multipart `parentid=0,type=1` |
| `/api/topic/list` | POST multipart `is_my,keyword,category_id,pageNum=1,pageSize=12` |
| `/api/activity/list` | POST multipart same paging; map only adds `sort_type,longitude,latitude,pageSize=50` |
| `/api/club/list` | POST JSON `name`; guest local gate |
| `/api/merchant/list` | POST JSON `name` |
| `/api/city/nodes` | GET `lat,lng,radius=20000,keyword,categoryId,tag,cityRole`; guest local gate |
| `/api/city/nodes/{id}` | GET authenticated detail |
| `/api/map/nearby` | POST multipart `longitude,latitude,radius=2000.0,limit=50` |
| `/api/map/reverse-geocode` | POST multipart `longitude,latitude` |
| `/api/merchant/public-detail` | Existing Roam adapter, POST JSON merchant `id` |

Services are created only inside AppSession's already-approved regional/deployment/storage-scope configuration block. Current production API configuration and approval registries remain unchanged and empty. Interface language does not configure backend region or coordinate system.

Every reader request captures account ID, epoch, credential and a credential-free UI scope. Stale success, errors and unauthorized callbacks are rejected. Guest epochs distinguish intervening sign-in/sign-out cycles. A current authenticated 401 from any global/city aggregate is not silently reduced to a partial source failure; it expires only that captured account. Guests retain public siblings and an explicit login gate. Query gates additionally prevent an older request, changed input, dismissed view or mode change from replacing current UI data. Categories have their own gate so their reads do not invalidate search results. Back navigation preserves loaded results; session changes reset the search stack.

## Integration and checks

The initial integration was executed from `native-search-map-new/tools/apply_search_map_integration.py` against the native checkout. The tool copies only this module's files and patches explicit AppSession/Home/ModuleFixture anchors; it does not publish code. Later module edits must be reconciled before rerunning it. `Tests/ContractChecks/test_search_map_contracts.py` is part of the aggregate Python contract suite. `tools/check_search_map.py --flutter ../app-audit` adds retained-source checks when that checkout is present.

Authored fixture entry: `--uitesting-module searchMap`; optional `--uitesting-search-map-entry global|city|nearby|route` and `--uitesting-search-map-scenario content|empty|partial|guest|failure|retry|unauthorized|unconfigured|delayed|cityFallback`. Global activity/club fixture detail destinations are routing sentinels, not business-detail acceptance; production routes reuse the real native views. Merchant/city/map/route fixtures exercise this module directly, and topics reuse the existing fixture reader.

Twenty-one Swift core methods cover wire shapes, auth precedence, guest skipping, partial sources, local filters, invalid coordinates, typed IDs, map-city fallback, history bounds, route fallback and session/query races. Nine authored UI methods cover filters/cancel, domain navigation, guest/partial results, missing-coordinate lists, city/nearby detail, route fallback, session reset/retry and English/Chinese large-type/dark/Reduce Motion presentation. These are authored tests, not executed Apple evidence.

## Remaining acceptance gates

Swift typechecking/builds, SwiftPM XCTest, simulator XCUITest, screenshots, VoiceOver, actual device Reduce Motion and maximum Dynamic Type remain NOT_RUN in this Linux workspace. Local Python assertions and Tree-sitter parsing are not a substitute. Source/backend deployment acceptance, regional map coordinate-system validation, live providers, location/privacy permissions and real road guidance remain outstanding. No live account/backend write, location capture, directions/provider request, remote publication or user-computer action occurred during this work.
