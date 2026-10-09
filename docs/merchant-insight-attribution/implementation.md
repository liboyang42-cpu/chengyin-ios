# P075 attribution and visitor mix

The insight screen now renders the existing facts.attribution visitors/checkins/redeems counts and facts.split newVisitors/returningVisitors from the same currently authorized insight response. These remain independent server projections. All three explicit attribution zeros form a known empty result; missing, malformed, negative, fractional or unsafe counts never become zero. A partial attribution or split is displayed as incomplete, without deriving missing counts from another field. Explicit zero visitor split counts remain visible.

The server window must be nonblank text; the original text is retained. A missing window stays unknown in both the new section and the existing facts section. No 30-day period, timezone or date calculation is supplied locally. The original redeemRate and repeatRate read/display expressions are unchanged. Added descriptions state their separate denominators: registrations in the reporting window, and members with a redemption in that window. Returning visitors instead mean window visitors with a historical visit before the window, and are not used to derive a repeat rate. No new rates, percentage bars or comparison deltas are calculated.

The new summary requires the current source merchant/read scope, matching loaded origin and insight, and no pending reload. If that context changes, its rows are hidden. Existing AppSession, coordinator and transport behavior are unchanged. Runtime invalidation timing remains unmeasured.

## Source evidence

Plan: Questify城瘾全面改革施工计划.docx P075 paragraphs 1771–1774 and PA10; SHA-256 eb23c8aefc22954bcd6f73ef800c32b763e7f8c4e3d4c68b0a0956756fd50133.

Pinned private source liboyang42-cpu/chengyin at ce61c0bbace743ff835cb297ef41c89b52181636 was read as reference. No private code is included in this native increment.

- chengyinhub-xcx/pages/merchant/marketing/ai-insight/index.js, blob b127d26613e45d1c670e7e5e5d47939c78115bb3, lines 118–123 (unknown vs explicit zero attribution), 217–228 (two different rate definitions), 232–267 (attribution and visitor split).
- chengyinhub-xcx/pages/merchant/marketing/ai-insight/index.wxml, blob 7dc487b2fd50d781190384c827474498e10e8bd5, lines 32–86 (attribution, separate metric scopes and visitor split).
- chengyinhub-system/src/main/java/com/chengyinhub/business/service/impl/MerchantInsightServiceImpl.java, blob 437e35e44e897d3d3af8eebc5d55bd24d3f65f22, lines 377–455 (same facts snapshot, counts and cross-window split), 520–582 (rate denominators).

## Integration and verification

Base tree 2c8ef1f07baeb27d42aa840284e140798bf67690, following the recent visitors package. Exactly three product paths: new Core/MerchantInsightAttribution.swift, new App/MerchantInsightAttributionSummary.swift and the facts hunk in App/MerchantMarketingView.swift. Preserve all other aggregate additions; use the separate integration-hunks.patch. Thirteen bilingual keys are provided for central catalog merge. Central project regeneration is required; shared project/catalog files and UI method/budget/timeout files are not modified.

Actually run: four focused Python source/connection checks and four Swift Tree-sitter parses. These do not execute Swift or establish UI/runtime identity behavior. Seven Core XCTest methods are authored but unrun. Apple compile, simulator UI/accessibility, aggregate and live acceptance are not run. Outer artifacts record whitespace, protected-path and exact-base replay verification. No live request, configuration save, deployment, commit or push occurred.
