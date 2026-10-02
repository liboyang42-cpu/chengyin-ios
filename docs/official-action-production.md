# Official action production composition

The normal AppSession factory now accepts an optional OfficialActionProductionApproval through NativeRuntimeDependencies. Defaults, regional registry and deployment configuration remain OFF. This is local implementation evidence, not deployment, device or live-account acceptance.

## Verified operations

The existing ApiOfficialEventController source defines these POST actions and GET projections:

- Legacy publish: api/official/publish; publisher permission and owned my-published readback
- Broadcast: api/official/broadcast; explicit audience/channel/content and optional owned event, then owned my-published readback. Submitted notification is not delivery
- Signup: api/official/events/{id}/signup; fresh event detail, followed by detail readback. Signed status does not establish attendance or reward eligibility
- Legacy completion: api/official/events/{id}/complete; only the existing non-V2, non-roam contract. The source increments progress and has no client idempotency key; no automatic retry
- Party responses: api/official/v2/parties/{partyId}/{action}, plus dedicated official organizer accept/decline routes; fresh party inbox and official publisher permission where required

The private backend verification included the controller, OfficialEventServiceImpl, OfficialEventV2ServiceImpl, CoopInviteServiceImpl and OfficialEventV2Mapper at the approved migration source. No backend code, schema, dependencies or configuration changed.

## Safety boundary

Approvals bind the exact immutable command and payload, account, namespace, CN market, API origin, closed paths and reviewed policy version. They are composition inputs, never remote flags or saved user preferences. Normal configuration provides no approval.

The coordinator performs fresh snapshot equality checks and atomically records a durable local replay lock before minting the production dispatch authorization. A direct send on the production access object always fails. The private transport accepts only the expected POST URL, method, headers, body and current credential, once. Review cancellation, task cancellation and account/epoch/token/role/origin changes fence dispatch and results. Existing locks survive new coordinators, relaunch and sign-out. Recheck after asynchronous preflight prevents two coordinators from racing past the same lock.

Readback uses only the command's exact GET allowlist. A malformed, failed or rejected readback after a successful POST is unknown, never an excuse to release the pending lock or retry. A returned publish/broadcast ID must appear in the owned projection. Signup unlocks later event actions only after independent detail shows signed=true. Increment-only completion remains locked even when acknowledged. The source party inbox filters out declined/withdrawn rows; a missing row is inconclusive and retains the lock. No absent row is labeled a confirmed decline or withdrawal.

## Deliberately unresolved source context

- Merchant invitation: the retained native command contains merchantIds only. Backend createOfficialMerchantInvites requires topicId and validates optional node/terms. OfficialMerchantInviteEditor currently has no normal callers and accepts no authoritative topic/node/terms. It cannot receive production approval until a source-backed caller and complete reviewed request are implemented
- Arrival: the current detail host does not supply an OfficialArrivalEvidence value, and no real producer supplies an authoritative current roam session plus approved fresh location sample. Production grants reject this command. Location/session values and request IDs are never fabricated
- No new endpoint, generic operation switch, retry key, receipt route, World/Map/NPC path, reward claim or backend capability has been added

## Verification

24 focused Swift production tests are authored, in addition to existing action tests. They cover OFF-by-default, scope/content binding, bypass rejection, exact review bytes, readback, unknown locks across recreation, storage failure/corruption, competing locks, cancellation and identity changes. The local Linux environment has no Swift or Xcode: Swift execution, typechecking and Apple builds remain NOT_RUN locally and must be established by integration CI.

Offline checks: focused official Python contracts, complete Python contract suite, supplementary pinned Tree-sitter parse and deterministic project/scaffold generation. These do not establish business, device or deployment acceptance. The assembly owner regenerates the Xcode project after combining this packet with other isolated changes.
