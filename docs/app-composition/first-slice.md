# Native composition: first local slice

## Scope

The normal `QuestifyApp → AppSessionContainer → AppCompositionRoot → AppSession → SessionRootView` path now accepts a typed reviewed deployment, injected HTTP transport factory, scoped token-storage factory and local defaults. Fixture roots remain separate and skip normal session creation. The shipped `RegionalLaunchConfiguration.composition` is explicitly unconfigured; no live endpoint or capability has been approved by this patch.

`ReviewedAppDeployment` independently validates exact market-scoped endpoint registry membership and regional capability evidence, and constructs the bundle/market/endpoint/realm storage identity. `CompositionHTTPTransport` restricts the first slice to reviewed CN SMS send/code login, authoritative session restoration and logout, plus an explicit home/search read grant for existing POST routes. A separate typed [public route-template read grant](../public-template/composition-read-grant.md) authorizes only exact catalog/list and projected/detail request shapes. A URL or authenticated account alone cannot enable other routes. Normal legacy services and explicitly injected factory transports pass through this boundary. Private home now has a separate exact owner/realm/role GET/PUT/DELETE grant and mandatory secure-journal composition, documented in [private-home session composition](../private-home-session-composition.md). Its grant and secure-storage primitive remain nil by default. Other mutations, Apple/WeChat provider exchanges, media hosts, location, payments and feature routes require later separately reviewed composition work.

The session-bound dependency builder receives the actual authenticated `RuntimeDependencyContext`. It is rebuilt when account, role, epoch, credential or deployment context changes; an atomic commit guard prevents combining the old account with a new credential. No `OperationEndpointApproval` is created from authentication or remote booleans. The transport rejects old credentials before dispatch and rejects both success and error replies if the session changed while suspended. Logout clears the token and records its tombstone before remote revocation.

The storage factory preserves existing `OperationDefaultsJournal` serialization and canonical account/deployment owner keys. It does not prepend a new namespace, migrate locks or erase pending operations on logout. Existing unknown records therefore remain visible and block a replacement operation under the same owner/target. The factory does not replace every feature's separate file/media storage system.

## Verification

Authored app-hosted recorder tests cover:

- Normal session container/root mount, login, home categories and global search, logout and cold-start tombstone
- Restoration, account/role changes and exact dependency contexts
- Missing review/capabilities/read grants with zero network calls, including authenticated sessions lacking read grants
- Delayed home reply after logout and stale credential rejection before dispatch
- Explicit wallet factory transport cannot bypass the first-slice route boundary
- Existing unknown-operation journal compatibility and account/deployment separation

The tests use synthetic `example.test` URLs and memory token storage; the recorder never opens a network connection. Root mounting is an app-hosted lifecycle smoke check, not a tapped end-to-end UI acceptance test.

Local source checks passed: 861 Python contract tests (46 explicit external-source skips), 89 tooling tests, scaffold/project determinism and supplementary Tree-sitter parsing of changed Swift files. These are not Swift compiler or Apple runtime evidence. Swift, Xcode, simulator/device and live provider tests were unavailable and were not run. Existing aggregate Apple CI and unsigned app-hosted test gates must run against the exact resulting tree before integration readiness is claimed.

## Required deployment inputs and remaining work

No production values are supplied. A deployment reviewer must provide:

1. Market: this slice implements CN existing auth contracts only; US auth remains unavailable.
2. Exact HTTPS API base URL, including any deployment path, and a separately reviewed market-scoped registry entry. No suffix matching or runtime-derived allowlist.
3. Native bundle identifier and explicit deployment/session realm. Changing either intentionally changes local credential scope; no legacy credential migration is implied.
4. Verified `domesticChinaPhone` evidence for the exact SMS/code-login/current-public-account/logout contract, including actual provider readiness, server-side OTP limits and the current role-bearing account projection. `.usernamePassword` cannot enable the incompatible legacy route. Apple/WeChat remain outside this slice. See [CN native session contract](../cn-native-session-contract.md).
5. Explicit `homeAndSearch` read review for banner, category, topic, activity, club and merchant-list POST routes. The grant does not include map location/reverse geocoding or other read APIs.
6. For later operation/device/provider features: independent exact deployment/account/path grants, legal/contract acceptance, provider verification and explicit OS/user consent, where applicable. Authentication never substitutes for them.
7. An approved Apple toolchain to run unsigned compilation, app-hosted recorder tests and actual root UI flow tests. Signing, activation, App Store work and live validation are separate and not performed here.

The typed deployment is installed at `RegionalLaunchConfiguration.composition`; do not add a remote boolean or widen the host list from Info.plist. A custom composition can be injected into `AppSessionContainer` for tests and reviewed deployment integration.

This is deliberately the first composition slice. Social member-action access/coordinators now rebuild for the exact runtime context and revoke escaped references, including their fallback read transports. Some existing lazy payment and contextual feature consumers still retain their original dependency objects. They remain dormant and their routes blocked here; they must be rebuilt/scoped and tested before those features are enabled. No claim of a live or complete app is made.

## Contract correction

Normal-root recorder tests now use SMS-code exchange followed by current-account readback. A synthetic password success did not establish compatibility. Source-only checks and authored recorders do not establish provider delivery, Apple runtime acceptance, or a usable deployed login.
