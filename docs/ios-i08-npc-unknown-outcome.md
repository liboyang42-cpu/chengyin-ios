# CY-HANDOFF: IOS — I08 merchant NPC non-retryable unknown outcome

2026-10-15 UTC. **SOURCE_CANDIDATE / EXECUTION_NOT_RUN / NOT_PUSHED**. This closes one existing merchant conversation response/recovery path, not the entire I08 card. I07 was first reviewed within the bounded checks below and produced no code change.

## Identity, ownership and current dependency

- Repository and continuing branch: `liboyang42-cpu/chengyin-ios:migration/native-ios`.
- Exact published parent: `8e3c74a196017550bd2ca2814cd23970c16dba0f`; tree `9df084d56c9bab69b6d5c2d95eb6d436bf411da7`. Before edits, all 5,081 files in the isolated starting snapshot matched the public tree's Git blob identities, with no missing or extra files. Existing cumulative work was retained; no older unsubmitted implementation was imported.
- Protocol: `CY-COORD-20261015-v1`. Read native `ios-current-status.md`, README and the existing call chain, then `IOS_START_PROMPT.md`, `IOS_HANDOFF.md`, `BACKEND_CHANGES.md`, `COORDINATION.md`, current ownership and relevant task/dependency records at control `53d50db24b83ec856abb7d998d913c79699934dc`.
- I08 dependency: **A02 / BK-AI, CONTRACT_FROZEN, NO_API_CHANGE**. The adapted response already exists in frozen candidate `1e403b135206844a34219753a36e2dee39c7dd59`. The control record's latest rolling checkpoint is `adc7c68e9398a61476bbfd57cab7696094d2b61d` / PR44; the same response tuple was read directly from that candidate. The rolling source is **SOURCE_DELIVERED_UNVERIFIED / NOT_RUN**, and **TEST_DEPLOYED=NO**. Neither earlier backend tests nor this source read establish native execution or current deployment.
- The backend's short summary calls the marker `reasonCode`. The actual `NpcChatResp` getter and response builder serialize the existing field **`errorCode`**. Native code already decodes `errorCode`; no `reasonCode` field or alternate protocol was invented.
- The newer L03 record supersedes the old broad AI-DELETE DRAFT wording only for the frozen implementation of existing deletion semantics: text/log erasure, lease revocation and a write barrier, retaining original unique request/tombstone and charged facts. It is not an all-data erasure promise. This patch does not implement native deletion, change retention, or touch those endpoints. AI-VOICE and CLAIM-MATERIAL remain DRAFT; every capability stays OFF.
- No applicable `AGENTS.md` or `.agents/skills/*/SKILL.md` exists in the native snapshot or its applicable ancestors. The current user instruction defers tests, builds, app execution and CI. No backend/shared control file, external agent, deployment, credentials or payment operation is involved.

## I07 bounded no-change review

The stated I07 concerns were checked against the existing source, not treated as a requirement to create a new feature:

- `Core/WalletCommerceService.swift` keeps `/api/points/list` (`assetPoints`) non-paged with an array payload and `/api/user/points/list` (`points`) on its separate paged table contract. It never adds page fields to the full-list path and rejects a second page for that path.
- `Core/ProfileService.swift` reads the existing identity wall first. A non-auth medal read failure returns those identities with a distinct unavailable medal projection; unauthorized/cancelled reads still fail closed. There is no client-side merge that adds club definitions to the platform result.
- `Core/RoamBadgeWallReader.swift` delegates only the existing badge read and fences the captured reader, account, namespace/scope and epoch before and after suspension. It has no stored result cache of its own.
- `Core/GrowthCenterService.swift`, `Core/GrowthCenterContracts.swift` and `App/GrowthCenterView.swift` consume the separate `me` rank/score, retain optional numbers, and preserve partial overview issues. They do not infer zero from absence in the Top 50 list.

No code gap was established by these bounded checks. Platform/club source membership, cache invalidation across real sessions, live full-list/paged behavior, off-list rank accuracy and device/error-state presentation remain unverified. This is **NO_CHANGE_SOURCE_REVIEW**, not I07 completion or a global no-bug claim. BK-BADGE / BK-ASSET / BK-EXISTING still need the actual approved deployed source and identities for business acceptance.

