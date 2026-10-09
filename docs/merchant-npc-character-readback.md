# Merchant NPC character save readback

## Source-backed gap

The ordinary merchant character editor previously installed the submitted character as its saved baseline after `npc/save` acknowledged the write. That copy retained the last loaded audit status and rejection reason. An edit to an approved or rejected character could therefore keep showing the obsolete result until the screen was reloaded.

The frozen source is `liboyang42-cpu/chengyin` at `ce61c0bbace743ff835cb297ef41c89b52181636`:

- `chengyinhub-xcx/pages/merchant/decor/ai-npc/index.js`, blob `d0088bf4d71158bc2b5cc19e7b4e1db32c4fc0b3`: `persistProfile` resets its displayed review to pending and clears the old rejection after a save.
- `chengyinhub-admin/src/main/java/com/chengyinhub/web/controller/api/ApiMerchantController.java`, blob `ac739a411d2de90de83bebecf482508e1d363a2a`: `/npc/profile` requires `PROFILE_WRITE`, derives the merchant from the authenticated access context, and returns its own pending/disabled editor profile. `/npc/save` returns an acknowledgment, without an authoritative profile/review receipt.
- `chengyinhub-system/src/main/resources/mapper/business/NpcProfileMapper.xml`, blob `5083449a94de07f67eb80ebe0d5a0b18c937e6cf`: `updateMerchantSelfNpc` resets `audit_status = 0` and constrains the update by ID, merchant scope ID, and `scope_type = 2`. It does not erase historical `audit_reason`; the native presentation already shows rejection reasons only when the returned status is rejected.

This is a narrow P080 authoring/readback correction supporting AI23/AI25/AI48 regression boundaries. It does not complete six-category knowledge governance, AI generation, live model evaluation, or production publication.

## Behavior

Only the `.character` success branch in `MerchantOperationsCoordinator.confirm` changes:

1. After the existing writer acknowledges the save, clear the old document, baseline, and editable character before awaiting another read.
2. Reuse `MerchantOperationsSessionReader.document(.character)`. That reader refreshes access, calls the owner-only `/api/merchant/npc/profile` endpoint, and fences the response against its captured session and scope. No public NPC projection, private business assistant, or model request is involved.
3. Install only an authoritative character response as the new baseline, preserving server-normalized fields and the returned review result. Do not locally invent pending, approved, enabled, or published status.
4. If the read fails or returns an unexpected document type, leave character fields cleared and say the save was acknowledged but its latest profile could not be loaded. The existing Refresh action only reads again. It does not resubmit the acknowledged payload.
5. If account, owner-access revision, authentication, screen generation, or task validity changes during readback, discard the late response.

Unknown writes never enter this success branch. Their existing durable journal and replay lock are unchanged. An unknown write is distinct from a successful write followed by an unsuccessful read. A null authoritative profile stays empty rather than restoring the submitted content.

## Verification and integration

- Fifteen focused Swift tests are authored for canonical readback, pending/approved/unknown review values, historical rejection removal, null/wrong-type responses, in-flight clearing, repeated confirmation, reload-only recovery, sign-out/account/screen interruption, revoked access, real adapter request ordering, and durable unknown-write locking.
- Eight native-local Python source contracts and one optional pinned-ce61 source parity check are provided. Supply `CHENGYIN_CE61_SOURCE_ROOT` to run the source comparison; absent source is explicitly skipped, never counted as source parity passing.
- Merge the two strings from `Resources/MerchantNPCCharacterReadbackLocalizations.fragment.json` into the main string catalog during integration. This patch deliberately does not edit shared catalog/project composition.
- Swift compilation, Swift test execution, Xcode builds, simulator/device UI, accessibility, and real backend/model acceptance are NOT RUN in the dot Linux environment. Offline source contracts do not substitute for those gates.

No production capability, endpoint approval, provider credential, publish switch, repository push, or deployment changes.
