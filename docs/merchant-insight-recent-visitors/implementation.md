# P075 recent visitor summary

The current authorized insight response already includes recentVisitors. The native insight screen now presents only nickname, visitCount, topicName and lastAtText from that response. There is no secondary customer, member, avatar or contact request and no row action. Valid server time text is preserved verbatim.

Missing/malformed data is unavailable; an explicit empty array is a known empty result. The server's maximum of five returned visitors is enforced without silently truncating a malformed larger response. Invalid/missing visit counts remain unknown rather than becoming one visit. Text fields must actually be strings. A stale source merchant/account scope hides all visitor rows immediately through the existing loaded insight origin comparison and current reader scope. Runtime invalidation timing has not been measured.

## Evidence

Construction plan: Questify城瘾全面改革施工计划.docx, paragraphs 1771–1774 (P075) and PA10. Exact document SHA-256 eb23c8aefc22954bcd6f73ef800c32b763e7f8c4e3d4c68b0a0956756fd50133.

All source references below use liboyang42-cpu/chengyin at ce61c0bbace743ff835cb297ef41c89b52181636. These are reference metadata; no private implementation was copied into this native repository.

- chengyinhub-xcx/pages/merchant/marketing/ai-insight/index.wxml, blob 7dc487b2fd50d781190384c827474498e10e8bd5, lines 90–100: recent visitor display fields.
- chengyinhub-system/src/main/java/com/chengyinhub/business/domain/vo/ai/MerchantInsightResp.java, blob 11b6457518fb1e5ae364c746b1336931197d96d4, lines 51–77: RecentVisitor response fields and formatted lastAtText.
- chengyinhub-system/src/main/java/com/chengyinhub/business/service/impl/MerchantInsightServiceImpl.java, blob 437e35e44e897d3d3af8eebc5d55bd24d3f65f22, lines 483–510: ordered latest visitor aggregation, response assignment, five-row maximum at line 509.

## Scope and integration

Three product paths: new Core/MerchantInsightRecentVisitors.swift, new App/MerchantInsightRecentVisitorsSection.swift and the single three-line insertion in App/MerchantMarketingView.swift. This increment depends on the completed insight navigation and cooperation-profile entry, base tree ab33cfe894f7bbdbc2cba4fbcb7fee2cf53633e2. Apply only the exact hunk to the aggregate MarketingView; preserve other feature batches. Eight bilingual entries are provided as Resources/MerchantInsightVisitorsLocalizations.fragment.json for central catalog merge. Central project regeneration is required for the new files. Project, catalog, AppSession, services, public merchant status, Muse paths and UI timing are untouched.

## Validation

Actually run: four focused Python checks, four-file Tree-sitter parse (tree-sitter 0.26.0 and tree-sitter-swift 0.7.3). Before freeze, whitespace and exact-base index replay are recorded in the outer package. The localization check accepts an absent fragment or a complete exact-value merge, rejecting partial or conflicting merges.

Six Core XCTest methods are authored but not run. Swift/Apple compilation, simulator UI, accessibility and scope-invalidating runtime tests are not run; source checks are not runtime privacy acceptance. No aggregate or prior-feature test suite was repeated. No live request, save, deployment, commit or push occurred.
