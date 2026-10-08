# Merchant NPC preset avatars and profile contract parity

## Delivered client increment

The existing Merchant workbench → Store character editor now offers “Choose a preset”. It renders the twelve exact bundled mini-program avatars, keeps the existing image/unknown code untouched on open or cancel, and changes only `avatar` after explicit confirmation. New empty profiles receive no invented avatar, name, greeting, personality or knowledge. Choosing a preset does not save: the character still goes through the existing immutable review, approved endpoint transport and uncertainty journal. This is a complete client-side choice-to-review integration; live submission is not claimed tested or enabled.

The frozen review shows the chosen preset artwork/name and exact stored avatar value. Photo URLs and unknown codes retain their original value without a substituted preset. Editing or switching accounts after review cannot use the captured preview as submission authority.

The original photo route remains available. This change neither uploads an image nor invokes an AI provider. The existing operations reader, merchant access checks, live-write approval and durable unknown-write lock are unchanged.

`MerchantStoreCharacter` now respects the same name/personality bounds as the actual mini-program and backend: name 32 UTF-16 units; personality 500, with explicit empty-string clearing allowed. Greeting remains the mini-program's 60-unit input bound, stricter than the backend's 255; knowledge remains 2,000. Name and avatar remain required. All five strings are trimmed when encoded. `persona: null` means no change on the backend, so an intentional clear is encoded as `"persona":""`; `knowledge` has the same empty-versus-null distinction. The client does not invent content when legacy read fields are absent/null.

Read-only `auditReason` is retained and displayed only when the loaded `auditStatus` is 2 and the reason is nonempty. Status is labeled “Last loaded review”, never inferred from a save or avatar selection. Audit fields, merchant ID, enabled status and provider flags never enter the five-field `npc/save` payload.

## Verified source evidence

All references below are from `liboyang42-cpu/chengyin` at exact commit `ce61c0bbace743ff835cb297ef41c89b52181636`, read via the GitHub connector. No missing historical Flutter checkout was treated as read.

