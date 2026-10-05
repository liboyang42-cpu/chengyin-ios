# Native roaming experience batch

## Implemented and mounted

The map toolbar opens **Roaming passport** in the existing map NavigationStack. Native destinations include local history, individual saved sessions with schematic route cards, server-session recovery, live-roam preparation with incremental tile-memory reads, stamp album/detail, memory-only caption preview, city-node voucher parameter/unavailable states, and a legacy-hangout unavailable state. Synthetic entry is `--uitesting-roam-experience` with `--uitesting-roam-experience-scenario`.

AppSession constructs the read service only alongside the existing approved regional API configuration. A history scope binds native bundle/deployment realm (`RegionalSessionStorageScope.service`), market, exact deployment URL and account. Readers also compare token and session epoch. The history adapter uses non-synchronizing, device-only Keychain items. No Flutter storage is imported automatically. Source-history photos are retained as references and never resolved or shared by the history UI.

## Exact retained Flutter contract map

| Source | Native implementation | Important semantics |
|---|---|---|
| `feature/roam/roam_session_store.dart`, `data/models/roam_session.dart` | RoamHistoryRecord/Store, Keychain adapter, history/detail views | Maximum 50, timestamp and server-session deduplication, unreadable vs missing vs empty, no zero substitution for absent metrics, failed read never overwritten |
| `feature/roam/roam_route_math.dart` | RoamRouteSketch/View | Local route schematic includes POI bounds; insufficient track renders honest unavailable state; no navigation claim |
| `data/api/roam_api.dart::sessionFact` | GET `api/roam/session`, one of `sessionId`/`clientSessionKey` | ACTIVE/FINISHED/NOT_FOUND only; response identity checked; finished-but-incomplete receipt never grants/labels a reward |
| `tilesPage`, `tiles` | GET `api/roam/tiles/page?afterId&limit`, GET `api/roam/tiles?limit` | Valid geohash keys, strictly advancing cursor when hasMore, unique loaded count, partial and fully loaded distinct |
| `stampList` / `data/models/roam.dart` | POST multipart `api/roam/stamp/list`, pageNum/pageSize | Response page must match; totals govern paging; 0 unsubmitted stays visible, 2 rejected hidden, unknown review states conservatively withheld; page failure retains rows |
| `shopStreakBadge` | GET `api/roam/badge/shop-streak` | `success(null)` remains disabled/absent rather than failure; not treated as an awarded badge |
| `city_stamp_logic.dart` | caption UTF-16 limit, JS-double barcode math + independent source golden | Caption only, no fake serial/reward; barcode helper is decorative, never voucher issuance |
| `city_node_voucher_logic.dart`, `data/models/city_node_detail.dart` | voucher snapshot/absolute clock, missing/unavailable native page | Code availability is independent from QR image; missing ID has no fake retry; source implementation defaults all non-positive TTL to 300s despite conflicting negative-TTL comment |
| `roam_live_controller.dart`, `roam_live_math.dart` | dormant location boundary, live capability gate, tile/distance helpers | No concrete device adapter, GPS prompt, presence heartbeat, reveal/discover/finish transport or fabricated arrival |
| `roam_hangout_page.dart`, `roam_social.dart` | unavailable destination | Existing native browser explicitly excludes retired hangout kind. This batch does not re-enable create/join/leave/close/report or personal membership reads |

## Safety and correctness choices

All production location, presence, settlement, camera/media upload, stamp exchange, voucher issuance, redemption and legacy-hangout capabilities are hard-off. No actual backend/provider/device operation was executed to verify this batch. No QR, transferable token or usable voucher is manufactured. A manually selected map center never becomes a device fix. Device fixes retain an explicit datum; conversion/provider validation remains unimplemented.

The service distinguishes HTTP status, envelope authorization and malformed responses. Requests use the source's raw Authorization token and no response caching. User-facing failures do not expose credentials or raw transport messages. Album requests deduplicate/update identities, remove newly rejected stamps and reject stale pages after reset/account change. Source moderation state 0 is not mislabeled approved.

Local history extends source shape with optional native serverSessionID and a versioned scope envelope. Only a complete matching settlement fact with matching shop/medal facts can be prepended. Atomic write failure preserves the old bytes. Native settlement capture is not wired, so reading a server result does not fabricate missing local route, duration or photos. A source trip with missing measurements remains explicitly unknown; aggregate values count only recorded samples.

Native UI uses standard navigation/buttons, Dynamic Type-capable stacked cards, VoiceOver labels and Reduce Motion-aware draft preview. The album intentionally uses accessible vertical cards rather than Flutter's rotated collage. Full visual/accessibility acceptance has not run.

## Remaining source gaps

This is a coherent read/local-state batch, **not full roaming parity**. End-to-end live tracking/recovery, reviewed coordinate conversion and freshness policy, durable in-flight finish reconciliation, settlement-to-history capture, discover/checkin/shop visit/reveal/presence, official-event arrival linkage, real camera/photo selection/upload/create/exchange, save/share exports, live voucher issue/renewal/redemption, retired hangout membership and source collage visuals remain disabled or incomplete. Known request construction is now authored in a separately gated dormant adapter; end-to-end live operation and device/media integrations remain incomplete. No undocumented receipt, endpoint or authorization is invented.

## Integration ownership

New module files are prefixed `RoamExperience`, `RoamHistory`, `RoamRecovery`, `RoamStamp` or `RoamVoucherHangout`. Shared edits were limited to AppSession, the map toolbar, QuestifyApp's fixture/normal routes, merged bilingual catalog, deterministic Xcode project, this progress record and exhaustive shard inventory. Existing editor stable ticket identity, CN scoped profile refresh and previously merged modules were preserved.


## Dormant source-backed mutation follow-on

`RoamExperienceMutationContracts` constructs the source's exact POST/multipart fields for reveal, POI discover, shop visit (sourceType 1/2 only), finish, presence, checkin, city-node complete, favorite toggle (bodyless POST), voucher issue, stamp create and stamp exchange. The production adapter denies each operation **before accessing credentials, constructing a request or calling transport**. No constructor flag, backend payload or launch argument can enable it. The adapter is unmounted. Redemption and retired hangout operations are absent.

The request builder is inert. Typed fixtures may inject a fake executor for validation; production uses the hard-off adapter. A device fix keeps GCJ-02 datum explicit; supplying a manual coordinate or fabricating a fix does not make any production effect executable. Three successful-envelope checkin dispositions remain too-far, participating/needs-scan and lit; repeated visits do not show XP as newly earned.

`RoamStampExchangeCoordinator` is an unmounted injectable workflow with a protected atomic journal bound to the complete history namespace/account scope. It stores the exact immutable draft/idempotency key before creation, persists the returned stamp ID before exchange, and never recreates a known-created stamp to retry exchange. The retained Flutter source explicitly requires createStamp idempotencyKey and documents exchange by givenStampId as idempotent. These are the only operations this workflow retries, on an explicit caller invocation; no automatic retry loop exists. A changed draft is blocked while a prior result is uncertain. Journal write failure prevents the next dispatch. Account/epoch replacement stops the second action and clears in-memory receipt state. Durable completion prevents replay across coordinator recreation; no receipt lookup route is invented. It does not acquire/upload photos or perform permissions/sharing.

Additional authored coverage: 12 dormant-mutation/journal tests and one album-navigation retention regression, plus static assertions. Runtime remains NOT_RUN. The album detail navigation fix retains source rows while cancelling pending work, avoiding removal of the NavigationLink that owns the pushed detail.
