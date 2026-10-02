# Registration and waitlist composition

Dormant, source-backed implementation. Shipped composition supplies no registration grant or storefront provider; no production calls, orders, consent submissions, payments, or waitlist changes were executed for this work.

## Supported flow

The existing activity registration form now offers an inline sold-out waitlist section. The server alone supplies membership eligibility and NONE / WAITING / OFFERED / CLAIMED / CONVERTED / CANCELLED / EXPIRED status. Status, join and cancel send only activityId/ticketId; authenticated membership is never selected by name or supplied as a body parameter. A joined queue is not an order. A CLAIMED/CONVERTED waitlist state is not a payment verdict.

An available offer remains in the same form. Reviewing it explicitly re-reads current status, binds the exact offer ID/token to the same account/activity/ticket, clears the old confirmation, fetches a fresh quote, and requires renewed review. Quote and create carry the identical pair. One offer means one ticket; there is no quantity or multi-participant offer API. Saved participant selection continues to use exact owned IDs; contact values remain the source-supported create fields.

The server's current offer policy supports up to one day. The old client's two-hour normalization limit is not copied. Offset-bearing deadlines remain absolute; timezone-free yyyy-MM-dd HH:mm:ss uses the backend's Asia/Shanghai configuration, never the device timezone. Local countdown expiry only removes the ability to submit. It does not renew, release or extend server inventory. Server status/transactions remain authoritative.

## Production activation boundary

RegistrationProductionFactory constructs URLSessionTransport rather than accepting a test-only marker or a global enable flag. The independent approval contains exact API base URL, storage namespace, account/session epoch, one activity, explicit ticket IDs, physical-activity product classification, CN market, CHN storefront, legal version/notice URL, permitted API paths and expiry. US/international contact/checkout contracts are not inferred from locale and cannot be activated through this CN grant.

The factory remains off unless the host explicitly injects this approval and an independently obtained current storefront. It cannot infer authority from a configured URL, an account role, a checkbox or a debug transport. Every request repeats the session, scope, origin/path, storefront and expiry checks before dispatch and after suspension.

The approved notice is linked from the form. Explicit agreement uses the existing compliance consent endpoint and confirms the exact signup scene/document version through latest-consent readback. Unknown consent writes are retained and only re-read; they are not resubmitted. Quote and create each verify current server consent. A local review checkbox does not substitute for that receipt.

A quote is locally reviewable for less than 120 seconds. This is a conservative UI recency limit, not a claim about server signature lifetime. The production service retains the exact quote selection/signature and repeats the freshness check immediately before writing. The backend still validates signatures and atomic offer consumption.

## Financial and replay boundaries

- Existing immutable registration request IDs and coordinator account/session fences remain intact
- Durable metadata locks are written before consent/join/cancel/create writes. They contain only scope, opaque local operation identity and an acknowledged numeric row ID; no credential, contact field, offer token, quote signature or payment parameters are stored
- Unknown join/cancel responses require explicit scoped status reconciliation. No automatic retry, background promotion polling, replacement order or offer renewal exists
- Create locks remain after success or uncertainty and survive app restart. The form exposes retained-order readback where an ID was acknowledged; it blocks replacement creation even when no ID is known
- Server create receipt, registration status and payment status remain separate. Zero price, absent payParams, countdown expiry and waitlist conversion never execute a payment SDK or prove payment success
- Closing/backing out scrubs form/offer state and invalidates callbacks. It does not silently leave the queue, release an offer, cancel an order or clear durable locks

## Verification

Synthetic XCTest sources cover contract decoding, exact wire shape, deadline/timezone handling, account/epoch/scope rejection, offer-bound quote/create, explicit legal consent/readback, durable unknown locks, cancellation, expiry between review and confirm, ticket changes, signout and form dismissal. These use in-memory transports only. Authored tests are not a claimed execution pass.

The isolated workspace runs structural/catalog/project checks and supplementary Swift syntax parsing. Apple compilation, XCTest execution, simulator/device accessibility, provider configuration and real-backend acceptance remain separate gates.
