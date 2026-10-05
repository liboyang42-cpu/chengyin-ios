# Native roam/map read module

## Delivered scope

`RoamBrowserView(reader:)` is a native iOS 17 SwiftUI/MapKit read-only browser with four independently loaded layers:

- City/merchant places, with local type filtering and authenticated POI detail
- Route locations from the map nearby endpoint, with a distinct ID domain
- Activities/themes, with local kind filtering; retired hangouts and unknown kinds are excluded
- Nearby walkers, using only a source-backed public whitelist and approximate positions

Map and list share typed rows and stable namespaced identities. Rows without valid coordinates remain in the place/route/event list without fabricated pins. Duplicate IDs are deduplicated within their domain. Search filters the current result set locally. Layer and radius changes reload; panning a map never sends a request. Detail cards contain readable source-backed fields, without dead action buttons. The place detail can independently display supplemental public merchant information and its top-level featured item.

The service additionally supports the optional exploration-day recommendation contract; its `success(null)` means no recommendation, and it has no invented map coordinate. This optional recommendation is not yet displayed by the browser.

## Integration contract

Create `RoamSessionReader(service:currentSession:searchArea:onUnauthorized:)`, then inject it into `RoamBrowserView(reader:)`.

- `service` is optional. Nil produces the not-configured screen. There is no default host.
- `currentSession` returns `RoamReadSession(accountID:epoch:token:)` from the current verified account. The epoch must advance on logout, expiration and replacement login, including the same account signing in again. The credential is not exposed to views.
- `searchArea` returns an explicitly supplied `RoamSearchArea` or nil. An area consists of a validated coordinate and a descriptive label. Nil produces the area-required screen and performs no transport call. The separate `RoamAreaPicker(onSelect:)` supplies native manual latitude/longitude entry. Root integration presents it and keeps the selected area only in memory. Empty inputs never select default coordinates; invalid/nonfinite/out-of-range values are rejected; Cancel never calls the callback.
- Do not fill this area from GPS automatically. Supplying a real location for a remote search requires its separate authorized workflow. No such workflow is implemented or invoked here.
- The public-merchant service method permits anonymous use as in the source; the browser uses its session-bound reader for consistent clearing of all detail state.
- `onUnauthorized` receives only the captured matching session. Results and errors from an old account, epoch, token, or area are discarded. An obsolete 401 cannot sign out a replacement session.
- The caller should keep the reader stable and re-render/rebuild the view when its session or explicitly supplied area changes. The view's request identity includes account/epoch/area/layer/radius/configuration and clears the selected card on reload.
- The root integrator owns navigation/session wiring, string-catalog merge and Xcode project generation. This module does not edit those shared files.

No real map is shown if a search area is absent. The chosen center is always a search area, never a user-location indicator. MapKit uses the backend-supplied coordinates in the same manner as the retained Flutter MapKit layer. The backend documents GCJ-02; native-device alignment in supported regions remains an acceptance check. No guessed coordinate conversion is added.

## Exact retained source contracts

All paths below are relative to the explicitly approved API base path.

| Native method | Flutter source | Wire shape |
| --- | --- | --- |
| `places` | `lib/data/api/roam_api.dart:pois`, `lib/data/models/roam.dart:RoamPoi` | GET `api/roam/pois`, query `lat/lng/radius`; default radius 3000 |
| `routeNodes` | `lib/data/api/map_api.dart:nearby`, `lib/data/models/nearby_node.dart` | POST `api/map/nearby`, multipart `longitude/latitude/radius/limit`; defaults 2000/50 |
| `events` | `lib/data/api/roam_api.dart:hangoutNearby`, `lib/data/models/roam_social.dart:RoamHangoutNearby` | GET `api/roam/hangout/nearby`, query `lat/lng/radius`; `data.items` |
| `players` | `lib/data/api/roam_api.dart:nearbyRunners`, `lib/data/models/roam_social.dart:RoamRunner` | POST `api/roam/nearby-runners`, multipart `lat/lng/radius`; no presence/session fields |
| `exploreDay` | `lib/data/api/roam_api.dart:nearbyExploreDay`, `lib/feature/roam/nearby_explore_day.dart` | GET `api/roam/nearby-exploreday`, query `lat/lng`; null is normal |
| `nodeDetail` | `lib/data/api/roam_api.dart:nodeDetail`, `lib/data/models/city_node_detail.dart` | GET `api/city/nodes/{id}`; `poiId` identity; authentication required by `roam_poi_detail_page.dart:_load` |
| `merchantDetail` | `lib/data/api/roam_api.dart:publicMerchantDetail`, `lib/data/models/roam_merchant_info.dart` | POST `api/merchant/public-detail`, JSON integer `id`; `featured` is a top-level sibling of `data` |

