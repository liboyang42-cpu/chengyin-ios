# W15: bounded foreground walking slice

This is an implemented, default-off first slice, **not completion of W15 or launch approval**.
No location/directions request was executed while developing it. No key, SDK, permission,
background entitlement, signing, deployment or production grant was added.

## Composition and authority

`NativeRuntimeDependencies.walkingNavigation` is nil by default. `AppSession` supplies its
ordinary `NativeWalkingNavigationFactory` through the search navigation environment.
City/nearby links pass entity identity only. Existing untyped search-center/destination
coordinates are not trusted as location evidence or target authorization.

An enabled, exact-context factory requires an injected `WalkingTargetAuthorizing` reader
and separately accepted MapKit WGS84 regions. It binds account, credential, epoch, role,
market, backend URL and storage namespace. There is no invented backend endpoint.
The target reader must authenticate the actor and return only the current allowed target,
with exact reference, revision, story release, datum, region and short expiry. The first
slice caps authorization at five minutes and stops when it expires. It does not obtain a
list of future nodes, choose the next station or reorder a story.

Start/resume and every automatic replan reauthorize before obtaining location or routing.
Cancellation, view dismissal, background transitions and session changes fence late results
and cancel both providers. Permission denial/required, unavailable target, unsupported
coordinates, weak/stale GPS, missing routes, provider/network failures and throttling are
separate states. Three consecutive accurate off-route fixes can replan, with a 30-second
cooldown and two automatic replans per coordinator. Manual retry is explicit.

Only already-authorized foreground CoreLocation fixes are read. Navigation itself never
requests permission. It does not grant gameplay device capabilities or location sharing.
Provider routing transmits the origin and allowed destination only after the separate
production approval and user start; it performs no presence/track upload.

## Route and progress

`MapKitWalkingRoutePlanner` conforms to `SearchRoutePlanning`, accepts walking only and
returns the actual `MKRoute` polyline, steps, road distance, expected duration and advisories.
The adapter's executor is protocol-backed for tests. No synthetic straight line is a
navigable route. Unconfigured legacy previews now say walking route unavailable.

The foreground UI shows the current authorized destination, route, provider, instructions,
accuracy and approximate remaining distance/time. Projection onto provider geometry is a
best-effort progress estimate, not lane-level, indoor, audio or safety-certified guidance.
Provider steps are shown verbatim in their returned language; no translation is invented.
Near-destination only shows a verification prompt. An optional existing-verification callback
can be injected by a future story host; no arrival, task-completion, reward or redemption API
is called. Existing search hosts do not yet provide that story-verification callback.

Address and business hours can be displayed when supplied. No entrance/floor fields are
invented from an address or map pin.

## Coordinates and Mainland China gate

Apple defines `CLLocationCoordinate2D` using WGS84. The adapter passes verified WGS84 input
through unchanged and renders returned MapKit geometry unchanged. These official type
contracts and offline tests **do not verify Mainland China routing/rendering behavior**.

Existing CN targets use GCJ02. They fail closed in this first adapter. The legacy
`RuntimeLocationProjection` is not used to reverse-convert or double-convert targets.
A real mainland walking provider/renderer contract remains required before W15 can be
considered complete. The typed target and `SearchRoutePlanning` boundaries keep route
providers separate from story progression. A future GCJ02 provider must additionally supply
an explicitly reviewed fix-to-provider coordinate adapter and matching renderer; changing a
region allowlist alone must never relabel a GCJ02 point as WGS84.

Tencent is an existing provider integration candidate, rather than a reason to assume a new
account or key is needed. The existing geometry-only route surface is not the W15 contract:
review its failure behavior before reuse. Use a single current-target walking contract that
preserves real geometry, steps, meters, duration units, provider/datum, fetch time and errors.
Do not treat a stitched route that substitutes straight lines as walkable.

Before activation, verify existing account/product/commercial scope and current provider
terms, including internal proxying, caching and display on the selected basemap. Tencent
route data must not be placed on Apple Maps merely because coordinate tests pass. If a
Tencent-native renderer is required, its official iOS SDK dependency is a separate reviewed
change, not included here. Credentials remain server/user-controlled and must not be copied
from web-service configuration into the app.

## Recovery and remaining acceptance

`WalkingNavigationCheckpoint` contains only reference plus exact owner namespace. The
factory rejects mismatched identity and restores idle; explicit resume reauthorizes and
requests a fresh route. **No durable checkpoint storage** is wired in this slice. Process-restart
recovery remains an integration gate; in-view pause/resume is implemented. No cached route
is used while offline. Low-power adaptation, map matching across ambiguous crossings,
voice/lock-screen/background navigation, structured merchant entrances and backend target
DTO wiring remain out of scope or dependent gates.

Offline synthetic tests exercise the shipping factory plus MapKit adapter with mock route
execution and location. Python structural checks and Tree-sitter parsing are supplementary.
Swift/Core execution, Apple SDK typechecking, app-hosted unit tests, simulator UI execution,
real routing and device walking acceptance: **NOT_RUN in this Linux workspace**.

Required field checks: flagship station 1→2→3, single shop/side node, locked target and
revocation, correct entrance, mainland WGS84/GCJ02 controls, covered regions, road closures,
off-route cooldown/budget, high-rise/tunnel GPS, airplane mode, denied/revoked permission,
foreground/background, low power, account change and process restart. Never equate a
passing unsigned build with these checks.

## Primary references inspected 2026-10-02

- Apple coordinate frame: https://developer.apple.com/documentation/CoreLocation/CLLocationCoordinate2D
- Apple routing: https://developer.apple.com/documentation/mapkit/mkdirections
- Apple walking: https://developer.apple.com/documentation/mapkit/mkdirectionstransporttype/walking
- Apple route geometry/steps: https://developer.apple.com/documentation/mapkit/mkroute
- Apple route distance: https://developer.apple.com/documentation/mapkit/mkroute/distance
- Apple foreground permission: https://developer.apple.com/documentation/corelocation/cllocationmanager/requestwheninuseauthorization()
- Tencent official route schema, including duration in minutes: https://github.com/TencentLBS/tencentmap-webservice-skill/blob/main/references/api-direction.md
- Tencent official iOS SDK/GCJ02 documentation: https://github.com/TencentLBS/TencentMapDemo_iOS
- Current Tencent API agreement, reached from the official site: https://rule.tencent.com/rule/0c5ee022-04cf-4614-a116-32d9f362552a

The inspected agreement contains commercial-authorization, display, wrapping/redistribution
and attribution restrictions. It does not establish permission for the specific proxy and
cross-provider basemap design; obtain an appropriate product/legal review of the existing
agreement before activation. No agreement was accepted in this work.
