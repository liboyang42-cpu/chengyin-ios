# Merchant station pause without a fallback

## Requirement and verified gap

The supplied consolidated construction document maps P086 / PA10 to the merchant game-node interface and its `onFallbackChange` / `submitPause` interactions. Its W03 and merchant operations requirements preserve current station ownership, action/revision checks and independent financial handling. The specified local document file was inspected directly; its cover says edition 8 despite being referred to as v9 in the handoff. The artifact receipt records its exact hash rather than treating a version label as evidence.

At the pinned current mini/backend source, a merchant may pause an active station without an approved alternate station. The original native form defaulted to fallback index zero and required a plan code/version. It could not prepare a pause when the approved fallback list was empty, and a reordered list could silently select a different plan.

## Implemented behavior

- The form now begins with a visible **No alternate station** choice. Selecting it omits both fallback keys. It never submits null, an invented target node, or an old selected plan.
- Choosing an approved plan retains its source/target identity, code, version, name and player message together. Reordering does not change the selected plan. Removal, replacement, duplicate ambiguity or changed displayed consequences require a fresh explicit selection; none is not used as an automatic fallback.
- Reason code and the existing valid civil resumption time remain mandatory. Reason text is optional as in the source builder; if present it is nonblank and limited to the source's 200 UTF-16-unit cap. A selected plan requires both valid code and positive version, matched to this station's current approved projection. Partial/null/blank/malformed plan fields remain invalid.
- No-plan pause still requires the current merchant perspective, activity, node, session status, available action and expected revision. It cannot authorize another station or bypass ACTIVE/RUNNING requirements.
- Both the form and existing frozen review explain that players see the pause, reason and expected resumption time, are not redirected elsewhere, and use the existing platform-support process for any refund request.

The request endpoint, command identity, frozen review, fresh baseline re-read, journal, unknown-result lock, same-request retry and default production write gates are unchanged. Existing valid requests containing a fallback keep the same fields and versions. No live pause, reroute, refund, payment, reward, provider or backend action was performed or enabled.

## Source

Private source ref: `liboyang42-cpu/chengyin@ce61c0bbace743ff835cb297ef41c89b52181636`.

- `chengyinhub-xcx/pages/merchant/game-node/index.js`, `defaultPauseDraft` and `submitPause`: starts without a plan and discloses no-plan consequences before submission.
- `chengyinhub-xcx/pages/merchant/game-node/index.wxml`, pause sheet: the alternate plan is optional, with a distinct explanation for no available plan and no selection.
- `chengyinhub-xcx/pages/merchant/utils/game-session-merchant.js`, lines 446–468, blob `259d8347c9893514692114c79db1638448d765f3`: omit both plan fields when none; require the approved matching pair when either is supplied; omit blank reason.
- `chengyinhub-system/src/main/java/com/chengyinhub/business/service/impl/GameSessionRuntimeServiceImpl.java`, lines 638–660, blob `3d8ac26f10eb50ba9c48682d9b4cc7873c7a4862`: no plan resolves to null; a supplied plan still uses the existing approved-plan resolver. Pausing without a plan does not invent an alternate station or modify orders.

No private-source files are included in the native patch. Backend/U2 is not edited.

## Integration and verification boundary

Base tree is `73e081ad4a1f3524f803ba6d9dac8806b745e880`. Existing product edits are limited to `Core/MerchantStationContracts.swift`, `App/MerchantContentEditor.swift`, and the existing review section in `App/MerchantContentViews.swift`; the selection value is an independent small Core type, not a new service/framework.

Merge the four unique entries from `Resources/MerchantStationPauseLocalizations.fragment.json` and regenerate the shared project in root integration. Shared catalog, project, AppSession, CI/timing and all Muse-reserved paths are unchanged. There are no new UI methods or timing estimates.

Thirteen Core XCTest cases are authored, covering no candidates, default none despite candidates, old-plan preservation, reorder, explicit clearing, stale/foreign/ambiguous options, partial/null fields, permission/state/revision gates, civil time, forbidden payload keys and review-warning scope. Focused source checks and supplementary Tree-sitter parsing are run; Swift/Core/AppUnit/UI, full aggregate, production service and device acceptance are not run in this Linux task. These checks do not establish that a real station has paused.
