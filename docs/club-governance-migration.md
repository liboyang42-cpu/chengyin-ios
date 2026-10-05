# Club governance and operations migration

Status: integrated locally into the shared native app. This is not release acceptance. Swift, Xcode, simulator and device stages are NOT_RUN in this Linux workspace. No backend requests, real messages, membership/role changes, attendance changes, dissolution, financial operations or remote writes were performed.

## Implemented scope

- 34 exact read adapters plus separately gated QR-image GET, with injected HTTP transport, JSON/form exceptions, business-code handling and strict target validation
- 23 closed mutation adapters that actually build URLRequests, dispatch through explicitly synthetic transports and decode source receipts; ordinary production construction cannot send any of them
- Access/me-driven workspace, including independently scoped event permissions. It does not treat the old administrator flag as the seven-role permission model. All returned roles are retained; only the source's four delegable codes are selectable, with club/event scope separation
- Host profile draft and existing identity-registration status; current account is reloaded and matched. Merchant/host mutual exclusion remains explicit. There is no ID-card field, identity-registration submission, media upload or legal/provider bypass
- Workbench navigation and owner statistics; customer search/filter/list/detail; tags and remark draft; registration-to-check-in detail navigation; nullable paid amounts and server-rendered contact text
- Event topics, series list/detail/future edits, occurrence list/cancellation status, four-bucket roster and version-bound attendance correction
- Governance bans, platform cases, scoped roles/assignments, owner transfer, report/appeal; platform bans cannot be unbanned by a club
- Audience counts, composed notification preview, source IN_APP channel, immutable review, acknowledgment and campaign status/retry. Null counts remain unknown. Acknowledgment never claims every notification was delivered
- Club-specific topic workspace, settings, recruitment and topic customer panels; separate story/chapter/node/template traversal; protected node answers use their own JSON endpoint. Ordinary TopicDetailView is not used as a substitute
- Rankings with nullable pace/timing; executing-club editions; hours/evidence local forms and dormant adapters; settlement amount-verification/void states and dissolution blockers
- Ephemeral group-code receipt and millisecond expiry; URL/credential safety; no automatic renewal, real redemption, image-host credential forwarding or photo-library save
- 327 English/Chinese localization entries, native List/Form/Picker/Toggle/NavigationStack, semantic labels, scalable system text and explicit accessibility identifiers

## Safety model

Production service initialization hard-disables all writes. The alternative initializer requires an explicitly marked offline transport and separate administrative, identity, financial and provider gates. No live registry/capability is added.

Each review binds the exact command, full target scope, account, session epoch, storage namespace, permission snapshot and relevant source readback. Series leads and assigned members are checked against a fresh member directory; owners are excluded from delegated-role targets. Confirm does another read and exact comparison, and SessionAccess independently verifies the immutable review again immediately before dispatch. Source `requestId` fields remain stable for an unchanged draft and rotate when payload input changes. Endpoints without source keys do not receive fabricated idempotency fields.

Conflicts/rejections are distinct from unknown results. Transport failures, cancellation after dispatch, stale-account responses, malformed acknowledgments and 5xx outcomes retain an account/realm/operation/target lock. Reopening or signing back into the same account cannot reset that in-memory lock. Accepted writes also stay locked because a generic success response is not transaction reconciliation. Cross-restart recovery is not established; this is one reason production writes remain hard-off.

Customer phone fields are not reconstructed; raw phone/token/identity fields are removed recursively. Public topic projections also strip accidental protected answer/hint fields. Roster phoneIncluded must be false. No credentials or PII are written to disk, test output or diagnostics.

## Exact sources

Primary APIs: `lib/data/api/club_ops_api.dart`, `club_crm_api.dart`, `club_compensation_api.dart`, `club_topic_ops_api.dart`, `club_api.dart`, `group_code_api.dart`, `publisher_identity_api.dart`.

Models: `club_ops.dart`, `club_access.dart`, `club_crm.dart`, `club_stats.dart`, `club_settlement.dart`, `club_manage.dart`, `club_topic_ops.dart`, `club.dart`, `club_post.dart`, `topic.dart`.

UI constraints: `club_apply_page.dart`, `club_event_ops_page.dart`, `club_governance_page.dart`, `club_roles_page.dart`, `club_notify_page.dart`, `club_ops_access.dart`, `edition_report_validation.dart`. Source hashes are retained in the static evidence JSON.

Encoding details: `/api/topic/info-to-user` and `/api/club/members` are form reads; chapter recruit/finish are form writes; governance/topic/CRM/compensation mutations are JSON. `activityId` is explicitly null in topic-manage-stats/audience/preview/send when no event is selected; it is omitted for unscoped access/roles. Leaderboard/topics/dissolution-blockers use `id`; compensation editions use `clubId`; group issuance sends only `activityId`; retry notification sends only `campaignId`.

## Deliberately unclaimed gaps and separate ownership

- ClubOperations create/update/open-setting/legacy-admin writes remain owned by the adapter batch. This module does not duplicate them
- Full runtime director/club_lead and game-session behavior belongs to PlayExperience; no substitute lifecycle state-changing endpoint is invented here
- Group-code redemption belongs to MerchantBusiness scanner. Payment, refund execution, financial recovery and authoritative settlement readback remain separately gated
- Compensation source only exposes editions, report hours and evidence submission. It does not expose hour/evidence status or reconciliation. The UI does not invent a confirmed/paid state. Source explicitly omits club withdrawal submission; none is added
- Publication/feed browsing is included. Full club-post/comment authoring, likes, revisions and moderation are outside these 23 contracts and remain outstanding unless migrated elsewhere
- Host form is consolidated native input, not a pixel replica of the source's four-step page. Identity registration, certificate upload, US-specific identity/legal rules and actual submission remain blocked by independent acceptance
- Source unspecified money currency and time-zone semantics stay unspecified. Numeric amounts are labeled as source values; no currency is inferred from UI language or region
- QR image GET is available only through the isolated offline-media constructor. The app does not fetch returned images or save to Photos. Issuance expiry is shown; auto-refresh/foreground recovery and real provider behavior remain acceptance work
- Server-owned chapter/event/contact eligibility stays server-owned. The native code is intentionally stricter for malformed booleans, duplicate IDs and missing required counts rather than filling zeros
- Visual design refinement, full VoiceOver/dynamic-type QA, iOS screen captures, signed builds, device tests, deployment acceptance and complete seven-persona backend fixtures have not been run

## Verification

- Source-contract, path, localization and hard-off checks: PASS (`python3 tools/check_club_governance.py`)
- Tree-sitter pinned parser: PASS for all authored Swift files, no recovery nodes. This is supplementary syntax evidence only
- 58 core test methods and 6 UI test methods authored, including looped coverage of every read and dormant mutation. These are inventory, not passing runtime counts
- Swift type checking / `swift test`: NOT_RUN, toolchain absent
- Xcode builds / simulator UI / device / visual / live service checks: NOT_RUN

Static evidence does not establish production readiness or whole-club flow parity. See the integration instructions for the mounted shared-app entry points.