- [Mini-program character editor](https://github.com/liboyang42-cpu/chengyin/blob/ce61c0bbace743ff835cb297ef41c89b52181636/chengyinhub-xcx/pages/merchant/decor/ai-npc/index.js), blob `d0088bf4d71158bc2b5cc19e7b4e1db32c4fc0b3`: `openPresets`, `confirmPreset`, `saveField`, `save`, `persistProfile`, field limits and five-field JSON payload.
- [Mini-program layout](https://github.com/liboyang42-cpu/chengyin/blob/ce61c0bbace743ff835cb297ef41c89b52181636/chengyinhub-xcx/pages/merchant/decor/ai-npc/index.wxml), blob `c390dc72f237add08f5ab66333b36a63d290745b`: avatar preview, preset picker and explicit “Use this avatar” action; last rejection reason.
- [Exact artwork data](https://github.com/liboyang42-cpu/chengyin/blob/ce61c0bbace743ff835cb297ef41c89b52181636/chengyinhub-xcx/utils/pixel-avatar-data.js), blob `87ee78031820e4e370635e004fc10501a4e7c9a8`: all 12 IDs, grid sizes, backgrounds, palettes and base-62 run strings. No new artwork was generated. Canonical native data fingerprint: SHA-256 `0f121d1296400c18b6f73c2a3a470182b589e64b53ee6b1376f9f2d8c49215d2`.
- [Mini-program renderer](https://github.com/liboyang42-cpu/chengyin/blob/ce61c0bbace743ff835cb297ef41c89b52181636/chengyinhub-xcx/utils/pixel-avatar.js), blob `c45b4033abbf91ead55272836363a301908b873e`: `px1:` encoding, exact run decoding, integer pixel scale. Native editing intentionally does not silently turn an unknown code into the first avatar.
- [Merchant controller](https://github.com/liboyang42-cpu/chengyin/blob/ce61c0bbace743ff835cb297ef41c89b52181636/chengyinhub-admin/src/main/java/com/chengyinhub/web/controller/api/ApiMerchantController.java), blob `ac739a411d2de90de83bebecf482508e1d363a2a`: authenticated `PROFILE_WRITE`, `/npc/profile`, `/npc/save`, 32/500/2000 limits, empty/null semantics, server-owned identity, audit state and no media submission for presets.
- [Backend avatar allowlist](https://github.com/liboyang42-cpu/chengyin/blob/ce61c0bbace743ff835cb297ef41c89b52181636/chengyinhub-system/src/main/java/com/chengyinhub/business/support/NpcAvatar.java), blob `977973309966f1b6d6c8fadde17644e032326f20`: exact 12 `px1` IDs accepted by the save endpoint.

The separate `MerchantNpcKnowledgeDraftService` at blob `588033fedd42ca6f0f5a02ab33ad86ffac84e932` explicitly has no HTTP endpoint or approved-source adapter. Six-category knowledge publishing, expiry, theme isolation and approval are not implemented by this increment. W04/W05 and AI23–25 remain broader open work.

## Ownership and lifecycle

- Picker opening captures the loaded reader scope, draft identity and exact character snapshot.
- Selecting a tile only updates picker state. Apply is disabled until a different supported avatar is explicitly selected.
- Apply checks current authentication/scope, unchanged draft and draft identity, no in-flight operation, no frozen confirmation and no unknown-write lock.
- Apply uses `MerchantOperationsViewModel.edit`, preserving media-owner invalidation and the existing document revision path. It is consumed after one use.
- Closing, backgrounding, discarding, reloading or replacing the account prevents an old picker from modifying the new document.
- No remembered selection crosses a new picker presentation. An existing known code is preselected; an empty, photo or unknown value has no default selection.
- Source review evidence is display-only. Choice and offline example save cannot manufacture review approval, publication, voice readiness or a working production NPC.

## Verification and integration

Executed in the dot Linux workspace:

- 14 focused Python source/data contract tests: passed. This includes exact full artwork fingerprint, all run bounds, integration/authority/lifecycle structure and bilingual key coverage.
- 10 existing merchant-operations structure tests: passed. Their optional historical Flutter-source comparison was not executed because that checkout is absent. The relevant mini/backend source checks above were separately verified against exact blobs.
- Six owned Swift files passed the repository’s pinned Tree-sitter 0.26.0 / tree-sitter-swift 0.7.3 syntax preflight with zero recovery nodes. This is supplementary parsing, not compilation or typechecking.
- Source blob hashes, owned-path scope, fragment JSON and `git diff --check`: passed.
- The supplied artwork montage is a deterministic data rendering for pixel inspection, not a screenshot of the iOS app.

Authored but NOT RUN in this environment: 11 Core XCTest methods and 15 AppUnit XCTest methods. Tests cover all presets, UTF-16 boundaries including emoji, five-field payload/explicit clearing, rejection reason, cancel/confirm, null profile, photo and unknown-code preservation, reload/account/edit invalidation, separate review/save and unknown-write locking. Swift, Xcode, Apple simulator/device and live backend/provider verification are unavailable here. No real save or provider call was made.

Integration owner should merge `Resources/MerchantNPCPresetLocalizations.fragment.json` into the main catalog and regenerate the Xcode project through the repository's supported generator. This packet deliberately does not edit the main catalog, PBX, AppSession, CompositionRoot or CI.

Commands after integration:

- `python3 -m unittest discover -s Tests/ContractChecks -p test_merchant_npc_preset_avatar.py -v`
- `swift test --filter MerchantNPCPresetAvatarTests`
- On the Apple executor, run `MerchantNPCPresetPickerTests` in `QuestifyAppUnitTests` after project generation.

Deferred shared E2E acceptance: open Store character, preserve existing photo on cancel; choose a preset and inspect the frozen review before saving; cancel and reopen; save/reload in the synthetic fixture; reject and unknown write outcomes; background/reopen and sign out; switch English/Chinese; small screen, large Dynamic Type, VoiceOver selection and visual comparison of all 12 artworks. Production save remains gated by the existing independent approvals.
