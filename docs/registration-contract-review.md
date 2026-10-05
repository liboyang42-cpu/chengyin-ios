# Registration quote/create contract slice

Reviewed 2026-10-01 against the retained Flutter checkout. This is a pure Swift domain/JSON slice; it adds no networking, UI, actual order, payment SDK, currency conversion, endpoint configuration or US payment support.

## Source evidence

- `lib/data/api/activity_api.dart`, `quote` and `createRegistration`: existing POST JSON operations `/api/registration/quote` and `/api/registration/create`, `ownerType: 2`, optional `ticketId`, integer `isUsePoint`, required `quoteSign`, optional `payChannel: APP`, `requestId`, paired offer fields, optional nonempty email/date
- Same file, `newRequestId` and `RegistrationCheckoutException`: request ID is nonempty and at most 64 characters; non-200 create errors preserve a numeric or string business code and supplied message
- `lib/data/models/activity.dart`, `RegistrationQuote` and `RegistrationCreateResult`: quote uses `payAmount`; create uses `payableAmount`; these are different wire keys. Quote monetary values are numeric/nullable; create amount also accepts numeric strings. Missing/empty `payParams` may be a free-order response or an idempotent replay, and does not establish payment completion
- `lib/feature/activity/activity_detail_page.dart`, `_SignupSheetState`: retain `_requestId` across attempts, obtain separate signup-data-sharing consent before create, re-quote on selection/points changes, and reconcile SDK results against authoritative status. Its no-parameter branch currently presets success; this slice deliberately does not port that unsafe inference for an idempotent replay. Expired/terminal conflicts and changed-price conflicts have different handling even when code 409 is shared
- Regression evidence: `test/data/api/registration_quote_sign_test.dart`, `test/data/api/activity_waitlist_registration_test.dart`, `test/feature/activity/fee_breakdown_null_amount_test.dart`, `test/feature/activity/signup_payment_flow_test.dart`

## Implemented

- `RegistrationQuoteRequest` encodes only the source JSON selection fields; activity ownership stays fixed at 2
- `RegistrationQuote` preserves optional monetary amounts as `Decimal`, including explicit zero. Missing total or blank signature cannot produce a create intent. Deduction is based on positive deduction amount, not points count
- `RegistrationCreateIntent` is immutable and owns a request ID generated once during initialization. Encoding and value copies reuse the same ID and payload. It copies the opaque quote signature unchanged, and uses the retained quote selection's owner/ticket/points values. The supported APP flag is encoded only when requested
- `RegistrationWaitlistOffer` makes half-present offer fields unrepresentable; positive ID and nonblank token are required. Both fields are encoded unchanged together, or omitted together
- `RegistrationCreateResult` handles absent/null/empty parameter bags and source scalar parameters, including numeric timestamps. A nonempty bag is only evidence of parameters, not SDK readiness or payment success. There is deliberately no `isPaid` or free-signup-success inference
- Both source success envelopes require a numeric 200 and object `data`. Business failures retain optional server message and parsed code without inventing localized text or automatic retries

## Deliberate safety checks and remaining gaps

- Compared with Flutter's permissive fallbacks, malformed amounts, negative amounts/points, invalid IDs, nested payment parameter values, and missing create-success IDs are rejected. Numeric strings are accepted only for create amount, matching the source distinction. Numeric-string parsing validates the entire value, avoiding prefix parses such as `19.99USD`; decimal arithmetic never passes through `Double`
- Local signature authenticity/expiry and server correlation cannot be verified from this opaque quote object. Callers must associate the quote with the exact selection and authenticated account. Consent, account/session isolation, quote request races, durable intent restoration, order readback, key replacement after reconciled cancellation/expiry, payment/retry routing and UI remain unimplemented
- Request ID validation uses UTF-16 length at most 64 as a conservative server-string bound; generated IDs are ASCII. Retrying requires retaining the existing intent. A new intent must not be created merely because a request timed out; construction alone cannot enforce persistence or server idempotency
- No country/currency semantics or provider availability are inferred from locale. `*Yuan` names remain the actual source fields. Phone/date format policy, payment completeness and provider integration need separate verified contracts
- Evidence is client source and source tests, not an inspected server implementation or live service. No live quote, registration, payment, refund, SDK callback, simulator or device was exercised

## Verification

Added 26 focused Swift XCTest cases for request keys/omissions, decimal/null/zero behavior, quote readiness, signature passthrough, same-intent retries, new-intent IDs, offer pairing, response variants and failure envelopes. Static whitespace and source review passed in this Linux workspace. There is no installed Swift compiler here: compilation and test execution are **not run**, and must be verified by the integration's native CI. Project regeneration is intentionally left to the integration.
