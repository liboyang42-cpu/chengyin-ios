# CY-HANDOFF: IOS — I08 player Shop NPC non-retryable unknown outcome

2026-10-15 UTC. **SOURCE_CANDIDATE / EXECUTION_NOT_RUN / NOT_PUSHED**. This is the complete existing player Shop NPC response/review/recovery slice. It does not close the whole I08 card or establish deployed AI availability.

## Identity, ownership and refreshed dependency

- Continuing repository/branch: `liboyang42-cpu/chengyin-ios:migration/native-ios`.
- Exact published parent: `1ddbb7928a042947b2955a9302d251ccd08309b8`; tree `445d303df4da2ab7a136f0c1ed39ef9468e3357c`. All **5,082 files** in the isolated starting snapshot matched the cumulative public baseline's Git blob identities, with no missing or extra files. The previously published merchant NPC work is retained unchanged.
- Protocol: `CY-COORD-20261015-v1`. Read the native current-status index, README, existing Shop NPC module/entry/contracts/coordinator/transport/recovery and regression sources. Refreshed the public control head and read `IOS_START_PROMPT.md`, `IOS_HANDOFF.md`, `BACKEND_CHANGES.md`, `COORDINATION.md`, ownership, relevant task records and `LONGRUN_CURRENT.md` at **`53d50db24b83ec856abb7d998d913c79699934dc`**.
- Task/dependency: **I08 / A02 / BK-AI, CONTRACT_FROZEN, NO_API_CHANGE**. The exact response tuple exists in frozen backend **`1e403b135206844a34219753a36e2dee39c7dd59`**, and was read again from rolling source **`adc7c68e9398a61476bbfd57cab7696094d2b61d`** / PR44. The rolling candidate is **SOURCE_DELIVERED_UNVERIFIED / NOT_RUN**; **TEST_DEPLOYED=NO**. Historical frozen backend test results do not cover this native patch or prove a deployed target.
- The control summary calls the marker `reasonCode`; actual `NpcChatResp` getters and the producer use **`errorCode`**. Only that existing serialized field is consumed. No new endpoint, request field, usage/cost assertion, response policy, cancellation or outcome-reconciliation API is introduced.
- Current source already routes `/api/ai/npc/shop-chat` through `chatWithShop` and the same response producer; `/api/ai/npc/voice-chat` uses the same stored-request/Shop response contract. The native transport already uses these endpoints. Voice retention here is compatibility of an existing dormant path, not new ASR/TTS, playback, quota or paid capability authorization. AI-VOICE and CLAIM-MATERIAL remain DRAFT; all capability gates stay OFF.
- No applicable `AGENTS.md` or `.agents/skills/*/SKILL.md` was present in the native snapshot or its applicable ancestors. The user explicitly deferred tests, builds, app execution and CI. No backend file, shared control log, production configuration, credential, deployment or payment is changed.

## Source-confirmed defect and sanitized reproduction

Existing entry: authoritative Play node -> `ShopNPCNodeEntrance` -> owned `ShopNPCView` -> explicit text/voice/regeneration review -> `ShopNPCCoordinator` -> `ShopNPCHTTPClient` -> existing Shop endpoint -> service notice / review / conversation.

Synthetic response for the exact submitted UUID:

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

The English notice and all identities/audio bytes in the new regressions are synthetic. No real account, model, audio upload, provider or network endpoint was exercised.

Baseline actual behavior:

1. `ShopNPCReply.decode` accepted only PASS/BLOCKED/NOT_RUN and rejected this frozen UNKNOWN tuple as malformed.
2. The coordinator retained the original review after that decoding error, but the malformed-response recovery still allowed confirmation/retry.
3. Merely accepting UNKNOWN would not fix it: `needsRetry` independently treated all PROCESSING responses as retryable, even when the server said false.
4. Treating it as an ordinary non-success terminal response would also be wrong: the existing terminal presentation says the request ended and invites a new question. The transport-unknown label separately invites same-ID retry. Neither label represents this non-retryable pending service result.

