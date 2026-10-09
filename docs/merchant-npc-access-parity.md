# Merchant NPC character access parity

## Narrow correction

The native store-character destination now requires the explicit `merchant:profile:write` permission from the existing active merchant access response. A supported owner, manager, check-in, marketing or finance role label alone does not grant this capability. Unknown active role identities still fail the existing decoder, even if a profile permission string is present. This changes the shared access projection used by the ordinary workbench entry, character profile reads, and dormant write preflight. No endpoint, permission grant, role mapping, production configuration, or backend authorization is added or relaxed.

Previously, an active merchant without this permission could see the character entry and attempt its owner-profile request. The server still required the permission and would reject that request. This is client/server entry and preflight consistency, not evidence of successful unauthorized data access or writes. Ordinary `AppSession.merchantOperationsReader` still receives neither endpoint approval nor a write journal; its saves remain disabled.

## Verified frozen source

Private source reference: `liboyang42-cpu/chengyin` at `ce61c0bbace743ff835cb297ef41c89b52181636`.

- `chengyinhub-admin/src/main/java/com/chengyinhub/web/controller/api/ApiMerchantController.java`, blob `ac739a411d2de90de83bebecf482508e1d363a2a`, lines 741–765: `/npc/profile` and `/npc/save` call `merchantAccessService.require(memberId, MerchantPermission.PROFILE_WRITE)`. Identity comes from the authenticated context. The profile endpoint intentionally returns the owner's pending/disabled character for editing.
- `chengyinhub-xcx/pages/merchant/decor/ai-npc/index.wxml`, blob `c390dc72f237add08f5ab66333b36a63d290745b`, lines 5–6: the NPC page access gate requires `canWriteProfile`.
- The voice status route in the same controller also requires `PROFILE_WRITE` at lines 931–937. This does not establish the complete legacy `.assets` contract: `/npc/avatar/status` is absent from this controller. The ordinary native assets router is already blocked by `MerchantPublicProductionFactory.supportsLegacyResources = false`. The existing `.assets` and `.cityNodes` access behavior is deliberately unchanged.

Private source bytes remain outside the public candidate. The optional source test requires exact Git blob hashes and fails for supplied missing/mismatched evidence; without the evidence root it reports a skip.

## Existing lower-level safeguards

- `MerchantOperationsHomeView` filters entry destinations with this same `access.allows` projection.
- `MerchantOperationsSessionReader.document` refreshes access before requesting the profile. The service rejects missing permission before its character transport request. An access check itself still makes the authorized `access/me` request; “zero requests” in direct service tests means zero protected profile requests once a denied access snapshot is supplied.
- The session reader already captures account, token, epoch, viewer/access revision, and scope. A changed account/revision or sign-out during either read drops the late response. An explicit server denial does not install a character. Reload clears the prior character before obtaining newer access. This patch does not invent a push-based revocation signal; an unreported server-side change cannot be known locally until refreshed or rejected.
- Dormant writes already refresh access again, compare the baseline, and require an independent endpoint approval, current-session check, and durable journal. The corrected projection now rejects a missing profile permission before its profile read, journal write, or save request.
- Successful save character-readback, unknown-write replay locks, provider/media/legal grants, character validation, avatar/voice/map UI, and live activation remain unchanged.

## Remaining AI/NPC dependencies

The six-category knowledge service inspected at ce61 (`MerchantNpcKnowledgeDraftService`, blob `588033fedd42ca6f0f5a02ab33ad86ffac84e932`) explicitly supplies no HTTP endpoint or approved-source adapter. Its review operations require a separately installed `MerchantNpcKnowledgeReviewAuthority` and route; its switch defaults off. Native UI must not invent routes or turn drafts/review previews into approved public NPC knowledge. This client entry fix does not resolve that backend/product dependency or establish real provider/model acceptance.

## Verification

Fourteen focused Swift XCTest cases are authored for explicit permission across every supported MerchantAccess.Role case, unknown-role decoder rejection, preserved assets/city behavior, denied zero-profile-request and allowed exact requests, fresh access, revoked reload, account/revision/sign-out interruptions, server denial, write-preflight denial, and ordinary write gates.

Executed locally: all eight focused Python checks passed, including the exact-ce61 comparison; related merchant checks collected 236 (231 passed, five explicit external-source skips); the full native Python contract suite collected 2,473 (2,425 passed, 48 explicit skips); structural scaffold verification passed; all three changed Swift files passed the pinned Tree-sitter 0.26.0 / Swift grammar 0.7.3 parse with zero recovery diagnostics. Patch-scope and replay verification are recorded in the candidate report. Swift execution/typechecking, Xcode/simulator/device tests and real backend access are not available in the Linux workspace and are not claimed passed. No backend/provider request or repository push was performed.
