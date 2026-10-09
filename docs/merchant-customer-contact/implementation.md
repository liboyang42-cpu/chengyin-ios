# Customer-list contact summary

The existing merchant CRM list response already provides a server-masked `phone` or a `contactHint` explaining its absence. The mini customer list displays one of these. The native compact customer row previously omitted both, leaving users unable to distinguish a missing number from a permission, consent, or responsible-organizer restriction.

This slice adds a stateless contact summary only to compact customer rows. It uses the current validated row and merchant access supplied by the existing page. Customer-read permission is mandatory; masked phone display also requires sensitive-customer-read permission. The phone must match the inspected server mask framing. Unexpected cleartext or unknown formats are not rendered or remasked; the server reason is used when present, otherwise the UI says contact details are unavailable. It does not claim the customer never supplied a number.

The response fields, customer identity, filters, pagination, current-snapshot/lifetime guards, detail navigation, actions and mutations are unchanged. No additional query, cleartext lookup, call, copy, export, URL, provider, permission, persistence or authorization is introduced. Existing sensitive amount presentation is untouched.

## Source evidence

Pinned private source ref: `liboyang42-cpu/chengyin@ce61c0bbace743ff835cb297ef41c89b52181636`.

- `chengyinhub-xcx/pages/merchant/customer/index.wxml`, lines 98–110; blob `afa7ac2fbfa95ea1aac01d9bb6ba8e1e91ea8928`: phone display or server-provided contact reason.
- `chengyinhub-xcx/pages/merchant/customer/index.js`, lines 931 and 948–951; blob `89859d7d4b55253409a952b4ee13f4d756c3737a`: phone string trimming and nullable-string validation.
- `chengyinhub-system/src/main/java/com/chengyinhub/business/service/impl/MerchantCrmAppServiceImpl.java`, lines 80–110; blob `e83de32e964301fb2c5395fdbeb012a578c12e58`: current merchant CRM permission, contact responsibility and consent checks, then masking before response.
- `chengyinhub-system/src/main/java/com/chengyinhub/business/security/PiiCryptoService.java`, lines 165–174 and 191–200; blob `400475f5d1679b2b3552b1963ae2f5eb8cf4ef3b`: masked shapes are one star, 1/2 UTF-16 units plus four stars plus 1/2 units, or 3 plus four stars plus 4 units. The native projection recognizes these shapes; it never computes or obtains a cleartext number.

Private source bytes are not part of this native patch.

## Integration and checks

Baseline native tree: `73e081ad4a1f3524f803ba6d9dac8806b745e880`. The only existing-file change is one three-line insertion in `App/MerchantBusinessRecordViews.swift`; a focused contract removes it and verifies the exact prior file hash. AppSession, Muse-reserved files, backend/U2, shared catalog, project and CI files are unchanged.

Root integration should add the two unique entries from `Resources/MerchantCustomerContactLocalizations.fragment.json` to the existing catalog and regenerate the project using its normal generator. No UI test methods or timing/sharding changes are introduced.

Nine Core tests and three app-hosted tests are authored for permission reductions, missing/null/malformed fields, source mask variants, cleartext rejection, exact reason fallback and refreshed rows. Only focused Python contracts and supplementary syntax parsing are run locally. Swift/Core/AppUnit, Apple UI/accessibility and live-backend execution remain unrun in this Linux task; static checks do not establish runtime acceptance.
