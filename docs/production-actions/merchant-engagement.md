# Merchant engagement production composition

Status: native implementation with ordinary-HTTP fake tests; real calls remain **OFF**. Swift compilation and Apple runtime acceptance are separate CI gates. No accounts, customers, messages, workbooks, invitation tokens, uploads or payments were sent during implementation.

## Normal path and scope

`AppSession.merchantEngagementReader` now obtains an exact service from `MerchantEngagementProductionFactory`, supplied by `NativeRuntimeDependencies.merchantEngagementApproval`. The default is nil. The ordinary read service stays read-only, the public unreviewed `execute` stays test-only, and synthetic fixtures do not authorize production. Grants are memory-only immutable commands, binding the exact merchant, account, CN market, API origin, namespace, method/path, customer/refund/task identifiers, audience/filter, channel, title/content, evidence selection and request bytes. Role labels alone grant nothing.

`MerchantEngagementCoordinator` is the only authority-ticket issuer. It checks the immutable review, refreshes source access and targets, requires a durable journal, reserves the namespaced intent, refreshes access/target proof again after reservation, and fences current context, epoch, cancellation and review at the final HTTP boundary and after the awaited response. The transport reconstructs the exact request and forwards once. A request with a different header, path, verb or body cannot reuse authority. Unknown results retain the durable lock across navigation, logout and relaunch. No financial result is inferred from these nonfinancial receipts, and evidence upload never submits an opinion or executes a refund.

## Supported source operations

- Save CRM segment: POST `/api/merchant/crm/segments`; exact name/filter and source request ID
- Create campaign: POST `/api/merchant/crm/campaigns`; source segment/coupon and audience preview are refreshed; creation never chains dispatch
- Broadcast: POST `/api/merchant/crm/broadcast`; exact audience expression, groups, filters and content are reviewed; server recomputes marketing consent and frequency/daily limits
- Create export: POST `/api/merchant/crm/exports`; exact query and request ID
- Download export: GET `/api/merchant/crm/exports/{taskId}/download`; exact account/store/task and fresh status/permission, credential in `X-CRM-Export-Token` only
- Reveal customer contact: POST `/api/merchant/crm/customers/{customerMemberId}/contact`; exact customer and call/copy purpose, never a store ID substituted for a customer ID
- Upload evidence: multipart POST `/api/common/uploadOSS`, source business type `merchant_aftercare_evidence` and mandatory multipart `refundId`; exact bytes/name/type and refund context, fresh `canRespond` and `allowedDecisions` containing `EVIDENCE`

Deployment must explicitly review applicable marketing-consent, customer-contact privacy, customer-export privacy and aftercare-evidence privacy obligations and provide its reviewed policy version. These are activation requirements, not fabricated user consent or a claim that legal/provider acceptance happened. Server consent and withdrawals remain authoritative.

## Deliberate source blockers

Current campaign detail returns title, channel, counts and recipient receipts but omits content. Production dispatch/retry must have the full message and complete frozen recipient list before review, so title-only current responses stay disabled. Native support will fail closed until a source-backed complete contract is supplied. No guessed message content or receipt list is substituted.

Current operator invitation acceptance provides only an opaque token and has no pre-acceptance destination/store/role proof. Production acceptance grants are rejected. The existing offline review remains available; no invented preview API was added. General merchant operator creation/role management is covered by its distinct `MerchantBusinessProductionFactory`, not by this acceptance path.

## Export and device boundary

Production download uses the existing ephemeral, no-redirect, response-limited HTTP transport, with a 32 MiB native memory budget checked while accumulating and again before handing bytes to the view. This is a client bound, not a claimed backend limit. Download URLs stay on the exact approved origin and path; tokens never enter a URL, filename, log or persistent journal. Only XLSX ZIP signatures are accepted; JSON/HTML errors never become files. This signature check is not a complete workbook malware scan. The source server rechecks current data-sharing consent and owns export authorization, expiry and auditing.

Separate exact device grants authorize customer+purpose call/copy, task-specific workbook save and refund-specific image selection. Download permission does not grant saving or sharing. Workbook save repeats permission and identity checks before presenting native save UI; export does not automatically open a share sheet or select a third-party recipient. Contact is reserved for one-time consumption before its fresh access await, eliminating duplicate-tap reuse; it is never shown as plain text in the UI, and copy remains local-only with a short expiration. Camera remains off independently.

## Evidence provenance and verification

Implemented freshly from the existing native contracts and a read-only comparison against the source controller/service contracts and the business reference. No private implementation or real data was copied into this public code.

Source contracts checked: `ApiMerchantCrmController` (segments, campaign create/detail/dispatch/retry, broadcast, exports/status/download, customer contact); `ApiMerchantOperatorController` (token-only acceptance); `MerchantCrmCampaignServiceImpl` (content omission in detail mapping); `MerchantCrmExportServiceImpl` (owner/token/consent checks); `ApiCommonController` (mandatory refund-bound upload); `MerchantAftercareServiceImpl` (operation-specific allowed decisions); retained Flutter `merchant_crm_console_api.dart`, `merchant_customer_detail_api.dart`, `merchant_operator_api.dart` and `merchant_aftercare_api.dart`. The supplied business reference is the target behavior guide; neither historical Flutter UI nor static parity proves deployed readiness.

Tests include ordinary HTTP dispatch, exact-context/body grants, default OFF, durable-journal enforcement, role/permission and store changes, post-reservation revocation, cancellation at the final HTTP boundary, replay/unknown locks, post-response account replacement, exact audience/content, source-blocked dispatch/invitation, evidence fields, export header/bounds and device separation. English/Chinese offline UI scenarios exercise the same production factory with an inert HTTP transport. Python source assertions and Tree-sitter parsing are supplementary checks, not Swift execution.
