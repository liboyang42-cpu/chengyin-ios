# P085 CRM source date picker

Customers and CRM segment filters now offer the same local date-range picker beside their existing sourceStart/sourceEnd fields. It changes no request itself. The original Apply Filter and saved-segment review/save paths remain the commit points. Each bound can be absent, the same date is allowed, and the end may be at most 366 days after the start, matching the verified backend contract.

Validation uses pure Gregorian integer day arithmetic, including leap years, with no elapsed-second/DST or server timezone calculation. The picker reuses the existing MerchantStationServiceWindow fixed-calendar carrier solely to present/read civil year-month-day components. No timestamp or UTC boundary is submitted; the original date strings remain the wire contract. Device today is proposed only after an explicit enable/replacement action, not on opening an empty field.

Opening/canceling/no-op keeps the exact original strings. Unrecognized source text is displayed until the user explicitly replaces or clears it. Replacing one bound does not rewrite the other. Clear controls affect only their selected local date. Nil versus an existing empty optional string is preserved on no-op in the segment host. The picker validates its own explicit Apply; existing manually entered fields and request validation remain unchanged.

A captured account scope, authorization generation and source merchant ID fence the open picker. The original date pair must also still match before apply. Changes to context, either bound, or disappearance close the local session. New rows/requests, customer identity data, notifications, exports and permissions are not introduced. Runtime dismissal/invalidation timing remains unmeasured.

## Source evidence

Plan: Questify城瘾全面改革施工计划.docx P085 paragraphs 1811–1814 and PA10, SHA-256 eb23c8aefc22954bcd6f73ef800c32b763e7f8c4e3d4c68b0a0956756fd50133.

All source references are liboyang42-cpu/chengyin at ce61c0bbace743ff835cb297ef41c89b52181636. No private implementation was copied into native code.

- chengyinhub-xcx/pages/merchant/customer/index.wxml, blob afa7ac2fbfa95ea1aac01d9bb6ba8e1e91ea8928, lines 142–146: two date-only source controls.
- chengyinhub-xcx/pages/merchant/customer/index.js, blob 89859d7d4b55253409a952b4ee13f4d756c3737a, lines 254–258 and 437–450: existing date selection/clear and sourceStart/sourceEnd JSON query fields.
- chengyinhub-system/src/main/java/com/chengyinhub/business/domain/dto/MerchantCrmCustomerQuery.java, blob e317f0bffb561c8a625aa680c49da320923bb36f, lines 14–19: wire date strings and server-only derived timestamp bounds.
- chengyinhub-system/src/main/java/com/chengyinhub/business/service/impl/MerchantCrmAppServiceImpl.java, blob e83de32e964301fb2c5395fdbeb012a578c12e58, lines 686–691: server date parsing, inclusive end-day via next-day exclusive boundary, same-day and 366-day range rule.
- chengyinhub-system/src/main/java/com/chengyinhub/business/service/impl/MerchantCrmSegmentServiceImpl.java, blob 1b2efc27db9fe7df3e316d5e833d4c1db379c7ce, normalize date block: the same range rule for saved segments.
- chengyinhub-system/src/main/resources/mapper/business/MerchantCrmAppMapper.xml, blob 1b95e06b64fffae2f487b1c548480271b81ea175, lines 142–146: server-derived lower-inclusive/upper-exclusive date constraints. The native picker does not calculate these server bounds.

## Scope and integration

Base tree de815c12769d9e1e099b90ef6ddcde51aa9abfa4. Four approved product paths: new Core/MerchantCRMDateRange.swift and App/MerchantCRMDateRangePicker.swift; narrow source-date insertions in App/MerchantBusinessViews.swift and App/MerchantEngagementViews.swift. Shared existing-file hunks are supplied; preserve aggregate contact, empty-state, reviews and other changes. Ten bilingual entries are supplied as a fragment and central project regeneration is required for new Swift files. AppSession, readers/coordinators, service/query contracts, Muse, backend, shared catalog/project and UI budgets are unchanged.

## Checks

Actually run: four focused Python source/connection/localization checks and five Swift Tree-sitter parses. Eight Core XCTest methods are authored but unrun: empty/one-sided/same-day, exact 366/367 boundaries, malformed/reversed, no-op raw preservation, explicit single-bound replacement, clear, calendar-carrier literal roundtrip and DST/skipped-local-day names. Swift/Apple compilation, Core execution, simulator UI/accessibility, runtime scope invalidation, aggregate and live acceptance are not run. Outer artifacts record whitespace, protected comparisons and exact-base index replay. No live API call, save, commit or push occurred.
