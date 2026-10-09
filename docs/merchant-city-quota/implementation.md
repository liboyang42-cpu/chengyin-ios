# P077/P078 city-node quota presentation and placement guard

The merchant content city-node screen now shows the existing authorized response's online-node count, including a maximum of zero. Missing, negative, string, Boolean and fractional quota values remain unknown. An unknown quota offers the existing read-again action; authorized node and application rows remain visible. Zero and exhausted quota have distinct explanations. Placement is available only when both counts are numeric non-negative integers and used is below maximum.

The placement editor shows the same projection from its own freshly loaded catalog. Its review action and `MerchantContentCommand.place` validation use the same `MerchantCityQuota` value. Template ownership and confirmed-address validation remain mandatory. No quota field is sent in a mutation. The existing coordinator clears a frozen review before reload, and the service reauthorizes, rereads and compares the complete frozen baseline before validating and dispatching. No coordinator, service, journal or grant was changed. The quota retry callback checks current scope, exact snapshot and observation time inside its task before invoking the existing load method.

This is a bounded improvement to the P077/P078 merchant content routes. It is not complete city-node feature parity. The older operations read-only catalog remains outside this approved write set. Claim and online/offline rules are unchanged. No new API, purchased entitlement, payment, refund, reward, credential, notification or production capability is introduced.

## Source alignment

The referenced local construction plan is `Questify城瘾全面改革施工计划.docx`, SHA-256 `eb23c8aefc22954bcd6f73ef800c32b763e7f8c4e3d4c68b0a0956756fd50133`, paragraphs 1779–1786 (P077/P078) and PA10. The caller calls this file v9; its cover still identifies edition 8. This increment uses those exact saved bytes without modifying the plan.

Private repository `liboyang42-cpu/chengyin`, pinned commit `ce61c0bbace743ff835cb297ef41c89b52181636`, was read only for contract verification. No private source is copied into this native candidate.

- `chengyinhub-xcx/pages/merchant/citynode/index.js`, blob `7c3620e2f31500c6ecf1bc7a9566619b5ae0eabb`: lines 15–17 strict numeric quota, 169–177 known/unknown projection, 196–211 retry and placement guard.
- `chengyinhub-xcx/pages/merchant/citynode/index.wxml`, blob `39f76dcdfb45d80fe420b85616b83702ef91da63`: lines 14–22 zero/full/unknown quota presentation and placement control.
- `chengyinhub-admin/src/main/java/com/chengyinhub/web/controller/api/ApiMerchantNodeController.java`, blob `e682d66ce410ef06d01301160386af8e0bd2b46d`: lines 85–90 maximum derivation; 236–275 authorized placement, existing template and address checks, quota rejection; 296–313 existing authorized list response and counts.
- `chengyinhub-system/src/main/java/com/chengyinhub/business/service/impl/MerchantCommerceService.java`, blob `68ebd97bfe02aab5d3c88dbbe56b7fc4cd9c171f`: lines 153–175 entitlement limit computation and 232–244 numeric result. No unlimited sentinel interpretation exists in these verified paths; invalid values are not converted into an invented unlimited grant.

The list endpoint returns scoped reads and counts. Retrying uses the already-existing native load path; this work made no live calls.

## Verification limits and integration

Six focused Python source checks and seven existing adjacent host checks passed. Six affected Swift files parsed with pinned Tree-sitter. These checks do not execute Swift. Thirteen Core XCTest cases, including coordinator reload and changed-quota confirmation scenarios, are authored but unrun. Apple compile, UI/VoiceOver, Core runtime, aggregate checks and live acceptance remain deferred to the consolidated batch. No new UI test method or timing budget was added.

Apply this dependent increment after service-time result tree `59f4366a48d84f7b5a5584a8aa0a97830f81dc20`. Merge the five unique localization entries from `Resources/MerchantCityQuotaLocalizations.fragment.json` and regenerate the project only in the integration batch. Shared catalog, project, AppSession, Muse-reserved paths and backend U2 are untouched. Do not treat this isolated candidate as an Apple-tested or production-enabled build.
