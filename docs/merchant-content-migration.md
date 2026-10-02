# Merchant content, recruitment and station workspace

Status: authored in isolation, ready for integration review. No shared application files were edited. Apple compilation, Swift tests, simulator/UI execution and live acceptance are **NOT_RUN**.

## Delivered surfaces

- Recruiting-route discovery reads `marketing-home.recruiting.items` once with fresh marketing-read permission. No duplicate coupon-summary/funnel requests are added.
- Merchant-only hosted-project list (`scope=MERCHANT`), project workspace and player roster. Host and participant projections are independently displayed. Player contact details are shown only when returned, with the server's contact hint. No client-generated contact data or masked-but-retained contacts.
- Chapter recruitment with the source's server-message mode routing: free-exploration chapters, classic-node registration, missing merchant category and non-merchant states remain distinct. Empty/unpublished player detail falls back to the merchant projection. Failed registration lookup is unknown, not “not registered.”
- Chapter applications, withdrawal, chapter-node configuration using owned templates, owner review, invited-merchant selection using the exact `(chapterId, memberId)` pair, and pending-node review. Invite explicitly means pre-approved application; approval is admission, not endorsement.
- Registration filters, details and creation/editing. Seven clearable content fields are always sent; creation additionally sends `mode=1`, `nodeId` and optional `cooperateDate`. Update preserves immutable `topicId` for validation and omits dates, template, ownership, award and financial fields. Cancellation reads enriched details and requires a known non-winning status.
- City-node catalog, quota, claim search, claim, offline/online and placement. Placement requires explicit address confirmation and an owned template; optional manual coordinates use the exact `lat/lng` form keys and radius 80. A successful response requires a positive application ID and never fabricates an online node.
- Node NPC and voice-state/reference editing. Node endpoints are **not** store NPC endpoints. NPC save is multipart `nodeId/name/avatar/greeting`, including empty greeting. Voice enrollment uses one `voiceSample`, never the store's five-sample array. No microphone, camera, upload, sound playback, clone-provider or avatar-provider execution is present.
- MERCHANT game entries, strict merchant projection, per-station preparation checklist/capacity/service times, acceptance, decline, readiness, pause with a source fallback plan, resume and player-submission verification. Available-actions union must also match the exact session and selected-station states.
- Source-backed poster and live-code reads remain separate. Poster requires a returned approved chapter-node record; live code requires a playable, configured station and valid session state. Live-code text expires from its immutable response-received timestamp; reopening a view does not reset TTL. QR image rendering, download and photo-library saving are not implemented.
- Host circle-instance supply review uses exact JSON `topicId/scope=MERCHANT`, only for a returned host projection with a circle code. This is separate from Cooperation's offer lifecycle.
- A typed `MerchantContentSupplyContext` joins application and recruitment chapter by actual chapter ID. Unknown terms or absent offer state do not create enrollment grants. `EnvironmentValues.merchantContentSupplyDestination` is the optional integration hook into Cooperation's own UI.

## Request and recovery safety

`MerchantContentService` constructs actual URLRequests and uses injected `HTTPTransport`. Every document load and mutation preflight first fetches fresh `merchant/access/me`; content pages require the source project-management permission. Node-NPC and game views require active access and the source endpoint's own authorization/projection rather than inventing new permission keys. All reads recheck account, credential, epoch and deployment storage scope after awaits.

The default execution setting is disabled. Writes additionally require an explicitly marked `MerchantContentOfflineTransport` and a pending journal. Production `URLSessionTransport` does not implement that marker, so a misplaced test flag alone cannot enable network writes. Only the synthetic DEBUG transport and test transport implement the marker in this delivery.

Immutable reviews bind the source snapshot, session stamp, command, target and fields. Confirmation rereads source and permissions, then compares the complete baseline. Changes abort before dispatch. The journal is written before transport and excludes tokens, contacts and ordinary content drafts. Its key includes stable deployment scope, account, merchant and target. Game recovery additionally preserves the full frozen command. File storage is atomic with mode 0600; corrupt/unwritable storage fails closed.

Ordinary content timeouts, malformed acknowledgements and HTTP ambiguity retain a durable lock. A list looking like the intended result cannot remove it. There is no invented content operation-receipt endpoint. Definitive non-auth business rejection releases the corresponding pending record and retains its original message.

Station operations follow the actual source protocol: POST command, then GET receipt; command HTTP 200 alone is not success. Receipts must bind `activityId/requestId/action`, positive terminal `receiptId` and nonnegative revision. APPLIED and FAILED are terminal; other/malformed results stay locked. Reconciliation reads the same receipt. Explicit replay first requires a correlated PENDING receipt, then fresh access and the same permitted source revision/station, and sends the exact original request ID and payload. A read timeout or mismatched receipt never authorizes replay.

## Important source gaps and deliberate limits

1. `blocked_by_backend_test.dart` says recruitment XP is validated but not persisted. No XP input or submitted `xpValue` is added. The published chapter XP limit may be displayed as source information. No claim is made about a newer backend fix.
2. `merchant_city_node_page.dart` sends `application.id` into a wrapper named `poiId`, but its application model does not establish that mapping. Native cancellation is blocked unless an explicit positive `poiId` accompanies a pending claim application. Application ID is never substituted.
3. The Flutter chapter application screen submits application then node sequentially. This native UI makes the two operations explicit: apply, refresh applications, configure the node. Pending and approved chain membership permit configuration. It does not pretend those writes are atomic or automatically replay either step. This is a UI-flow difference, not an absent endpoint adapter.
4. Cooperation owns offer enrollment/reconfirmation/pause, perk templates, financial commitments and their execution restrictions. This module supplies only correctly scoped context and a navigation hook. Before integration supplies that hook, the native UI reports the supply context without promising an active supply action.
5. Service times are validated civil strings (`YYYY-MM-DD HH:mm`) without inventing a timezone. Current/future eligibility remains a server decision. No device location is captured.
6. Source roster and registration privacy rules are not replaced with account-role guesses. A missing field remains absent. Unknown review/game states do not enable actions.
7. No provider/media integration, real backend, publication, moderation, recruitment, membership, money movement or redemption happened. Actual remote write activation remains a separate acceptance task; the current marker deliberately excludes the live transport.
8. The normal merchant entry, supply bridge and DEBUG launch gate must be wired by the integrating parent. This isolated delivery is not yet a mounted production feature. Pages beyond source first-page caps are explicitly disclosed; this module does not invent pagination that wrappers do not expose.
9. Full image/QR rendering, device accessibility, layout on small/large displays, theme/locale behavior and resumed foreground sessions still require Apple runtime verification. Code presence and parser success are not runtime parity.

## Evidence

- 46 literal endpoint paths checked against retained Flutter wrappers
- 62 authored Swift core tests and 7 authored XCUITest flows, **NOT_RUN**
- 229 bilingual localization entries
- 11 Swift files: pinned Tree-sitter parse passed with no recovery nodes
- Source/localization guard script passed
- A disposable copy of the current target plus these files/catalog entries passed project regeneration and scaffold validation: 415 Swift sources in structural inventory, 3,293 bilingual keys; these are overlay counts, not tested or merged counts
- Swift, Xcode, simulator, physical devices, live API: **NOT_RUN**

Source fingerprints and the exact endpoint inventory are recorded in `merchant-content-static-evidence.json`. Tests and local gates can be rerun after integration; source checks do not substitute for Apple's compiler or runtime.