Expected: preserve the exact original review UUID and its complete normalized text, voice bytes/duration or regeneration target; show only a service notice, keep the composer/reuse/regeneration locked, and do not retry, replace the ID, append a conversation turn, replace a verified answer or promote audio/ASR to success. Only an explicit existing local cancel/discard may release this screen's review; that is not server resolution.

## Implementation: one existing native flow

- `Core/ShopNPCContracts.swift`: decodes existing `errorCode` and retains the safety decision. UNKNOWN is accepted only for PROCESSING / REQUEST_OUTCOME_UNKNOWN / retryable=false. The UUID, required status/safety/retry fields, bounded safe text/ASR and optional delay checks remain. Other UNKNOWN combinations remain malformed. `needsRetry` now requires explicit `retryable=true`.
- `Core/ShopNPCCoordinator.swift`: adds a distinct `pendingIsNonRetryableProcessing` projection and `.replyUnresolved` presentation reason. It retains the original review for every non-retryable PROCESSING result, including an already-supported NOT_RUN safety value. It never marks the result terminal and never enters success/transcript replacement. `canConfirmPending`, synchronous intent preparation, and captured-intent dispatch all deny retry. A supplied delay cannot turn denial into later permission.
- `App/ShopNPCView.swift`: reuses the current review panel. Non-retryable PROCESSING hides the retry action, countdown and terminal/new-question guidance. It shows the existing safe notice and existing local-only abandonment warning. The failure key reuses the existing neutral unavailable text rather than the transport-unknown text that tells users to retry. No localization file or new screen is added.
- The original normalized text stays in both the pending review and the untouched SwiftUI draft. Unknown voice results keep the exact clip, not an invented transcript; the existing view can review its byte count/duration. The protocol still never supplies playable audio to this native path. Existing verified messages survive an unknown regeneration response.
- Existing `cancelReview` remains an explicit local action. The warning states that it does not cancel server processing or delete records, keeps a typed draft, and that a later send creates a new request that may incur another charge. Cancelling alone makes no request. Voice discard still discards the local clip. This patch does not add an extra confirmation dialog or reuse the merchant coordinator's different confirmation-token machinery.
- The transport-only missing-response path remains `.unknownOutcome` with the existing explicit same-ID retry. The new server-response lock is separate from that path. Malformed/mismatched responses do not establish the new trusted service state.
- Existing suspend/resume authority checks preserve the denial without sending; close, scope/grant invalidation and account retirement still clear private in-memory conversation state. Late replies remain fenced by epoch and scope. This slice does not add durable cross-process request recovery or claim that reopening proves cancellation, deletion, refund or completion.

## Owned paths and authored acceptance

Only these seven native paths change:

1. `Core/ShopNPCContracts.swift`
2. `Core/ShopNPCCoordinator.swift`
3. `App/ShopNPCView.swift`
4. `Tests/CoreTests/ShopNPCModernOutcomeTests.swift`
5. `Tests/AppUnitTests/ShopNPCModernOutcomeTests.swift`
6. `docs/ios-current-status.md`
7. `docs/ios-i08-shop-npc-unknown-outcome.md`

**12 Core methods authored, NOT_RUN:** exact frozen tuple; omitted/mutated tuple rejection; complete multiline/multibyte text and request ID retention; all review/send entry points locked; retryable=false with known processing safety and delay; retryable-processing -> unresolved transition; transport-only same-request recovery; exact voice clip retained with no ASR/audio success; regeneration/history/reuse preservation and explicit local cancel; absent/blank safe notice; mismatched response UUID; suspend/resume/authority loss; cancellation-resistant old reply after a new scoped conversation. Several related assertions share one method; this list is coverage, not a count of individually executed scenarios.

