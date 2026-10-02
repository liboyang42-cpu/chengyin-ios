# Runtime dependency wiring audit and integration

## What was missing in code

The normal navigation to PlayExperience was already mounted. However, both AppSession play service construction paths forcibly supplied the service's empty capability default. The otherwise-real HTTP clients could therefore never obtain the parent snapshot. Nested specialized PlayKit screens, chapter/story, ending, leader, circle, preference and prefab surfaces remained behind that empty read gate.

The new composition takes an optional `NativeRuntimeDependencies` in `AppSession.init`. Its default is `.dormant`. An independently reviewed `RuntimeDependencyConfiguration` can now be passed to the *normal* session root, with an optional fake HTTP transport for tests. `RuntimeDependencyFactory` mounts the existing source-backed clients. The request wrapper captures account, token, session epoch, role, regional market, complete base URL and storage namespace and rechecks before dispatch and after completion. Only exact approved API paths can pass. There is no endpoint, sample account, login bypass or demo-to-live fallback.

Additional genuine composition gaps repaired:

- PublisherLifecycleHostContext no longer discards an injected read grant. The normal pricing preview and partner-inspection client can use the approved transport. Pricing writes, refunds, transfers, graduation and creator application approvals stay separate and absent
- Nearby merchants now has an actual device-fix → source coordinate conversion → existing multipart `api/merchant/nearby` → merchant list pipeline. A normal-root environment destination mounts it from the existing merchant/cooperation navigation. Entering is inert; the user must accept the location purpose and press Locate and search
- PlayKit sensor, artwork-host and spatial approvals now travel through both the normal node/advanced route and the chapter inline route. Source task data cannot enable these dependencies
- Stillness now has a concrete acceleration streaming adapter, using the existing native sensor implementation and its m/s² conversion
- Prefab and ordinary play device factories can now use a scoped concrete camera/library/scan/location provider rather than a hard-coded dormant provider. Location uses the audited WGS84→GCJ02 conversion and rejects stale or inaccurate fixes
- Shop NPC text dispatch can receive separate pre-approved server/provider/legal/access grants through the session composition. Its existing current-node authority, explicit production-write switch and exact-path network fence all remain mandatory
- Logout, credential rotation and account/role changes cancel active device, location, streaming sensor and retained parent runtime work. Cached parent readers now include the epoch and role

## Exact external configuration still required

Nothing in this packet activates any of the following. Do not derive these inputs from server task fields, local language, device position, user defaults, launch arguments or the endpoint string itself.

