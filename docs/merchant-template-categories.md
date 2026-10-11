# Merchant template gameplay categories

## Baseline and scope

Upstream iOS: `96d727404a966cd3b3d2437c79449046beda560f`.
Exact incremental preimage: `0fc771a3b6bab15506618839ff47573729636674`.
Dependencies after 96: metadata `8448504` replayed `52923f9`; preparation `c988892` replayed `dbaac7a`; rules `c12905f` replayed `b23af69`; hints `ba3a202`; timeline `0fc771a`. The first two field-plan batches are already in 96. Apply this increment after those dependencies, not directly to 96. Seven earlier archives are immutable.

The master construction document W05, lines 399–427, requires typed merchant game authoring, human review, and server approval boundaries. Gameplay categorization is an existing Mini editing workflow supporting that authoring, not a new W05.2 requirement or proof that a template has been approved. A selected gameplay category never grants publication authority.

## Exact source contract

All source evidence is pinned to private backend/Mini commit `f1fe895f34c3664783aafd6145cf93e0de15878d`:

- `chengyinhub-xcx/components/cy/category-sheet/index.js`: POST `/api/category/list`, `type` and `parentid: 0`; buffer/selection/cancel, distinct failure and genuine-empty states.
- `chengyinhub-xcx/pages/publish/temp/index.wxml:1647–1649`: template picker uses type 4. `index.js:2091–2118` receives selected IDs; `2610–2620` requires at least one category on publish; `2765–2770` sends CSV as `activityCategoryids` and the first selected ID as `categoryId`; `3230–3240` restores saved IDs.
- `ApiCategoryController.categoryList`: root category filter, active/non-deleted/type filter, array result after `CategoryPublicProjection`. No pagination contract is invented. Native sends `parentid` explicitly as `"0"`.
- `CmsTemplatePublishRequest`: existing `categoryId: Long` and `activityCategoryids: String`.
- `TemplatePublishServiceImpl.copyPropertiesToMemberTemplate`: copies both fields. Existing merchant submit checks ownership and uses the same request type.
- `CmsMemberTemplateMapper.xml`: both fields persist on insert/update when non-null. `ApiTemplateController.myinfo:620–686` returns the entity and source `sysCategoryList` labels.

Native adds exactly one read route to this merchant service: POST `api/category/list` with form `type=4,parentid=0`. Existing merchant project permission/session validation runs before it. The existing authenticated read wrapper retains cancellation, account-scope, and unauthorized-response handling. No new write route or write permission is added.

## User workflow

1. Open a template and choose gameplay categories. Loading, error with retry, genuine empty catalog, and no local search matches have different states.
2. Search loaded names or IDs, toggle multiple current catalog entries, and reload without losing this sheet's buffered selection. Cancel or leave/background/change account/draft discards the buffer; late responses cannot apply it.
3. A saved ID no longer in the current catalog remains selected and blocks Apply until explicitly removed. An unrecognized CSV remains intact until the user explicitly replaces it. Loading cannot silently remove legacy data.
4. Apply requires at least one currently available ID. Its order follows selection order; when IDs actually change, the first becomes primary. This edits the existing document draft only. The sheet never saves or publishes.
5. Frozen review includes names, IDs, primary ID, explicit legacy-format replacement, and server-authority disclosure. Existing review cancellation/discard remains available.
6. With the existing write approval and permissions, submit uses `activityCategoryids` plus `categoryId` and then rereads the acknowledged template ID. Only that response becomes saved state. Production writes remain disabled without their existing approval/journal. No real submit was executed during development.

Opening and applying an unchanged supported selection preserves exact CSV bytes, original primary ID, and labels, even if the legacy primary differs from the CSV. It does not silently normalize legacy state. Unsupported source is sent back unchanged unless explicitly replaced. Missing/null source values remain omitted. The picker does not introduce a new clear-all save operation; its Apply follows Mini's at-least-one publication rule. Previously empty untouched templates keep their existing validation behavior; this feature does not retrofit global publication validation.

Wire names `categoryIds`, `sysCategoryList`, names, and UI flags are never added to the save body. Category choices are not AI-mapped. The existing duration/ordinary players distinction, local-only W05.2 plans, unknown-write replay lock, rewards, and other write gates are unchanged. No category ID is generated from a name. Catalog IDs are positive JavaScript-safe integers; malformed/duplicate/wrong-type catalog rows produce failure instead of a partly usable list.

The editing buffer lasts for the current sheet/session only. It is not durable local storage. Synthetic fixtures are clearly synthetic and exercise the same document/readback path without any backend write.

## Integration fragment

Register new runtime files in the appropriate existing targets:
- `Core/MerchantTemplateCategorySelection.swift` (Core target and existing App inclusion convention)
- `App/MerchantTemplateCategoryPicker.swift` (App target)

Register new Core/UI test files and merge 24 bilingual entries from `Resources/MerchantTemplateCategoryLocalizations.fragment.json`. Integer interpolation keys use `%lld`. The delivered evidence `integration-fragment.json` lists exact paths/methods. Central project/catalog/CI files are not edited here.

## Verification and limitations

- PASS: 11 new source checks plus 66 related source checks; 9 Swift files parsed with pinned Tree-sitter; whitespace and forward/reverse patch checks; exact preimage and previous seven archive hashes.
- Authored but NOT RUN: 20 Core XCTest methods, 3 simulator UI flows. Core coverage includes strict decoding/no-op preservation, cancel/single-use/stale/account/out-of-order reads, explicit unavailable/unsupported handling, exact catalog form/grant, existing approved submit and canonical label/primary readback, no approval/no replay. UI covers cancel, ordered selection/review/save/readback, retry reload buffer, empty Apply block, and discard.
- NOT RUN: Swift type checking/build, Apple SDK checks, simulator, screenshots, VoiceOver/Dynamic Type, real backend/payment/reward acceptance. Required dot environment has neither `swift` nor `xcodebuild`; no alternate machine used. Parser/source checks do not prove native compilation or runtime behavior.
- Existing old source/CI failures are not repaired or included in this feature's acceptance claim. Earlier text-moderation gaps remain a separate backend activation issue owned by root; this increment adds no merchant-authored text field or backend change and makes no deployment assertion.
