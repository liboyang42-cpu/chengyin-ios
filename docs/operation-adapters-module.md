# Project, Club, Merchant and Team dormant transport adapters

Status: source implementation integrated; default production capabilities remain off. No real request, approval, credential change, publication or external operation occurred. Fake-transport XCTest methods are authored, not executed. Swift/Xcode/runtime: NOT_RUN.

## Implemented contracts

- Project: JSON `POST /api/topic/create` consumes a positive numeric/string scalar `data`; JSON `/api/topic/update` includes existing `id` and accepts the immediate `code:200` acknowledgment. Multipart `/api/topic/edit-detail` sends `id` plus the exact personal/merchant owner `scope`; `/api/publish/home` reads the source permission and nullable quota. Existing revision, product/scope, whitelist and stable local ticket identities are retained. No AI precheck or media endpoint is enabled.
- Club: six exact JSON dispatch paths from `club_api.dart` and `club_topic_ops_api.dart`: create, update-mine, three open-settings routes and set-member-role. Fresh create-role/owned-club, owner/admin/member, previous-setting and profile-baseline checks precede each dispatch. Creation acknowledgment may omit an ID; no ID is invented. Setting responses must contain the returned setting value.
- Merchant: exact JSON requests use the existing source field builders for update, decor/save, coop-profile/save, npc/save and city-node/template/submit. Access permission strings, fresh document baseline, hidden fields, JSON-array strings and UTF-16 limits are preserved. Template acknowledgment requires positive numeric scalar `data`; NPC acknowledgment does not mean review approval. Story sends decor title then profile sequentially. Unknown first response prevents the second request. Rejection, cancellation, transport loss or persistence failure after an acknowledged step produces a partial outcome and retains the lock; there is no retry or rollback.
- Team: exact JSON create/join/quit/kick/disband bodies reuse TeamWriteContract. Create requires positive `data.teamId`; other responses acknowledge the known request target without synthesizing a roster, membership or team status. Fresh eligibility or team detail is checked before dispatch. A creation-context loader must reread an owned registration; no owner/activity ID is turned into a guessed registration ID. No join-mode setter is implemented.

## Scope, persistence and honest outcomes

OperationEndpointApproval binds exact base URL, deployment namespace, account ID and allowed path set. Supplying a URL alone is insufficient. Project/Team adapters require a persisted matching local operation before dispatch and persist a dispatch-start marker before handing the request to transport. A recreated adapter cannot replay that marker. These UUIDs are local review identities, never sent as server idempotency keys.

Club and Merchant require a minimal persistent journal. Records contain only local operation UUID, account/deployment owner key, target key and acknowledged-step count. They contain no credential, draft, member names, invitation code or response text. Story/profile/decor/gallery share a conservative storefront target lock because their source writes overlap. Known first-step rejection can clear the lock; partial and uncertain outcomes cannot. Journal corruption and write/clear failures fail closed. Credential epoch/token/session changes or cancellation after dispatch remain uncertain.

Immediate acknowledged results are distinct from DEBUG simulation. The coordinators and review labels preserve that distinction. Ordinary refresh never establishes an earlier operation's outcome. Project and Team receipt methods return no production result without a request; no receipt, reconciliation, idempotency or rollback route was invented.

## Composition and integration plan

All source files and tests are in the current generated project. AppSession still mounts ProjectEditDisabledService, unapproved Club/Merchant access and the unconfigured TeamReadOnlyService. Normal UI cannot create a write grant. Team's factory now accepts an optional independently reviewed read grant and optional OrderLifecycleTeamSource, both absent by default. A supplied creation source rereads its exact registrationID via OrderLifecycleService and validates the full TeamSession before/after the read.

Any later authorized deployment must supply scoped endpoint acceptance, current credential closures and durable journals in the composition root. Project HTTP adapter supports existing-project load, but the ordinary editor factory continues to use its local-only disabled service. Enabling that entry requires an explicitly approved read configuration. Do not add a capability toggle in a view. Before any live enablement, run Swift/type checks, all focused and aggregate XCTest suites, unsigned CN/US builds, simulator interruption/restart tests, actual Keychain/defaults persistence verification and separately authorized backend/account acceptance.

## Remaining gaps

No live acceptance, compiler, simulator, device, media upload, provider generation or permission change was performed. Source lacks a safe way to resolve unknown/partial operations after process loss; production must preserve those locks until a separately reviewed reconciliation contract exists. No automatic resend, matching-content inference or destructive reset is offered. Broad authoring page parity, media/category pickers, runtime navigation acceptance and production entry approvals remain separate work. Project/Team write errors retain coarse existing failure enums; richer server-message presentation can be added without changing the acknowledgment/unknown boundary.

## Verification

24 focused fake-transport XCTest methods cover exact requests, positive/acknowledgment shapes, default-off/scope gates, fresh revision/quota/ownership/access checks, unknown replay blocks, story partial completion, persistent namespace/account/target isolation and coordinator acknowledgment semantics. Seven new source checks verify these boundaries against preserved Dart. Existing module checks now verify dormant dispatch rather than obsolete throw-only placeholders.

After integration: 1,224 authored core methods; 193 UI methods in 28 classes; 2,572 bilingual keys. Six UI shards remain unchanged and exhaustive. Structural/scaffold, 214 source-contract checks, 16 tooling tests, 14 parser self-tests and whitespace checks pass. All 22 new/edited Swift files parse without recovery. Full-tree supplementary Tree-sitter check retains the same 10 pre-existing diagnostics in six files across 461 files. Parsing is not Swift compilation; no XCTest or UI test was run.
