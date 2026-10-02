# Contextual publishing: current source contract audit

This change is offline implementation, not provider/deployment or Apple execution acceptance. No production grant is installed. Original private source files, data, credentials and media are not copied here.

| Flow | Current source decision | Native handling |
|---|---|---|
| Merchant node AI assist | Retired in current mini. `docs/audit-e2e-202609/05-publish-chain.md:108`, `00-baseline.md:31`, `tests/lint/ui-integrity-baseline.js:197–210`; no remaining mini template/fill caller. Backend method alone is not product approval. | Do not resurrect the old Flutter sheet. Existing unmounted template-fill request descriptor stays dormant. |
| AI quick draft | Active `pages/publish/simple/index.js:57–173`; POST theme/draft/quota, theme/draft with idea + productType. Up to three named nodes, every location explicitly confirmed. | Typed result, quota, cancel/use state, injectable sheet caller; original draft changes only after Use Draft. Unknown quota is not zero. Manual editing remains available. |
| Existing draft mode | Active `pages/publish/fabu/index.js:2495–2563`; selection is tentative, populated draft copied after confirmation; merchant scope cannot switch. | Local copy only, independent draft identity; no server clone endpoint. |
| Publish result | Flutter branching action sheet superseded by `pages/publish/fabu/index.js:6580–6692`: result closes to host project, preview lives on host. | Acknowledgment remains distinct from reviewed/published status. No fabricated success from local review. |
| Payment return | Active result-sheet + payment-workflow; every SDK outcome requires authoritative registration status. | Readback result UI must never trust SDK success. Production payment stays off. |
| Topic self-play | Active topic/index:987–1177; registration create/pay check recorded activity_host_data_sharing / activity_signup consent. Separate topic ownerType=1 and native payChannel=APP. | Independent topic request contract, never reuse activity ownerType=2. Consent/legal/provider/replay gates remain closed without approved integration. |
| SKU quantity/cart | Current mini app route registry has no mall/product/cart routes, while native visibility policy already explicitly hides points/mall. | Leave hidden; frozen Flutter SKU sheet does not authorize restoring it. |

Backend source examined: ApiAiController theme draft/quota and template-fill methods, ApiRegistrationController create/pay/pay-app consent gates. Source behavior is evidence of contract, never a claim of deployed availability. Frozen Flutter baseline was used only for discrepancy detection.

## Scoped normal-host AI composition

`NativeRuntimeDependencies.businessConfiguration` remains nil in normal composition. An accepted integration can supply `.publishingAIQuota`, `.publishingAITheme`, and independently `.publishingAIClub` exact POST routes through `BusinessRuntimeConfiguration`. These are not implied by `.publishingRead` or `.publishingWrite`. `AppSession.publishingAIDraftFactory` builds the real typed client; `makePublishingAuxiliaryService(feature:)` provides the club provider adapter. Both retain exact runtime context and durable opaque replay journals. An additional body guard rejects extra/missing fields, wrong method/path/origin/query, and unsupported modes. Role/market/session checks remain in the underlying service. No grant, credential, endpoint or provider is configured by these hooks.
