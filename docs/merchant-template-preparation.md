# Merchant template: persisted venue and materials editor

## Delivered operation

The existing merchant template creation/editing form now includes a native venue-type picker and a multiline materials editor. These are the existing persisted `usageLocation` and `requiredMaterials` fields, using the prior batch's exact template save and authoritative readback. They are not another session-only planning block.

The venue picker mirrors Mini's seven exact wire values: 景区, 公园绿地, 商圈街区, 古镇老街, 博物馆, 校园, 室内场馆. English and Chinese labels are localized, while the stored wire values remain unchanged. No value is selected by default. An unfamiliar loaded value remains visible and is preserved byte-for-byte unless the merchant explicitly selects a known replacement. The placeholder is not a clear command.

Materials support multiple lines. Request encoding trims only outer whitespace and preserves line breaks. Empty venue/material values are omitted, so they do not pretend to clear an existing server column. The UI and frozen review explain this behavior. Both fields are optional for existing-template compatibility; this slice does not establish every mandatory W05.2 field.

Venue and materials descriptions do not prove site permission, actual suitability or equipment availability. The UI asks the merchant to verify these facts. No location provider, address change, stock reservation, payment or reward flow is invoked.

## Exact source basis

MASTER v10's merchant-authoring section (lines 399–400) permits space/equipment constraints as shop-authoring inputs. This slice implements existing preparation metadata relevant to that requirement; it is not full safety/operating-constraint acceptance.

The corresponding Mini page and backend were checked at `f1fe895f34c3664783aafd6145cf93e0de15878d`:

- `chengyinhub-xcx/pages/publish/temp/index.wxml` lines 119–135, blob `b5d2e240b5b3f74f0c63cbdaae1437dcc729afc1`: materials input and the existing venue picker.
- `pages/publish/temp/index.js`, blob `76e39df5c326aaf029bda8da21562072fb352553`: exact `VENUE_OPTIONS` at line 115; fields at 336–337; materials edit at 1372–1374; venue sheet and selection at 1446–1454 / 1478–1482; source hydration at 3046–3047. The current-ref blob was verified equal to the already inspected Mini source. Its merchant citynode branch retains `/api/merchant/city-node/template/submit`.
- `CmsMemberTemplate` and `CmsTemplatePublishRequest`: both preparation fields are Strings.
- `TemplatePublishServiceImpl.saveMerchantNodeTemplate`: copies through the established publish DTO whitelist; `copyPropertiesToMemberTemplate` lines 529–530 copies both fields.
- `CmsMemberTemplateMapper.xml`: existing result, insert and dynamic-update mappings preserve null/omitted values and store non-null preparation values.
- The prior batch's existing `/api/template/myinfo` readback returns these fields through the same entity and authorization path. No alternative route is added.

Exact source excerpts, blob IDs and verified URLs are in this batch's evidence.

## Existing safety and lifecycle boundaries

All editing goes through the existing coordinator and dirty-state guard. Frozen review includes the venue label/source value and materials text. Cancel keeps the current edits; discard/reload restores source data; old review objects cannot save later edits.

Saving still requires the existing independently approved endpoint, authenticated session, merchant project permission, fresh baseline and durable replay journal. The server-returned template ID and source detail control the post-save baseline. Readback failure cannot promote the submitted copy or trigger a new write. AI allowlists do not map either preparation field. Presence of either earlier local planning group still blocks submission of the whole template.

The DEBUG reader now models the existing omission semantics for preparation values. This is a synthetic test aid, not live server evidence.

## Integration and verification

Base: `8448504d32d27a2368a751a67d2130061f562f18`, following the three sealed merchant batches from native base `53bbc93ea77bcb66a2ed1701e3e0ef8896d30e13`. This patch contains only preparation-field changes; the earlier packages remain unchanged.

Merge `Resources/MerchantTemplatePreparationLocalizations.fragment.json` (14 English/Simplified-Chinese entries) through the integration line. Register `Tests/CoreTests/MerchantTemplatePreparationTests.swift` (10 tests) and `Tests/AppUITests/MerchantTemplatePreparationFlowTests.swift` (2 tests). Runtime code stays in already registered files. Central PBX/catalog/CI files are untouched.

Focused source checks cover exact venue choices, strict optional String decoding, unknown-value preservation, exact payload keys, no AI/local-plan bypass, mounted editor/review, translations and authored test inventory. Core tests additionally exercise a full synthetic approved submit → exact-ID source-readback path, cancel/discard behavior, omitted-value preservation and no replay. UI tests cover selection/material edits, review/cancel/save/readback and explicit discard before reload.

Swift/Core XCTest, Apple builds, UI execution/rendering/accessibility and real backend acceptance remain NOT_RUN without Swift/Xcode. Python and pinned Tree-sitter checks are supplemental. No remote repository write, real sensitive write, payment, reward or production activation occurred.