**5 AppUnit methods authored, NOT_RUN:** English/Chinese and large-type view construction with unresolved review projections; consumed button-intent rejection; local cancellation without dispatch; suspend/resume/retirement; session-owner account invalidation. These are authored model/hosting tests, not rendered UI inspection, accessibility or device evidence. Existing test files are already wired; no project generation or test-target change is needed.

Performed: source and manual flow inspection, public-source identity lookup, cumulative baseline blob comparison, bounded diff inspection, file/patch hashing. **NOT_RUN:** Swift/Core XCTest, AppUnit, XCUITest, typecheck, lint, Xcode/build, app/simulator/device execution, accessibility, Python/Node/Java test suites, CI lookup/dispatch, live accounts/provider/audio/networking, backend integration or independent business readback. No push, merge, deployment, signing or app release was performed by this implementation worker.

## Dependencies and remaining boundaries

- Backend source ownership remains A02/C00. The current approved deployment, runtime package/database identity, real account access and provider availability are still unverified; native production gates remain OFF.
- Existing NPC export remains read-only. L03's frozen deletion barrier/text erasure preserves original unique request/tombstone and charged facts; it is not an all-data erasure promise and native deletion is not implemented here. Unknown usage must not become a real zero cost, and no usage UI or new accounting model is added.
- The prior merchant NPC slice is already published in the parent commit. This separate Shop NPC slice does not reopen it or imply that remaining I08 data-rights/usage/product acceptance is complete.
- Source review and any later publication are separate from execution acceptance. Later authorized validation must exercise the retained and new cases on the exact published SHA, plus real entry/close/background/reopen/VoiceOver behavior and approved backend identities.

## Sources and rollback

- [Native published baseline](https://github.com/liboyang42-cpu/chengyin-ios/tree/1ddbb7928a042947b2955a9302d251ccd08309b8)
- [Refreshed backend control](https://github.com/liboyang42-cpu/hengyin/blob/53d50db24b83ec856abb7d998d913c79699934dc/docs/plans/mini-codex-cloud-20261015/BACKEND_CHANGES.md)
- [Current rolling source/deployment limits](https://github.com/liboyang42-cpu/hengyin/blob/53d50db24b83ec856abb7d998d913c79699934dc/docs/plans/mini-codex-cloud-20261015/LONGRUN_CURRENT.md)
- [Frozen UNKNOWN producer](https://github.com/liboyang42-cpu/hengyin/blob/1e403b135206844a34219753a36e2dee39c7dd59/chengyinhub-system/src/main/java/com/chengyinhub/business/service/impl/NpcChatService.java#L443-L545), blob `5e44497c97aed8fd063fc2fafc851910d0c30f3c`
- [Rolling Shop/UNKNOWN producer](https://github.com/liboyang42-cpu/hengyin/blob/adc7c68e9398a61476bbfd57cab7696094d2b61d/chengyinhub-system/src/main/java/com/chengyinhub/business/service/impl/NpcChatService.java), blob `8ca70e50b925fe1b64f59cc82e53e6565c534ffc`
- [Shop and existing voice controller](https://github.com/liboyang42-cpu/hengyin/blob/adc7c68e9398a61476bbfd57cab7696094d2b61d/chengyinhub-admin/src/main/java/com/chengyinhub/web/controller/api/ApiAiNpcController.java#L205-L350), blob `534f13858932da31d41faf99c0ae62a42cc744f7`
- [Actual response fields](https://github.com/liboyang42-cpu/hengyin/blob/adc7c68e9398a61476bbfd57cab7696094d2b61d/chengyinhub-system/src/main/java/com/chengyinhub/business/domain/vo/ai/NpcChatResp.java), blob `0a16d658d0d9da21a042bada5d5e805f63d76039`

Rollback only this seven-path bounded patch against the exact parent, preserving the merchant change and all prior cumulative work. No stored schema, endpoint, backend policy or capability flag requires reversal. Do not replace whole cumulative files from an older snapshot.