Additional behavior is grounded in `lib/feature/roam/roam_team_markers.dart` (do not render retired hangouts), `lib/feature/roam/roam_live_page.dart` (walker privacy and POI types), `lib/core/network/dio_client.dart` (raw Authorization credential), and `lib/core/util/coord.dart` (backend coordinate system).

HTTP status is checked before decoding. Gateway 401 and envelope code 401 precede optional message/payload decoding. Only envelope code 200 is success; a malformed envelope cannot silently become an empty map. Node-not-found business messages become a distinct unavailable state; other failures remain errors. Null/missing arrays are empty. Null node detail is malformed, never a fabricated empty place. The detail and merchant response identities must match the requested identity.

The native layer deliberately tightens unsafe source defaults:

- Invalid/missing place coordinates remain absent rather than becoming zero/zero
- Unknown POI types and retired/unknown event kinds are not displayed
- Fractional exploration-day IDs are not accepted as positive integer identities
- Player coordinates are defensively reduced to three decimal places before storage; already-coarse values are preserved despite binary rounding noise
- Unknown merchant opening status is omitted, not asserted as open
- Privacy-sensitive fields outside the public whitelist, remote media URLs and raw server error messages are not held in these DTOs or displayed

`status == 1` is the only published POI state. Missing, null or unfamiliar statuses are not promoted to published. Boolean completion/favorite flags accept only booleans, not numeric/string truthiness. Walker percentages clamp to 0...99; negative counts/durations are not displayed.

## Privacy and excluded work

This module contains no CLLocationManager, authorization request, user-location annotation, location button, GPS/presence reporting, location storage, route trace, check-in, favorite mutation, roam start/stop/finish, join/leave, ticket purchase, payment, or navigation-to-player action. It does not log or persist requests or coordinates. Live searches necessarily transmit the explicitly supplied search center to the configured backend; that is not enabled by choosing a fake device position. No live request was made during implementation.

Nearby walker information is a last-loaded snapshot, labeled as such. It is cleared on reload and session change; there is no background refresh, assumed live presence, distance-to-person label or precise coordinate disclosure. MapKit may fetch its own basemap tiles when rendering; this does not turn the fixtures into backend-connected data and must be considered separately for an airplane-mode/device acceptance check.

The full roaming experience remains unimplemented: fog reveal/history, session recovery/settlement, authenticated interactions/check-in, teams, public content media, permissions/consent flow, registration/payment and backend validation. This is a substantial read module, not completed roam parity.

## Offline fixtures and verification

`RoamFixtureReader` is DEBUG-only and has no URL, host, token or transport. It uses fixed synthetic coordinates around `(1, 1)`, and the UI labels them as offline examples. Scenarios: content, empty, failure, unauthorized, unconfigured, missing area, missing coordinates, unavailable place, unpublished place and supplemental merchant failure.

`localizations.json` contains 82 `{key,en,zh-Hans}` records for root catalog merging. New files are restricted to the assigned roam prefixes, this document, and the localization handoff.

36 XCTest methods were authored across `RoamContractTests`, `RoamServiceTests`, `RoamSessionTests`, and `RoamAreaInputTests`, covering exact methods/paths/fields, raw auth, null semantics, status precedence, malformed/gateway responses, role-safe/public whitelists, precision reduction, invalid coordinates/IDs, private-session invalidation and request-center changes. They use injected transports and never reach a network.

Verified in the current Linux workspace:

- All 82 localization records have nonempty English/Chinese values and unique keys
- Every static roam UI localization literal has a matching handoff record
- The service contains exactly the seven reviewed read paths
- Fixture source contains no remote URL
- No shared project, root session, or shared string catalog was modified

Not run: Swift compilation, `swift test`, Xcode build, simulator/UI tests, MapKit rendering, Dynamic Type/VoiceOver visual review, device-region coordinate alignment, and live-backend acceptance. `swift`, `swiftc` and `xcodebuild` are absent in this workspace. Root integration must generate the project and run those gates on the approved macOS CI path; static checks do not establish a build pass.
