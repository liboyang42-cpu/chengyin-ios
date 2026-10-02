# Publishing modes: additive integration packet

## Scope and verified source

Implemented from `app-audit/lib/feature/publish`, publisher identity helpers, activity_publish.dart, my_project.dart and API wrappers. Source is current Flutter, not older mini-program assumptions.

- Quick/simple UI is a route seed, **not direct publication**. AI parsing rejects incomplete and >3-node plans wholesale; AI coordinates are discarded. Each node requires an explicit POI confirmation. The `ai_simple` seed, product 1/2, chapter/node identity and source free default ticket feed the existing ProjectEdit workflow. Historical `publishMode=simple` create request is a descriptor only.
- Activity uses independent `ActivityPublishDraft` and play-template ID; source-required cover, venue, title, description, categories, time and ticket fields validate before review. Dates are wall-clock strings, not device-zone-translated instants. Strict time ordering, ticket inclusion and positive stock are retained. Missing price differs from explicit 0. `categoryIds` is CSV; `collaborators` is always an array, including empty; cover maps to both imgUrl/imgArr.
- My Projects preserves typed topic/activity/template IDs; unknown types are retained separately and never dispatched. Delete, topic toggle with expectedUserStatus, activity toggle and template library status use distinct routes. Full raw baseline comparison prevents stale actions. List supports exact source filters, scope and first-page limit, with truncation text. Cancellation/refund eligibility is informational only; no guessed financial operation is sent.
- Source identity is registration, never certification. China 18-character checksum/date/name/consent/source rules are pure ephemeral helpers. Status fails closed, receives only registered, has no personal detail. Already-registered change goes to platform support. US registration is explicitly unsupported. Identity has an independently approved, executable dormant adapter and synthetic transport tests. No identity collection UI is mounted; no identity payload is persisted. Production does not construct this auxiliary adapter.
- POI search has injected protocol, stale-response generation control, cancel/clear, selectable named results, native map and coordinate accessibility fallback. The MapKit adapter is disabled by default and never asks for device location. Categories/member collaborators/quoted play templates use exact read shapes. Topic-only reward form writes selfPlay/price/quota, optional medal metadata and existing coupon ID into ProjectEdit preserved fields; it does not author or redeem coupons.
- AI quota read and theme-draft/template-fill/club-design/safety-precheck descriptors are source-backed. A separate PublishingAuxiliaryService implements exact executable HTTP paths behind independent endpoint approval and a persistent operation journal. It is not mounted in production, and US provider execution remains unavailable pending a regional contract. No provider request was actually made. Existing TemplateAuthoring remains owner of play-template editing; ProjectEdit remains owner of pro/update/edit-detail adapters and complete route validation.

## Files and composition

The package is integrated in chengyin-ios. ProjectEditLaunchView links to SessionPublishingModesView, reachable from account and home publishing entries. Session host injects account/role/region and a stable UUID keyed by the session gate, account ID and role. It switches typed resource.kind to TopicDetailView, ActivityDetailView or DiscoveryTemplateDetailView. It resets navigation/seed state on session changes.

AppSession.makePublishingService takes optional explicit read approval; the default is nil and returns no service. PublishingApprovedReadTransport checks exact host/path/account/namespace against a read-only path allowlist before and after requests. No mutation approval or journal is mounted by the host. PublishingMapKitAdapter is passed in disabled mode; approved deployment composition must explicitly enable it. Production never constructs PublishingAuxiliaryService.

Quick-route seeds enter the existing retained ProjectEdit coordinator via ProjectEditView(seed:). Seed application requires matching originating session, full editable scope, no unknown pending operation, a new-topic target and no unresolved saved draft. Existing restore/conflict/unknown state is never bypassed. If a saved draft exists, the user must resolve it before explicitly choosing the incoming seed. ProjectEdit continues to own route validation, secure persistence and HTTP contracts.

The ProjectEdit form now binds PublishingTopicRewardsForm to preserved source fields. Intermediate text is retained locally; ProjectEditValidation checks reward price/quota/coupon validity before review. Whitelist edits cannot change rewards. Coupon authoring/claim/redemption is not added.

Quick/activity forms now offer explicit save/restore using PublishingDraftStore over ProjectEditSecureStorage. Active pointers are separated by account, region and mode and are stored in the same secure storage interface. The complete envelope checks identity, owner, version and baseline; there is no UserDefaults fallback. No identity form content enters this store.

The Debug --ui-publishing-modes launch branch mounts PublishingModesFixtureHost and prevents production AppSession construction. Shared Localizable.xcstrings contains the new keys; computed labels use the environment-aware appLocalized helper. The Xcode project and six exhaustive UI shards have been regenerated. Auxiliary review data is transient; its journal stores opaque operation/owner/target only. Identity confirm rereads registration status and blocks rebind. AI player access is rejected locally; server gates remain authoritative. Safety precheck unavailability stays a soft content gate while retaining an uncertainty marker to prevent repeated provider requests.

## Safety and intentionally unavailable outcomes

An uncertain write is account/deployment scoped and survives logout/relaunch. Project actions lock their business identity; activity-create uncertainty locks all new activity creation for that account so regenerating local draft IDs cannot bypass it. HTTP malformed/transport/stale-account results stay unknown. There is no source receipt/status-by-operation endpoint, so no automatic reconciliation, resend or unlock control exists. Explicit valid business responses release the lock; success is only acknowledgment, not approval/online publication. A failure clearing the journal stays unknown. No actual publications, uploads, identity transmission, financial action, provider request, credential or deployment change was performed.

Management membership/ownership is established through the authenticated /api/project/my result plus reread, not guessed permission fields. Server remains authoritative. Unknown row types have no actions. Future paging is not invented: source always sends pageNum=1; narrow filters or higher source-supported limit rather than implying arbitrary pagination support.

## Tests and status

- 39 authored Core XCTest methods across PublishingModesTests (28) and PublishingAuxiliaryTests (11), covering domain rules, wire encoding, fake HTTP dispatch, default-off grants, account/role/region boundaries, persistent retry locks, source safety soft-gate semantics, transient identity data, exact identity status-before-submit, secure draft restore and endpoint approval isolation.
- 4 authored XCUITest flows, with Debug fixture host mounted. Tests remain NOT_RUN.
- 10 new integration contract assertions plus 10 supplementary source checks.
- Aggregate current evidence is recorded in publishing-modes-verification.json. No local structural check implies Swift compilation.
- Swift compiler/type checking, XCTest, XCUITest, iOS simulator/device, accessibility runtime and visual QA: **NOT_RUN** (Swift/Xcode unavailable on Linux).
- Focused Tree-sitter diagnostics are supplemental only. Full repository parse retains the known unrelated diagnostics, recorded separately.

## Remaining gates

1. Run the Apple toolchain, authored Swift/UI tests and dynamic type/VoiceOver checks before claiming runtime parity.
2. Resolve US publisher identity and provider/legal contracts; no invented international validation or automatically enabled provider.
3. Approve and configure read/MapKit/provider/identity/upload/publication capabilities independently. Current live defaults stay off. No identity collection UI is mounted, and no upload provider has been enabled.
4. Unknown mutation outcomes need authoritative support/reconciliation; no source receipt API is invented and no automatic replay/unlock exists.
