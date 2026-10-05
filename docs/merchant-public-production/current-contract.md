# Current merchant public/NPC factory boundary

## Implemented, dormant by default

F02 now has normal `NativeRuntimeDependencies` → `AppSession` → production-factory → public-home reader composition. `MerchantPublicProductionApproval` is an exact CN backend/namespace/account (or separately approved anonymous context) capability. All fields default off/empty. Public requests contain exactly one `id` (merchant row) or `memberId` (owner) and never a session token. Returned identity must match the requested identity; missing IDs are never substituted. Account, token, role, epoch, region, namespace and backend changes invalidate retained work before and after awaiting.

F01's supported merchant-row chat seam now uses the same normal factory with an independently specified row allowlist and server/provider/legal grants. Chat does not grant ownership, voice cloning or media access. Every dispatch first re-reads the public row and verifies its NPC identity. Exact source JSON is `requestId`, `bizId` (merchant row), `message`, at most 300 Unicode code points. This never enters the play-node shop-chat domain.

A write-ahead local journal retains request UUID, deployment/account and merchant row only. Unknown/malformed, mismatched receipt, retryable/processing, stale session and cancellation outcomes retain the lock. Same-request retry uses the original UUID and fresh readback. Another UUID for that row is blocked across host recreation. Only the exact request's known terminal nonretryable source status clears the marker. No text, response, token or audio is persisted in that journal. There is no invented status/reconciliation route. If the caller loses an unresolved UUID after restart, a fresh request remains blocked; a separate supported recovery UX is not claimed here.

No live model, backend, device or upload was called during authoring. This is a composition packet, not production activation or live acceptance.

## F01 legacy resource incompatibility is a native/source gap

The current `ApiMerchantController` does not support the legacy native five-sample voice workflow or generated-avatar workflow. The normal `.assets` host fails closed before its existing legacy reader can call speculative endpoints. `resourceClient()` stays dormant. This is not a missing external permission and enabling grants would not repair it.

Supported CURRENT workflow requiring a new native adapter/UI:

1. `POST api/merchant/npc/profile`: authenticated `PROFILE_WRITE` access, authoritative server merchant row; returns the owned profile under `data`, including disabled/unapproved editable content
2. `POST api/merchant/npc/save`: profile/name/avatar/greeting/persona/knowledge editing. Ownership derives from server access, not submitted profile ID. Avatar is an accepted `px1:` preset or allowed uploaded image; save is not image generation
3. `POST api/merchant/npc/voice/enroll`: a single `voiceSample` URL plus `voiceConsent: true`, not `sampleUrls` or a five-item array and not a requestId-based native enrollment contract. The owned NPC must already exist. Same sample while pending/ready returns its existing status; an already-pending different sample is rejected. The native replacement needs a single-clip capture/upload/review UI, an explicit ownership/authorization consent, fresh owned-profile/permission proof, bounded sample validation and a durable unknown-write lock
4. Enrollment returns top-level `voiceStatus`, not an envelope `data` resource object. A successful request never alone means the voice is ready: 0 unset, 1 pending, 2 ready, 3 failed
5. `POST api/merchant/npc/voice/status`: top-level `voiceStatus` and optional `voiceSample`; pending status can query the upstream voice provider and update readiness. This read therefore needs its own explicit provider acceptance, not an assumed harmless static profile read
6. `POST api/merchant/npc/voice/reset`: clears the current owned voice; no `requestId` is accepted. The new UI needs a separately reviewed reset action, post-action status readback and no automatic replay after uncertainty. Reset is not evidence of deleting an upstream provider voice asset

Current server comments describe a single mp3/m4a/wav sample, 10 seconds–5 minutes and at most 20 MB. The replacement must separately verify actual capture/upload enforcement and provider acceptance rather than treating these comments as end-to-end validation. No upload/device permission is introduced by this packet.

No CURRENT matching backend operation exists for:

- `api/merchant/npc/voice/script` or five server-provided scripts with `consentIndex == 0`
- `api/merchant/npc/voice/revoke` (use a separately implemented current reset workflow; do not relabel provider deletion)
- `api/merchant/npc/avatar/generate` or `api/merchant/npc/avatar/status` (current profile avatar editing is separate)

F01 therefore remains partial for voice/profile/editor parity. F02's host gap is closed. No backend upgrade, future theme NPC, AI feature plan, market/home redesign, merchant engagement, template assist, Square, club-review, official or social-action work is included.

## Source and verification

Source comparison: current backend revision `f280c988305df257545edc0b48a62d61690ef0e8`; `ApiMerchantController.java`, `ApiAiNpcController.java`, `NpcChatService.java`, `NpcChatReq.java`. The optional contract comparison uses `CHENGYIN_BACKEND_SOURCE_ROOT` and explicitly reports NOT_RUN when absent. Supplying a missing or incompatible checkout fails.

Authored tests exercise the actual pure-Core factory and normal App dependency factory using ordinary in-memory HTTP recorders. Static checks and Tree-sitter parsing are supplementary; Swift execution, App unit execution and unsigned Apple builds require Apple CI. No runtime pass is inferred from authored tests or parser success.
