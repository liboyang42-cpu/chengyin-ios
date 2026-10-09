# P081 explicit capacity clear

Deleting a previously loaded nonblank capacity now produces capacity:null together with params.clearCapacity:true on the existing cooperation save preview. A missing/null/already-empty source does not produce a clear request, even after a user types and removes a temporary number. Explicit zero remains a numeric zero. Restoring the original value removes the clear intent. The form and frozen confirmation both explain the local clear and its saved effect.

The DTO keeps the loaded capacity only as local edit bookkeeping. Equality still compares all six existing form/hidden fields, so the same server facts do not conflict merely because a prior local instance carries edit bookkeeping. Each edit still cancels the old immutable confirmation; freshness and request previews continue through the existing coordinator/service. The emitted params object contains only the source-supported clearCapacity Boolean. Existing fields and hidden suitActivityTypes/coopOpen values retain their previous serialization. No unknown response fields are forwarded or broadened into write authority.

Only the definite cooperation success branch consumes the local capacity intent and establishes the new baseline. Explicitly cleared text becomes the server's blank/nil form representation. Failure and unknown outcome do not acknowledge the clear; unknown replay locks remain intact. Canceling confirmation keeps the local draft, while the existing discard/reload behavior restores/replaces it. Newer source facts or scope cannot use an old confirmation. No extra read or save is introduced.

## Evidence

Plan: Questify城瘾全面改革施工计划.docx P081 paragraphs 1795–1798 and PA10. Exact document SHA-256 eb23c8aefc22954bcd6f73ef800c32b763e7f8c4e3d4c68b0a0956756fd50133.

Reference repository liboyang42-cpu/chengyin at ce61c0bbace743ff835cb297ef41c89b52181636. Native changes are original code; no private implementation was copied.

- chengyinhub-xcx/pages/merchant/decor/coop-setting/index.js, blob 13c858b69c93d0ae033627a64af233ebb6ac024d, lines 208–218: capacity null and explicit clearCapacity flag; other form/hidden values remain in the existing payload.
- chengyinhub-xcx/pages/merchant/decor/coop-setting/index.wxml, blob a621ff48899a642c69d76b2f3049a1ac6bfa62b7: editable capacity and explicit save.
- chengyinhub-admin/src/main/java/com/chengyinhub/web/controller/api/ApiMerchantController.java, blob ac739a411d2de90de83bebecf482508e1d363a2a, lines 632–655: COOP_MANAGE access, six whitelisted fields and clearCapacity propagation.
- chengyinhub-system/src/main/java/com/chengyinhub/business/service/impl/MmsMerchantServiceImpl.java, blob 6ca6adb7723fcdeb8ed9fe8ef7e7b26dbfb072b5, lines 303–321: clear requires COOP_MANAGE, null request capacity, exact true flag and current nonnull capacity; ordinary authorization/update guards remain.
- chengyinhub-system/src/main/resources/mapper/business/MmsMerchantMapper.xml, blob 5c130b6ef26ac3e31f19d550e3632274e8e4f2cd, lines 310–314: explicit capacity-null update.

## Scope and integration

Base tree 6a4cb1b17bc82af592cd495514a23d89af66c541. Three approved product paths: Core/MerchantOperationsContracts.swift (only MerchantCoopSettings), App/MerchantOperationsEditor.swift (cooperation field + confirmation hunk), Core/MerchantOperationsReading.swift (only cooperation acknowledgement branch). Exact shared-file hunks are supplied; do not replace the aggregate OperationsEditor, which has other NPC/category work. No service/AppSession/backend/API/project/catalog or central timing changes. Two bilingual keys are provided as a fragment.

## Checks

Actually run: four focused Python source/connection/localization checks and four Swift Tree-sitter parses. The initial affected checks were rerun once after the equality implementation changed. Eleven Core XCTest methods are authored but unrun: wire null/true, missing/null/empty, zero, restore/hidden preservation, fact/intent equality, invalid values, cancel versus discard, success then another edit, unknown replay block, explicit retry after definite rejection, and stale scope/source denial. Apple compile, Core execution, UI/accessibility, aggregate and live acceptance are not run. Outer artifacts record whitespace, protected paths and exact-base index replay. No live API call, save, commit or push occurred.
