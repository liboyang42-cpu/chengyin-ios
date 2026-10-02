# Ticket, city voucher, coupon and owner-refund runtime composition

This is fresh native Swift implementation, derived from the audited source contracts. It does not copy private backend implementation or signing material. Production approvals remain absent in `NativeRuntimeDependencies.dormant`; there are no deployed endpoint credentials, new financial permissions, redemption calls, device calls or live requests in this change.

## Normal navigation and presentation

- Order lifecycle → entry pass now uses an injected ticket-code coordinator
- Roam → city voucher accepts a positive source POI ID, then opens native code presentation. A POI ID never establishes entitlement. Server issuance remains authoritative, including unpublished POIs with a pending voucher
- Both use a native scrollable presentation, a user-triggered Show code action, locally generated Core Image QR pixels from the exact server response, countdown, retry and background/dismissal cleanup
- QR rendering is independent of the optional server-generated image URL. Native code does not reproduce the older Flutter long-text fallback or count a decorative image as a scannable code
- The signed `v1` response is structurally checked against the request target, server expiry, response type and (for city vouchers) current account. This is not local signature authentication: only the server has the signing key and verifies redemption
- Expiry uses server absolute milliseconds; no guessed TTL or seconds conversion. Ticket expiry clears the code and requires manual retry. City vouchers automatically reissue only upon expiry; an issuance failure stops automatic requests until the user retries
- The view owns a cancellable one-second task. Inactive/background/disappear invalidates in-memory code and pending callbacks. Returning to the view requires a new user action. No code, image or signing secret is persisted, copied to the clipboard, logged or saved to Photos
- Ticket readback uses the existing registration-info route. There is no invented ticket-status endpoint. The native pass deliberately does not interpret `verificationStatus == 1` as fully consumed; a multi-chapter ticket can still be usable
- Ticket readback labels distinguish an active or ended registration and do not claim a successful scan or payment

## Independent approvals

`VerificationCodeApproval`, `CouponCodeApproval` and `ClubOwnerRefundApproval` are separate, composition-only values. The normal AppSession factories consume them without a debug-only UI path. None can be set by Info.plist, UserDefaults, links, launch arguments or server response. All default to nil.

The approval must match CN market, complete deployment URL, namespace and account, plus exact required paths. A captured scoped transport additionally fences role, session epoch and token before/after each request. Gameplay approval does not grant QR issuance or owner refunds. US activation needs separate contract acceptance.

Required paths:

| Flow | Exact source paths |
| --- | --- |
| Ticket | POST `api/verify/dyncode/issue` (`registrationId`), POST `api/registration/info` (`id`) |
| City voucher | POST `api/verify/citynode/issue` (`poiId`) |
| Coupon | POST `api/coupon/qr-token` and `api/coupon/status` (`couponHistoryId`) |
| Owner refund | `api/club/access/me`, `api/club/crm/checkin/detail`, POST `api/registration/cancel-by-owner` (`id`) |

Coupon API requests use the scoped transport. The image fallback requires an exact approved HTTPS origin and the existing ephemeral bounded no-redirect/no-credential image loader. Foreign session responses are rejected, and issuance 401 invalidates only the matching session. A validated server token can still be rendered locally without a media grant.

## Owner refunds

The retained coordinator keeps review/preflight, a fresh server OWNER permission check, exact evidence comparison and two durable locks. It acquires the registration lock and, when present, the exact parent-order hash before send. It retains both after timeouts, malformed replies, HTTP/business rejection, cancellation or uncertain results. No response clears a lock or automatically retries a refund. Registration status, cash refund status and points return remain separate.

Authorization-generation fencing additionally makes a token/role change invalidate a pending review even if its account and epoch happen to match. The coordinator still uses Java ASCII trim semantics (UTF-16 units ≤ U+0020) solely to determine whether the parent order is blank; it hashes the original nonblank bytes unchanged. Persistent files continue containing only opaque keys and `pending`, never review/customer/credential data.

`canDispatchOffline` still identifies only canned fixtures. The independent `canDispatch` property describes an approved client; the normal UI does not label it as a simulation. Default composition uses the read-only fallback and does not send.

## Verification limits

Local checks: 8 new Python contract checks, existing contract regression suite, deterministic project/scaffold and strict supplementary Tree-sitter syntax parsing. New Swift XCTest covers receipt binding, invalid expiry, exact form routes, independent grants, token/role/account changes, duplicate taps, late callbacks, background clearing, multi-chapter readback, expiry policies, coupon media origins and durable refund unknown outcomes. App-hosted tests assert all shipped grants are nil and normal factories remain unavailable.

Swift/Xcode compilation, execution of the authored XCTest and Apple visual/device acceptance must be run by the CI integration owner. This Linux workspace has no Swift compiler or Apple SDK. No simulator screenshots, live business actions or device acceptance are claimed.
