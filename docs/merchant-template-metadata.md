# Merchant template: source-backed duration, player description and readback

## Delivered increment

The existing merchant template editor and immutable review now expose the actual server fields `duration` and `players`. The native edit property `gameDurationMinutes` is deliberately separate from `participationPlan.durationMinutes`; `players` remains ordinary game player-count text, not `maximumParticipants` or approved venue capacity. No copying between these fields is performed.

- `duration`: JSON integer minutes, from 0 through `Int32.max`. This matches the backend Long → Integer exact conversion. Zero is the server's existing creation default. Malformed, negative or out-of-range readback fails rather than truncating or inventing a value. Edits outside the supported range block review.
- `players`: existing String metadata, with no fabricated numeric-capacity meaning. A value such as “2–6” remains a String.
- Blank edits omit the corresponding key. They do not clear existing values. The UI explains this behavior; an omitted duration on creation receives the server's existing 0 default.
- AI suggestion allowlists remain unchanged. The two prior session-local planning groups remain independent and continue to block submission whenever present.

The new server-backed metadata is optional for legacy compatibility. This is not completion of all mandatory W05.2 operating and safety requirements. An actual maximum-capacity or staffing save contract is still unverified; no such mapping is inferred from `players`.

## Exact source evidence

All backend/controller/DTO evidence was read at `f1fe895f34c3664783aafd6145cf93e0de15878d`:

1. `CmsMemberTemplate.java` lines 56–68: String `players`, Long `duration`, documented as minutes.
2. `CmsTemplatePublishRequest.java` lines 39–49: String `players`, Integer `duration`.
3. `ApiMerchantNodeController.templateSubmit`, lines 172–231: existing `/api/merchant/city-node/template/submit` receives `CmsMemberTemplate`; requires authenticated principal, PROJECT_MANAGE and merchant-node permission; validates content/sensors/coupon ownership; invokes `saveMerchantNodeTemplate` and returns the resulting template ID.
4. `TemplatePublishServiceImpl.saveMerchantNodeTemplate`, lines 398–440: existing updates require owner and merchant-node identity. Content is copied through the publish DTO whitelist; duration uses `Math.toIntExact`, not truncation. Null duration on update stays null so dynamic SQL preserves the old column. Server-owned ownership/status/publication fields are reset by the service. Lines 523–533 copy players and duration into the stored entity.
5. `CmsMemberTemplateMapper.xml`: result mapping at lines 16/20, inserts at 271/274 and 337/341, updates at 413/416. Both keys have existing database mappings.
6. `ApiTemplateController.myInfo`, lines 620–686: existing `/api/template/myinfo` reads the legacy entity, applies owner/public eligibility and secret stripping, and returns the entity. Native access checks and exact returned-ID checks remain in place. This work does not broaden who can read a private template.
7. Mini `pages/publish/temp/index.js`, current blob `76e39df5c326aaf029bda8da21562072fb352553`, still matches the previously inspected snapshot. Its citynode branch at 2746–2747 sends `toNodeTemplate(formData)` to the existing merchant submit endpoint; 2756–2776 copies form values with specific remappings. Its generic duration/player fields do not prove a venue-capacity contract.

Exact excerpts, file blob IDs and verified source URLs are retained with this batch's evidence. No backend code is changed.

## Authoritative readback and creation identity

The existing reader protocol now has a template-specific save result carrying the ID acknowledged by the submit endpoint. The production session reader still uses the same dormant `MerchantOperationsService.save`, with independent endpoint approval, exact account/session checks, fresh baseline, permissions and durable replay journal.

After a definite acknowledgment:

- The coordinator clears the submitted copy before readback; it does not call that copy authoritative or approved.
- A new template adopts the acknowledged positive ID, then reads the existing owner/detail route at that ID. An update cannot silently switch to a different acknowledged ID.
- Only an exact-ID returned template becomes the baseline/draft. New-template editing continues with that ID, and the retained-image owner is re-created for the new destination rather than reusing the former unsaved-template context.
- Readback failures or mismatched returned IDs leave the submitted copy hidden. Reload retries a read at the acknowledged destination; it does not resend the write.
- Session changes, cancellation and stale generations cannot promote late readback. Unknown writes keep the existing uncertainty lock and do not start readback or retry.

Readers that lack a creation receipt refuse new-template saving before sending. The DEBUG fixture uses an explicit synthetic ID and source-normalization rules for these tests; it is not evidence of live backend behavior.

## Integration and verification

This increment depends on the two sealed candidates: participation plan `c80fcab1d70996e172ed9ff6c8452a7b9cb8f98d`, then exit plan `c626436182221b38b65b65f788dd8b8b78df6f02`, both rooted at true native base `53bbc93ea77bcb66a2ed1701e3e0ef8896d30e13`.

Merge the 8 English/Simplified-Chinese entries in `Resources/MerchantTemplateMetadataLocalizations.fragment.json` through the integration line. Register `Tests/CoreTests/MerchantTemplateMetadataTests.swift` (13 tests) and `Tests/AppUITests/MerchantTemplateMetadataFlowTests.swift` (2 tests). Runtime code is in already registered files. No central PBX/catalog/CI file is changed.

The authored Core tests cover decoding, integer/overflow boundaries, ordinary String players, omitted fields, local-plan locks, AI non-overwrite, acknowledged create/update readback, changed IDs, failed readback/read-only recovery, uncertain saves, session changes and a full synthetic approved service transport through the exact submit/detail routes. UI tests cover canonical fixture readback/reload and overflow rejection.

Executed source checks and pinned Tree-sitter parsing are supplemental. Swift/Core XCTest, Apple builds, UI execution/screenshots/accessibility, and real endpoint/provider acceptance remain NOT_RUN when Swift/Xcode is absent. No remote repository write, real backend write, payment, inventory or reward operation was performed, and no production capability was enabled.
