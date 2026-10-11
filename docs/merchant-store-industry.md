# Brand-center industry selection

## Standalone baseline and source

Actual upstream and exact preimage: `41571fed5c27d4766d0bebb02e2800d798f1edbd`.
No unsubmitted dependency on template batches 6–9. This is the shop's industry classification, separate from template gameplay categories. Integrate the incremental patch into newer combined trees; do not overwrite their Core/Editor files with these standalone-415 after-images.

MASTER v10 W05, lines 399–427, assigns shop facts and human confirmation to merchants; the merchant responsibility domain is also stated in lines 225–226. The concrete existing workflow is Mini brand-center industry editing, not a newly invented W05 requirement.

Source is pinned to backend/Mini `f1fe895f34c3664783aafd6145cf93e0de15878d`:

- `chengyinhub-xcx/pages/merchant/decor/index.js:825–845`, SHA `36f0d912f63369d8d110b56757387c66ae81d307`: loads POST `/api/category/list` with `type:1,parentid:0`; `toggleCategory` marks only the chosen index; `saveCategories` sends the single category ID to `saveDecor`.
- `ApiCategoryController.categoryList`, SHA `3b3582e02904912d4fd64d58afe401c151706c6b`: active, non-deleted, type-filtered root categories; returns an array. Type1 industry is distinct from type4 gameplay.
- `ApiMerchantController`, SHA `ac739a411d2de90de83bebecf482508e1d363a2a`: `publicCategories(Integer categoryId)` confirms the native integer range; `coopProfile:547–557` obtains the server-authorized merchant and returns category labels; `saveDecor:666–724` requires PROFILE_WRITE, selects the server-authorized shop, whitelists non-null `categoryId` and uses `updateAuthorizedProfile`.

Persistence evidence: `MmsMerchantServiceImpl.updateAuthorizedProfile/authorizedProfilePatch:268–360` (SHA `6ca6adb7723fcdeb8ed9fe8ef7e7b26dbfb072b5`) rechecks the locked active principal/merchant/operator role, retains categoryId in its explicit patch whitelist and invokes the mapper. `MmsMerchantMapper.xml:259–267` (SHA `5c130b6ef26ac3e31f19d550e3632274e8e4f2cd`) writes non-null categoryId to category_id; result mapping17 reads it back.

The existing coop-profile read requires COOP_MANAGE on the server; the existing native decor write gate requires PROFILE_WRITE. This change creates no grant and bypasses neither check. Existing role/scope behavior is not repaired here.

## User flow and boundaries

1. Open the existing shop-decoration screen and choose store industry. The current saved numeric ID remains visible. Catalog load, failed read with retry, genuine empty catalog and stale picker are distinct.
2. Choose exactly one available industry. There is no auto-selection when none was saved. The currently saved ID can be absent from today's catalog; loading keeps it intact and explains that selecting another industry would replace it.
3. Cancel discards the sheet buffer. Reload retains the selected ID, but Apply is disabled if it is no longer available. Account/scope changes, another document edit, review, dismissal or backgrounding invalidate the picker; late replies cannot restore or apply it.
4. Apply changes only `MerchantStoreDecor.categoryID` in the current draft. The existing document edit owner remains responsible for image/draft invalidation. The picker itself never saves.
5. Frozen review shows old/new numeric IDs and warns that classification is public and does not grant qualifications or approval. Catalog labels are used to choose; they are not copied into save payloads as authoritative facts.
6. Existing approved decor saving remains required. This new industry-changing flow rereads the source after acknowledgement. Only the returned category becomes the saved baseline. If readback fails, fields are cleared and the existing reload action can recover; the acknowledged write cannot be replayed.

Backend null does not clear categoryId, so no clear action or invented clear flag is offered. Valid selectable IDs are positive and fit Java Integer. Only that positive industry selection is newly counted as nonempty decor, so an otherwise-empty shop can review its new industry. Nil/zero does not bypass empty validation. This necessary validation path was added to START before editing, retaining the initial START copy.

The existing generic decor save request remains a full whitelisted decor request. Industry selection changes only the category field; other existing values or separately reviewed pending decor edits remain in that request. It does not narrow or replace existing save semantics with Mini's single-field patch. Names, category type, `categoryIds`, `activityCategoryids`, and local choice flags are never introduced into the payload. Server authorization and the existing approval/journal/freshness gates still decide writes.

The picker buffer lasts only for the current editing session; no durable local save is claimed. No provider call, media upload, payment, reward, backend modification or real production save was performed.

## Verification and integration

- PASS: 34 focused source checks (12 new plus 22 related decor/tag/featured/hours checks), pinned Tree-sitter parsing of 9 Swift files, whitespace/patch applicability, exact baseline before-images and previous nine archive hashes.
- Authored NOT RUN: 19 Core XCTest methods and 3 simulator UI flows. Core covers strict type1 catalog/Integer range, one-choice/no-op/buffer/cancel, missing saved ID, empty/error/retry, stale draft/account/out-of-order response, industry-only validation, existing request preservation, exact catalog permission, approved source readback, failed-readback reload with no replay, and production-write gate. UI covers cancel/no-op, before/after review, keep/discard, save/readback and selection reload.
- NOT RUN: Swift type checking, Core XCTest, Xcode build, simulator/screenshot/VoiceOver/Dynamic Type, real backend/provider/payment/reward acceptance. The required dot environment has no `swift` or `xcodebuild`; parse/source checks are not native execution. No alternate environment used.

Register `Core/MerchantStoreIndustrySelection.swift`, `App/MerchantStoreIndustryPicker.swift`, new Core/UI test files, and merge 22 English/Simplified Chinese entries from `Resources/MerchantStoreIndustryLocalizations.fragment.json`. Evidence includes `integration-fragment.json` with exact paths/methods. No central PBX/catalog/CI files are edited. Nine sealed batches and known historical scope/moderation work remain unchanged.
