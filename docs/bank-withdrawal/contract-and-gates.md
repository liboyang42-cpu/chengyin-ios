# App bank-card withdrawal contract

Scope: front-end code and synthetic proof tests only. No live bank, card, payment, withdrawal, database, or financial-service actions were performed. The app request supersedes the retired mini-program/Flutter entry policy for this feature. No private implementation, configuration, credentials, or contact details are included here.

## Source-backed contract

Read-only verification used the current backend's withdrawal controller, preflight controller/request/response, bank command service, withdrawal service/domain and preflight policy. The audited Flutter snapshot had removed create/preflight methods; it is not authoritative for the new app requirement. The existing native history's status mapping was corrected against the current backend domain.

| Operation | Request | Response |
| --- | --- | --- |
| POST api/fund/preflight/bank-withdrawal | JSON requestId, amount, realname, bankName, bankAccount, mobilephone | AjaxResult data with challengeId, challengeToken, state, serverTime, expiresAt, expiresInSeconds, question, consequence, riskLevel, canProceed, amount, currency, accountMask, phoneMask, safetyMessages |
| POST api/fund/preflight/{challengeId}/confirm | JSON challengeToken | Same challenge shape; state CONFIRMED; token may be null |
| POST api/fund/preflight/{challengeId}/reject | JSON challengeToken | Same challenge shape; state REJECTED |
| POST api/withdrawal/create | JSON requestId, challengeId, withdrawalAmount, realname, bankName, bankAccount, mobilephone | AjaxResult data: positive numeric application ID |
| POST api/withdrawal/list | Authenticated read; no body required | AjaxResult data list; existing reader also accepts historical rows/list wrappers |

Amounts are decimal CNY; positive, at most 12 integer digits and 2 decimal places. Required name/account fields are at most 64 UTF-16 units, bank name 128, phone 32, requestId 64. No unsupported issuer list, card-number format, phone-country, or financial eligibility rule is added by the client. A UUID is created for the immutable local intent and reused for both preflight and create.

Preflight state is PENDING, CONFIRMED, REJECTED, or CONSUMED. Risk is STATIC, WARNING, or BLOCKED, supplied by the server. The client obeys canProceed and never computes eligibility/risk. Backend role, available-funds/freeze, pending-request, and idempotency checks remain server responsibilities.

The backend currently sets serviceFee to zero and receivedAmount to amount at application creation. The preflight response does not provide a fee quote or arrival estimate. The native review therefore promises neither a quoted fee, final net receipt, nor an arrival date. A positive application ID means accepted for review only, not approved, paid, or arrived. History states: 0 pending review, 1 approved, 2 rejected, 3 paid. Approval must not appear as payout.

## Safety and runtime gates

- BankWithdrawalAdapter defaults enableReviewedWrites=false; grant defaults nil; consent evidence defaults nil. BankWithdrawalView adapter defaults nil. The ordinary app landing and synthetic fixture both pass only the read-only wallet reader.
- A future composition root must separately approve exact deployment/account/path grants, including the concrete dynamic challenge paths. Preparing a challenge does not authorize confirm/create. Both confirm and create grants are checked before confirmation dispatch.
- The backend requires a current AGREE for document bank_account_collection, scene withdrawal. No native bank-document acceptance UI or verified current server document/version is installed by this packet. This is an explicit external integration gate, not a fake checkbox or a claimed consent. Any eventual acceptance flow needs its own reviewed consent integration.
- Immutable review contains every outgoing field and scope. The exact captured authentication token plus deployment/account/epoch is checked before dispatch and after each await. Expiry honors the smaller server TTL/timestamp delta, conservatively measured from request start; confirm/create cannot continue after expiry, cancellation, token change, or scope change.
- Before preflight can dispatch, the existing durable journal stores only operation UUID, deployment/account owner, fixed target, and acknowledged step count. No name, bank/account/phone, amount, challenge token, authentication token, or request/response body is persisted or logged.
- Ambiguous outcomes, malformed receipts, session changes, or interruption preserve the durable account/deployment lock across new epochs and app restart. There is no reset button, automatic replay, fallback payout, or background transaction. History lacks reliable requestId correlation, so it cannot clear an unknown-operation lock just because a superficially similar row appears.
- Explicit rejection can clear the lock only after a matched server REJECTED response. Cancel on the prepared review follows that explicit rejection path. Closing an unsubmitted form makes no request. Background/account/navigation loss clears in-memory PII; if a request was already in flight, its unknown lock remains.
- There is no real-money fixture. Synthetic transport data is confined to XCTest and existing offline read fixtures.

## UX and test boundary

Native form uses masked account/phone entry, a keyboard dismissal control, scroll-to-dismiss keyboard, immutable review sheet, explicit two-step disclosure/confirmation, safe cancel, truthful dormant/errors, accepted-for-review receipt, and existing history. It is reachable from the wallet balance/support landing. The support alternative does not claim bank withdrawal was retired.

Authored: Swift domain tests covering validation/wire binding, closed grants, consent versions/revocation/scope, duplicate/edit/cancel, token/account fencing, expiry, durable unknown restart, status mapping, successful rejection, malformed responses and successful application receipt; plus three bank-related UI cases within WalletCommerceFlowTests. Executed local checks are recorded in the packet validation report. Tree-sitter is syntax-only. Linux has no Swift/Xcode; actual Swift tests, app builds and XCUITest require the publication CI and are not claimed passed here.