## Source-confirmed defect and sanitized reproduction

The existing flow is merchant detail entry -> `MerchantNPCChatView` -> `MerchantNPCChatCoordinator.send` -> `MerchantNPCHTTPClient.chat` -> POST `/api/ai/npc/merchant-chat` -> reply/transcript/recovery controls.

Both the frozen and current backend sources return the following tuple when the provider outcome or stored lease outcome is uncertain:

```json
{
  "code": 200,
  "data": {
    "requestId": "the exact submitted UUID",
    "outcomeStatus": "PROCESSING",
    "safetyDecision": "UNKNOWN",
    "errorCode": "REQUEST_OUTCOME_UNKNOWN",
    "retryable": false,
    "safeText": "The original request outcome is unknown."
  }
}
```

The English safeText above is a synthetic fixture, not a claim about the service's localization. No real model, account, merchant or provider is contacted.

Baseline behavior was wrong in two linked places:

1. `MerchantNPCReply.validate` rejected safetyDecision UNKNOWN even for that exact frozen tuple. The coordinator converted the valid response into the local `.unknownOutcome` fallback and offered same-ID retry.
2. `MerchantNPCReply.canRetry` inferred permission from PROCESSING even if `retryable` was explicitly false. Merely accepting UNKNOWN would therefore still violate the response contract.

Expected: preserve the original request and normalized question, display the server's safe notice, do not invent an answer/history entry/audio success, and do not offer retry or unlock a replacement send solely because the valid response arrived. The server's retry denial and a missing transport response are distinct facts.

## Implementation and complete existing recovery path

- `Core/MerchantNPCContracts.swift` accepts UNKNOWN only for the exact PROCESSING / REQUEST_OUTCOME_UNKNOWN / retryable=false combination, still requiring the original UUID, bounded text, and bounded optional delay. Wrong UUIDs, missing fields, other UNKNOWN combinations and unknown outcomes remain malformed. `canRetry` now requires the server's explicit true value; `hasUnknownOutcome` is a local projection of existing fields.
- `Core/MerchantNPCCoordinators.swift` keeps the original ID and input for every non-retryable PROCESSING reply. A successfully decoded server response decides retry eligibility; the absent-response transport-unknown path retains its existing same-ID retry behavior. A server denial is shown as unavailable recovery even on the third local attempt, rather than being mislabeled as an expired local attempt limit.
- Existing `MerchantNPCChatView` already displays safeText and the original outcome. Existing `MerchantNPCRecoveryView` disables retry from `canRetry`; the composer stays locked because requestID is retained. No new view, localization, route, service or recovery panel is added. The generic unavailable recovery label is retained; the returned safe notice supplies the specific unknown-outcome explanation.
- No completion receipt is created. `MerchantNPCConversationHistory` only records its already supported terminal outcomes, so this pending response cannot become a completed turn or erase earlier verified turns. Existing composer retention therefore keeps the user's draft, and success audio remains unavailable.
- Existing local abandonment remains an explicit, one-use UI confirmation with owner/request/attempt/revision checks. Cancel preserves the lock; confirming only releases the current screen's request. Its existing warning says it does not cancel server processing or delete records, and a later new send can incur another charge. This is not a backend cancellation, deletion, resolution or refund.
- Existing background/close/account/grant invalidation and generation fencing remain unchanged. Retiring this in-memory conversation clears private display state and does not send automatically. Cross-process recovery, durable request preservation and server outcome reconciliation are not added or claimed. A newly opened conversation is still the pre-existing explicit lifecycle path.

## Authored acceptance and actual evidence

Nine methods were added to the existing `Tests/CoreTests/MerchantNPCResponseIdentityTests.swift`:

- Exact frozen tuple preserves ID/input, blocks retry/new send, and creates no success/history/audio.
- Mutated or omitted tuple fields and mismatched request identity remain rejected.
- Explicit retryable=false also wins for an already-supported PROCESSING/NOT_RUN response.
- A legitimate retryable-processing response can transition to unknown without changing the original request body.
- Third-attempt server denial takes precedence over the local attempt-limit label.
- Transport-only unknown still recovers by an explicit exact-request retry.
- Earlier verified transcript survives; only existing explicit local abandonment unlocks another send.
- Missing/blank safe notice never fabricates an answer or retry permission.
- Lifecycle retirement clears private state and never automatically replays the request.

Five methods were added to existing `Tests/AppUnitTests/MerchantNPCRecoveryPresentationTests.swift`, covering existing recovery/composer projections, cancellation and one-use confirmation, an obsolete transport-unknown confirmation after a server denial, scope/grant revocation, and a late unknown response from an interrupted conversation after a new conversation succeeds. These are model/presentation tests, not rendered UI or device evidence.

All **14 added methods are authored, NOT_RUN**. The existing files are already wired; no project regeneration is needed. Existing successful, rejected, retryable, malformed and local-unknown tests are retained.

Performed: source reading and manual flow review, public-source/blob comparison, bounded diff inspection, and patch/file hashing. **NOT_RUN:** Swift/Core XCTest, AppUnit, XCUITest, typecheck, Xcode/build, simulator/device, accessibility, lint, Python/Node/Java test suites, CI lookup/dispatch, live networking/provider/account execution, backend integration, deployment, signing or release. No push, merge or backend write was performed by this implementation worker.

## Remaining boundaries and next sequential item

The separate Shop NPC flow has the same safety-UNKNOWN rejection and processing-implies-retry assumption in `Core/ShopNPCContracts.swift`. Its existing coordinator/review/lifecycle is a distinct flow; it is deliberately unchanged for a separate review and delivery after this merchant slice is published. Native NPC data export remains read-only. Deletion admission, real usage/cost presentation, provider availability, and the full I08 card still require their own source/authorization and execution evidence; this patch does not fabricate usage or enable model spending.

## Sources and rollback

- [Control snapshot and dependency status](https://github.com/liboyang42-cpu/hengyin/blob/53d50db24b83ec856abb7d998d913c79699934dc/docs/plans/mini-codex-cloud-20261015/BACKEND_CHANGES.md)
- [Current rolling checkpoint](https://github.com/liboyang42-cpu/hengyin/blob/53d50db24b83ec856abb7d998d913c79699934dc/docs/plans/mini-codex-cloud-20261015/LONGRUN_CURRENT.md)
- [Frozen response producer](https://github.com/liboyang42-cpu/hengyin/blob/1e403b135206844a34219753a36e2dee39c7dd59/chengyinhub-system/src/main/java/com/chengyinhub/business/service/impl/NpcChatService.java#L443-L545)
- [Current response producer](https://github.com/liboyang42-cpu/hengyin/blob/adc7c68e9398a61476bbfd57cab7696094d2b61d/chengyinhub-system/src/main/java/com/chengyinhub/business/service/impl/NpcChatService.java#L438-L581), blob `8ca70e50b925fe1b64f59cc82e53e6565c534ffc`
- [Current merchant controller](https://github.com/liboyang42-cpu/hengyin/blob/adc7c68e9398a61476bbfd57cab7696094d2b61d/chengyinhub-admin/src/main/java/com/chengyinhub/web/controller/api/ApiAiNpcController.java#L390-L402), blob `534f13858932da31d41faf99c0ae62a42cc744f7`
- [Actual response field names](https://github.com/liboyang42-cpu/hengyin/blob/adc7c68e9398a61476bbfd57cab7696094d2b61d/chengyinhub-system/src/main/java/com/chengyinhub/business/domain/vo/ai/NpcChatResp.java), blob `0a16d658d0d9da21a042bada5d5e805f63d76039`
- [Published native parent](https://github.com/liboyang42-cpu/chengyin-ios/tree/8e3c74a196017550bd2ca2814cd23970c16dba0f)

Rollback is limited to the two Core files, two existing regression files, this dedicated document and its current-status rows. Apply only this slice's bounded patch against the exact parent; do not replace cumulative native files or unrelated unsubmitted work. No persisted format, API request field, policy, capability or backend change needs reversal.