1. Regional account boundary: `RegionalLaunchConfiguration` still has an empty reviewed `approvedBaseURLs` registry and empty `verifiedCapabilities`. Supply the exact approved CN base URL including port/path, `QuestifyMarket=CN`, an accepted `QuestifySessionRealm`, valid bundle namespace and independently accepted CN login capability. Existing session bootstrap, keychain and legal/provider gates remain unchanged. This packet intentionally rejects use of these CN runtime contracts under US market configuration
2. Per-account runtime acceptance: construct `OperationEndpointApproval` for that exact base URL, `RegionalSessionStorageScope.service`, authenticated account ID and explicit source API paths. Place it in `RuntimeDependencyConfiguration(market: .china, ...)` and pass it to the normal AppSession composition. An approval for another account, namespace or base path fails closed. A resumed/new login captures a new session epoch/token/role
3. Parent journey reads: opt into `.reads` and approve `api/play/nodes`; branch projects also require `api/play/route-state`. Run readback/results need `api/play/run-session`, `api/play/run-session/list`, `api/play/ending`, `api/play/leaderboard`; leader progress uses `api/club/lead/team-progress`. Supplying only a read path does not activate writes
4. Advanced PlayKit: `.advanced` plus `api/play/advanced/start` and `api/play/advanced/action`, with `.reads` and `api/play/advanced/state` / `api/play/advanced/leaderboard` for authoritative refresh. These are real server-session starts/actions, not local simulation. Their existing review, version, idempotency and unknown-result behavior is preserved
5. Other play features: independently opt into `.classicCompletion`, `.runPersistence`, `.hints`, `.leader`, `.playerCommands`, `.circle`, `.preference`, `.tags`, `.directorCommands`, `.mediaUpload`, or `.thoughtClaims` only with the exact source paths needed by the configured experience. Dynamic resource paths (e.g. play OS/tag and chapter claim paths) must be individually approved. See `Core/PlayExperienceService.swift`, `PlayAdvancedRuntime.swift`, `PlayGameSessionRuntime.swift`, `PlayPreferenceRuntime.swift`, `PlayDirectorRuntime.swift`, `PlayPhotoEvidence.swift` and `ChapterThoughtSync.swift`; no wildcard/all-capabilities shortcut is introduced
6. Journey extras: `journeyReads` covers `api/play/encounter` and `api/play/companionLine`; `journeyChecks` covers `api/play/check/{action}`; `journeyCollect` covers `api/play/egg/collect`. These flags are independent from parent reads and classic completion
7. Pricing/partners: `publisherReads=true` and exact `api/topic/pricing/preview`, `api/topic/xp-budget`, `api/club/detail`, `api/merchant/public-detail` paths as needed. Ownership is still established by the existing topic/club/activity readers. This config deliberately does not create pricing-confirm, refund/cancel, ownership, graduation or application mutation approvals
8. Nearby merchant lookup: `nearbyLocation=true` plus exact `api/merchant/nearby`, a real signed-in session and nonempty installed `NSLocationWhenInUseUsageDescription`. Only then can the page's explicit purpose consent and OS When-in-use permission permit a fix. Requires a ≤30-second-old, ≤100 m fix. Query stays source `radius=5000`, `limit=30`; raw coordinates are not persisted. A lead ID is never used as a public member ID
9. Native play devices: explicitly select `devices` from `.photo`, `.scan`, `.location`, `.motion` as independently accepted. Camera/scan needs installed `NSCameraUsageDescription` and OS camera authorization; library uses the system picker. Image upload additionally needs `.mediaUpload` and `api/common/uploadOSS`; the uploaded image still requires review before completion. Location additionally follows the real-fix conversion path; no manual search-area substitution
10. Sensor screens: `sensors` selects `.acceleration`, `.soundPeak`, `.heading`. Required installed descriptions are respectively `NSMotionUsageDescription`, `NSMicrophoneUsageDescription`, `NSLocationWhenInUseUsageDescription`, plus supported physical hardware and relevant OS permission. Sound measurements never become recorded/uploaded audio. Runtime instances are screen-owned and canceled on session/lifecycle invalidation
11. Artwork/AR: approve exact HTTPS artwork hosts separately. Spatial modes use `PlayKitSpatialApproval` with `.plane`/`.marker`; marker calibration is an exact marker URL→measured width in meters. AR still requires its existing device/camera checks and a server-validated scan. No calibration or asset authority is inferred from payloads
12. Shop NPC text: separately supply `ShopNPCGrants.server/provider/legal/access`, set `shopNPCWrites=true`, approve exact `api/ai/npc/shop-chat`, and retain active unlocked node authority. A deployment grant is not user consent or legal acceptance. Voice additionally needs its specific provider/format/transmission/microphone approvals and a configured capture consumer; this packet does not supply an audio-recording workflow or synthesize a response-audio contract

## Intentionally still bounded

- These changes make configured normal composition possible; they are not evidence of live endpoint, real-account, device, payment, privacy, legal or store acceptance
- Walk/WeRun encrypted-step proof is not supplied by iOS local motion. No proof adapter/backend contract is invented
- AR model/GLB rendering remains unsupported by the image-only spatial implementation; marker mode requires real calibration
- Existing platform audio/external-map consumer grants and public merchant home/review/image-reader grants remain owned by their original modules. Nearby list navigation does not silently enable those readers
- The four existing points/mall product-hide decisions are untouched
- Runtime configuration is injected by the reviewed composition root. There is no in-app “enable everything” switch

## Source evidence

- Flutter `lib/data/api/play_api.dart`, `lib/feature/play/*`, `lib/feature/play/stillness_platform.dart`, `lib/feature/play/stillness_challenge_controller.dart`, `lib/core/util/coord.dart` at source revision a63e9e9
- Flutter `lib/feature/coop/nearby_merchants_page.dart`, `lib/data/api/merchant_api.dart`, `lib/data/models/nearby_merchant.dart`: explicit GCJ-02 provider, nearby multipart query, memberId public-home route
- Flutter `lib/data/api/topic_api.dart` and existing PublisherLifecycleHTTP: pricing preview/partner contracts
- Current backend `ApiMerchantController.nearby`: authenticated POST `/api/merchant/nearby` accepts longitude/latitude/radius/limit. Backend access and phone visibility remain server-owned
- Existing native real service implementations remain the request/response authority. No private backend implementation, endpoint deployment, credentials or production response was copied into this packet

## Verification boundary

23 new fake/isolated Swift tests are authored (18 Core, 5 AppUnit). They use synthetic credentials, fake transports and fake fixes only. Python contract checks and Tree-sitter parsing are supplementary evidence, not Swift typechecking or Apple/runtime evidence. Use the packet validation report for exact executed counts and merge-time results.
