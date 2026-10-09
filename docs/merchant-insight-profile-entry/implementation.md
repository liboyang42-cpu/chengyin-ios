# P075 cooperation-profile settings entry

The insight screen now presents the returned cooperation-profile configuration state, capacity and demand, with an entry to the existing cooperation settings page. `configured` is recognized only as a JSON Boolean. Missing, null, numeric or string representations stay unknown and do not enable the entry. Capacity is recognized only as a returned non-negative integral JSON number; zero remains zero. The configuration state is never inferred from capacity, demand, recommendation results or a merchant role.

The entry reuses the preceding insight navigation origin: the current authorized workbench merchant ID and operations-reader scope, bound to the matching loaded insight/session snapshot. The callback, selected destination and factory all recheck that origin. A scope change invalidates the old destination. It opens only existing `MerchantOperationsDocumentView(.cooperation)` through the current session reader. That reader rechecks the existing COOP_MANAGE permission, scoped profile read and normal editor review/save policy. The entry does not read a new endpoint, grant a permission, save a setting or initiate AI processing.

## Source and exact scope

The saved construction plan SHA-256 `eb23c8aefc22954bcd6f73ef800c32b763e7f8c4e3d4c68b0a0956756fd50133`, P075 paragraphs 1771–1774, includes `goProfileSetup`. The caller calls this saved file v9; its cover still says edition 8. The plan is unchanged.

Private `liboyang42-cpu/chengyin@ce61c0bbace743ff835cb297ef41c89b52181636` source was read only:

- `chengyinhub-xcx/pages/merchant/marketing/ai-insight/index.js`, blob `b127d26613e45d1c670e7e5e5d47939c78115bb3`, lines 10–11 and 279: profile setup opens the existing decoration cooperation settings page.
- `chengyinhub-system/src/main/java/com/chengyinhub/business/service/impl/MerchantInsightServiceImpl.java`, blob `437e35e44e897d3d3af8eebc5d55bd24d3f65f22`, lines 169–185: configured, capacity, suitable activity types and demand come from the current merchant profile; configured is explicitly set by the server. It has no source-merchant identity field, so origin still comes from the authorized workbench.
- `chengyinhub-admin/src/main/java/com/chengyinhub/web/controller/api/ApiMerchantController.java`, blob `ac739a411d2de90de83bebecf482508e1d363a2a`, lines 547–557: existing cooperation-profile read remains under COOP_MANAGE. This package does not alter or directly call that endpoint.

Base tree `110c4c0fd3aed6a8a35dceb3b09d93d3ed7f4901`, after the frozen insight recommendation package. Only four product paths change: `Core/MerchantMarketingModels.swift`, `App/MerchantMarketingView.swift`, `App/NativeEntryLandingView.swift`, and new `App/MerchantInsightProfileSummary.swift`. The new typed route is not accepted by the legacy three-token AI suggestion parser. Prior recommendations, current Home origin injection and all public merchant/status files remain unchanged. Apply additive shared-file hunks, not whole-file replacement.

## Checks and integration

Four focused Python checks and five affected-file Tree-sitter parses passed, together with exact-base replay and whitespace checks. Four AppUnit schema/presentation tests are authored but unrun. Apple compilation/navigation/UI/accessibility, aggregate and live acceptance remain deferred. No previous feature suite was repeated.

Seven unique bilingual keys and new-file project registration remain central. Localization checks accept the isolated fragment or the fully merged catalog with exact per-key equality. No UI test method, runtime budget, CI timeout, AppSession, service, coordinator, default grant or backend U2 change. No live API request or configuration save occurred.
