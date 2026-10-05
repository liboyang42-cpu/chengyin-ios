# Registration networking service

Reviewed 2026-10-01 against the retained Flutter client. This slice adds an unwired, dependency-injected native service and synthetic transport tests. It does not configure a service host or make a live quote, order, payment, or status request.

## Verified client-source contract

| Operation | Source | Native request |
| --- | --- | --- |
| Quote | `lib/data/api/activity_api.dart`, `ActivityApi.quote` | `POST /api/registration/quote`, JSON |
| Create | Same file, `ActivityApi.createRegistration` | `POST /api/registration/create`, JSON |
| Known-order readback | Same file, `ActivityApi.ticketInfo` | `POST /api/registration/info`, multipart form with string `id` |
| Readback fields | `lib/data/models/activity.dart`, `RegistrationDetail.fromJson` | Numeric `id`, optional numeric `registrationStatus`, `paymentStatus`, `verificationStatus`, optional `registrationNo` |
| Authentication | `lib/core/network/dio_client.dart`, request interceptor | Raw token in `Authorization`; no added `Bearer` prefix |

The service uses the existing `RegistrationQuoteRequest` and `RegistrationCreateIntent` encoders unchanged. Quote sends only `ownerType: 2`, `ownerId`, optional `ticketId`, and integer `isUsePoint`. Create sends the retained intent's exact selection, participant fields, opaque `quoteSign`, `requestId`, optional `payChannel: "APP"`, paired waitlist offer fields, and nonempty optional email/date. No fields, alternate routes, or payment-provider requests are invented. The configured gateway path is preserved when appending each source endpoint.

Evidence is the retained client implementation and its models, not an inspected server implementation or a live-service acceptance test. The Flutter source remains untouched.

## API and boundaries

- `quote(_:token:)` returns the source-shaped `RegistrationQuote`
- `create(_:token:)` returns `RegistrationCreateResult`; it never invokes quote, payment, or readback on the caller's behalf
- `readStatus(registrationID:token:)` makes one explicit request for a known registration ID, returning a narrow `RegistrationStatusSnapshot`. The returned positive ID must match the requested ID. Missing/null statuses stay nil; unknown numeric statuses remain raw values. Malformed identity or status types fail closed
- All operations require a nonblank, header-safe token and use the existing validator. Tokens are passed through unchanged and never stored by this service
- JSON requests set `Content-Type` and `Accept` to `application/json`; readback reuses the existing multipart builder. All requests use the existing 20-second request timeout and cache-bypass policy
- Cancellation and transport errors propagate unchanged. Cancellation is checked immediately before and after transport. The service sends at most one request per method invocation; it never refreshes credentials or retries
- Use the existing `URLSessionTransport` for actual transport. Its ephemeral session disables cookies/caching and its redirect delegate rejects redirects. This service rejects every non-2xx HTTP status, including redirects; injected transports must uphold the same no-redirect/no-retry contract. The `HTTPTransport` abstraction cannot prevent a custom implementation from following redirects internally
- No default transport, configured host, UI connection, account access, consent submission, SDK integration, persistent storage, or remote action is added

## Error preservation

For a 2xx HTTP response, the existing registration envelope decoder requires numeric `code: 200` and decodable object data. Business failures propagate as `RegistrationResponseFailure`, retaining parsed numeric/string codes and an optional server-owned message. An empty message is different from no supplied message. Malformed success payloads become `APIError.malformedResponse`; they do not become zero-cost orders or empty successful state.

Every non-2xx HTTP response throws `RegistrationHTTPFailure` with its `statusCode` and any parseable code/message in `response`, including HTTP 401. It does not discard an error envelope just because its `data` is malformed. A non-JSON response still retains HTTP status. A contradictory HTTP failure with `code: 200` remains an HTTP failure. Unknown nonnumeric codes yield nil, consistent with the existing registration failure contract; no server message or translated fallback is invented.

A future caller must handle HTTP authorization denial through `RegistrationHTTPFailure.statusCode == 401`, and business authorization denial through `RegistrationResponseFailure.code == 401`, while applying the existing account/session isolation rules. The service itself never logs out, clears credentials, routes by message text, or treats an error as permission to recreate an order. No raw response body or participant data is logged.

## Idempotency and readback limits

`create` only accepts a prebuilt immutable intent. It encodes the same request ID, opaque signature, waitlist token, and participant/selection data on every explicit invocation. Sorted JSON keys also make byte-level request comparison stable. The service never creates a new intent or request ID, including after timeout, cancellation, 409, 410, malformed response, or an HTTP failure.

A failed or cancelled create call can have committed an order on the server. Retain the exact original intent and account association until that outcome is resolved. Do not interpret a transport error as proof that no order exists. No automatic retry is implemented, even with the same key.

The readback endpoint and its raw status fields are source-verified. It is a single-request primitive, not a payment verifier. The Flutter `RegistrationPaymentVerifier` contains status precedence/polling behavior, but this slice deliberately does not introduce that policy. Create results with missing payment parameters, zero amount, or an idempotent replay are returned without declaring payment or registration success.

Readback requires an already-known registration ID. No lookup-by-requestId route is verified here, so this service alone cannot reconcile a create timeout that returned no ID. Order-list reconciliation, secure intent persistence/restoration, matching an order to the retained intent, account/session/race isolation, quote freshness, signup-data-sharing consent, deadline handling, payment orchestration, and recovery UI remain separate work. A raw readback snapshot does not by itself prove that a different signed-in account owns the caller's retained intent.

## Synthetic verification

`Tests/CoreTests/RegistrationServiceTests.swift` adds 25 XCTest cases covering:

- Exact JSON endpoint, source body keys/omissions, APP-channel option, paired offer fields, unchanged signatures/tokens, gateway prefix and raw authorization
- The same intent/body across explicit invocations, timeout propagation without automatic retry/re-quote/key replacement, transport cancellation, and invalid-token rejection before send
- Numeric/string business errors, missing/empty/opaque messages, HTTP envelope preservation including 401 and malformed error `data`, non-JSON HTTP failures, and 3xx rejection without another service request
- Malformed success data, unusable incomplete quotes, free/unknown/replay/payment-parameter create variants without automatic follow-on operations
- Exact multipart readback ID, requested/returned ID matching, missing/null/unknown statuses, malformed identity/status rejection, business read failures, and invalid readback IDs

Every fixture transport returns local strings/errors and records requests only. It never creates a session or opens a socket. The tests do not prove real URLSession redirect behavior, backend idempotency, payment-provider acceptance, account ownership, or production operation.

Local static review and whitespace checks passed in the Linux workspace. Swift is not installed there, so compilation and XCTest execution remain pending cloud CI verification. No live backend operation was performed.
