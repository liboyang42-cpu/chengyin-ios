# P081 explicit charge choice

An unspecified chargeType now blocks cooperation draft review until the user explicitly chooses the existing free (0) or paid (1) hosting option. A missing/null read remains nil and the existing picker can show its unselected item; it is never defaulted to free. Existing unknown codes remain preserved and rejected by the separate chargeUnknown blocker. This adds no payment flow, rate, permission or endpoint.

The existing editor already renders draft.blocker and disables review through coordinator.canReview. MerchantOperationsDraft.previews also rejects a blocked draft. No UI product change is needed. Capacity validation still runs first, and optional/zero capacity semantics remain unchanged when a valid charge choice is supplied. Explicit capacity clear does not bypass the choice.

## Evidence

Plan: Questify城瘾全面改革施工计划.docx P081 paragraphs 1795–1798 and PA10; SHA-256 eb23c8aefc22954bcd6f73ef800c32b763e7f8c4e3d4c68b0a0956756fd50133.

Reference source liboyang42-cpu/chengyin at ce61c0bbace743ff835cb297ef41c89b52181636:

- chengyinhub-xcx/pages/merchant/decor/coop-setting/index.js, blob 13c858b69c93d0ae033627a64af233ebb6ac024d, lines 28 and 39 define the two options and nil initial state; lines 192–193 explicitly reject any value other than 0 or 1 before save; lines 210–218 send the selected chargeType on the existing payload.
- chengyinhub-xcx/pages/merchant/decor/coop-setting/index.wxml, blob a621ff48899a642c69d76b2f3049a1ac6bfa62b7, the charge dropdown retains a choose-first presentation for null.
- chengyinhub-admin/src/main/java/com/chengyinhub/web/controller/api/ApiMerchantController.java, blob ac739a411d2de90de83bebecf482508e1d363a2a, lines 632–655 retain COOP_MANAGE and the existing chargeType write field. The new native requirement is source UI validation, not a claim that the backend newly enforces it.

No private implementation was copied.

## Integration and verification

Base tree 6299e9454cefdaa5b31bf043a06ca72962f1a403. One approved product path: Core/MerchantOperationsContracts.swift, the MerchantCoopSettings.blocker hunk. The existing capacity-only test method now supplies chargeType:0 in its fixture so it keeps independently testing the original optional nonnegative capacity rule; its assertions and method name/count remain unchanged. Six new Core methods cover nil, unknown, 0/1, explicit selection, independent capacity and clear interactions. One bilingual key is provided as a fragment. Shared-file hunks include the single old test fixture adjustment.

Actually run: three focused Python checks and three affected Swift file Tree-sitter parses. Six new Core XCTest methods plus the corrected existing method are authored/updated but unrun. Swift/Apple compilation, Core execution, simulator UI/accessibility, aggregate and live acceptance are not run. Outer artifacts record whitespace, protected comparisons and exact-base replay. No UI budget/timeout, AppSession/service, live call, save, commit or push change.
