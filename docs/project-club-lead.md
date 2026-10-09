# Existing professional editor: club-led participation

This source-backed increment fills the existing professional editor's “Invite clubs to lead” control. It does not create another publisher, send invitations, contact clubs, publish a topic, or enable a production capability.

## Source and repaired gap

Reference repository: `liboyang42-cpu/chengyin`, exact commit `ce61c0bbace743ff835cb297ef41c89b52181636`.

- `chengyinhub-xcx/pages/publish/fabu/step3.wxml`: the club-led section is exposed only for `productType === 1 && !clubId`; a switch edits `formData.openClubPool`.
- `chengyinhub-xcx/pages/publish/fabu/index.js`: new professional drafts default on; edit readback restores `Number(topic.openClubPool) === 1`; `onClubPoolChange` records the selection; submit emits 1 only for an enabled city topic without a club, otherwise 0.
- `chengyinhub-system/src/main/java/com/chengyinhub/business/domain/dto/TopicCreateDTO.java`: `Integer openClubPool`.
- `chengyinhub-system/src/main/java/com/chengyinhub/business/service/impl/CmsTopicServiceImpl.java`: `resolveOpenClubPool`, `assertClubLeadOnlyForCityOrienteering`, and update mapping enforce the same product/club distinction. New omitted settings default on; existing explicit off is retained. Club membership/authorization is not granted by this setting.

The older Flutter-derived native mapping hardcoded 0 for all FULL payloads and did not retain authoritative readback. That could silently close an enabled existing topic. This increment supersedes only the older `openClubPool=0` claim in `docs/project-edit-module.md`. The master document's original-professional-publisher reuse requirement remains the governing scope.

## Native behavior and preservation

- The control is mounted once in the existing `ProjectEditView`; prepared review uses its frozen draft and appears only when the actual prepared payload contains `openClubPool`.
- Genuinely new drafts use ce61's default 1. Authoritative readback replaces that default exactly, including absent/null/zero/unknown values. Decoding an older local envelope does not insert the new default.
- Legacy absent/null local values display off and remain unchanged on a no-op. A deliberate eligible toggle edits only `preserved.openClubPool`.
- Only numeric 0/1 and missing/null values are supported. Strings, booleans, other numbers, arrays, and objects stay read-only and block FULL submission before eligibility normalization. No raw source value is guessed or erased.
- Known settings submit 1 only for city topics without an owning club. Ineligible topics submit 0 with an explicit explanatory notice; the local stored preference remains intact.
- WHITELIST returns before the field is emitted or full-only validation runs. Existing locked-field comparisons detect mutation of the preserved setting.
- Captured toggle callbacks require the exact controller, generation, editor lease, owner/session, draft identity, base revision, mutation revision and draft bytes. Same-byte replacement, ABA, mode/club changes, restore/discard, logout/reauth, newer visit and disappearance retire stale callbacks.
- Existing review invalidation, autosave, explicit local save and cold restore own persistence. A toggle makes no durable-save claim. Unconfirmed chapter removal and unknown submission locks remain effective.

## Verification boundaries

Seven pure-domain and ten app-hosted Swift test methods are authored for source defaults, preserved values, eligibility, whitelist, immutable review, lifecycle races, cold restore, local save failure, and uncertain outcomes. Python static checks verify wiring, gates, localizations and absence of dispatch. Static parsing and Python tests are not Swift compilation or runtime evidence.

Apple compilation, Swift/XCTest execution, simulator/device flows and live backend behavior are NOT_RUN in this cloud environment. The root integration owns generated project/catalog refresh and the exact existing ProjectEditView history-inverse guard update. No guard is weakened here.
