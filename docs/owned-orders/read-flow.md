# Bounded owned-order read flow

Reconstructed after the workspace reset on native base bcd754bd41dd41b3dad22a436211cd89ee47b657 / tree 302035c74d787b560d9051fcf924159006f4ec3d. This is a new implementation packet with fresh hashes and checks, not a claim that the lost 0d25762/tree69a17de bytes or test logs were recovered.

## What works in this source slice

Normal Account → existing ProfileOrdersView → fresh ProfileOrderDetailView uses AppSession and CompositionHTTPTransport. A row's ID drives a new detail request; list data is never promoted to a current detail. The observed-session wrapper retires private views when account/session/viewer/approval identity changes. It supplies no OrderLifecycle action coordinator or external-map provider. Other existing Profile destinations retain their previous default wiring.

Only two exact request shapes are granted:
- POST api/registration/list with canonical multipart containing only owner_type=3.
- POST api/registration/info with canonical multipart containing only one canonical positive id.

Query/fragment, body streams, alternative method/encoding, duplicate/mixed/extra fields, member IDs, status/is_online subsets and invented page/cursor fields are rejected. The source list has pagination disabled. Owned reads require code200/data.rows/data.total, total equal to all returned rows, unique positive IDs and memberId equal to the current account for every row. Detail correlates both requested order ID and member ID. Missing/mixed-owner/incomplete responses fail closed. Explicit empty table/total0 is the empty state. Legacy ProfileService callers keep their pre-existing permissive envelope path; only the owned reader enables the strict expected-owner path.

## Authority and task lifetime

OwnedOrderReadApproval is a distinct CN-only, at-most-24-hour observable lease; root selection defaults to nil. No login, role, display amount, remote flag or other read approval creates it. Issuers must retain an issued lease, explicitly revoke it before removing/replacing it, and create a fresh revision to reissue. A revoked lease cannot revive. The native launch configuration remains unchanged/unconfigured.

Each lease schedules its own expiry notification. The expiry task recomputes the remaining delay from the absolute deadline when its MainActor turn begins, so late scheduling cannot restart the original lease duration. Explicit revocation or expiry changes observable state, which the normal screen reads through the current reader identity. An already-loaded, otherwise-idle private page therefore invalidates without waiting for a user refresh. Date checks at every dispatch/completion remain authoritative even before a scheduled expiry task runs or after background suspension. Foreground/test expireIfNeeded is irreversible and never renews a lease.

Every initial load, toolbar/button retry and pull refresh is owned by the existing actual-task owner; replacement/disappearance cancels the underlying reader Task. UI generations independently prevent stale painting, preserving the list NavigationLink snapshot while its child is pushed. Complete identity, credential bytes, viewer revision, realm, epoch and approval issuance are fenced before dispatch and after both success/error. Current HTTP/envelope401 expires the current session. Late, canceled, dismissed, superseded, revoked, expired or account/role/session/approval-ABA responses cannot expire a replacement session. Current403/business errors remain errors.

## Money and state fidelity

Registration/payment/verification, refund application/payout, and returned points remain independent. Registration2 is not payment success. Payment0/1/2/3/4 are pending/processing/paid/failed/refunded; raw codes remain visible. Refund payout0 is processing,1 confirmed original-channel refund,2 pending manual,3 pending second verification,4 manual refund verified,5 queued,6 dispatching. Unknown codes stay unknown.

pointUsed is a count. pointDeductAmount, pointPaymentAmount, wechatPaymentAmount, payableAmount and refundAmount are monetary values; they may exist while payment is pending. They are never added or converted. Missing values do not become zero. Fractional refund status codes and money strings are rejected. Point return status remains distinct from cash payout. Server prose and masked detail phone stay verbatim.

Money rendering uses Decimal → NSDecimalNumber.stringValue directly. There is no NumberFormatter, Double conversion, two-decimal rounding, inferred FX or point conversion. Authored tests include values beyond the exact-integer range of Double and many decimal places. The CN source describes yuan-denominated amounts, but the wire lacks an explicit per-order currency; the existing currency-unconfirmed label remains instead of inferring currency from locale.

## Backend activation blocker: ownership invariant

Exact inspected backend PR1189 commit36f9012761ec3b6d170c3f5b39d7c554a4c09ac5 / treed2fee9396c577515272aef1764ae6274dcaaa3ea:
- ApiRegistrationController.java c74387b2fdb7e7295bd6215d2f739bb8ad0e2be7
- CmsRegistrationMapper.xml 9c234582c2c60f9fb5dd154f2c6d65698b73e69a
- CmsRegistrationServiceImpl.java f98a49f59d16ebd44a43ca5950eab3b397178d8d
- BaseController.java a98f981ca9a3ea2b6a1139c919adb3b893ae8d98
- OwnershipUtils.java 3d7710d9247c6196ee5cb111747826783f15748b

The list derives member ID from the authenticated nested AppUser, but does not reject null before passing its query to the mapper. The mapper omits the member_id predicate for null. With owner_type3 and omitted filters, this can become an unfiltered ledger query for a malformed authenticated principal. The normal valid-owner path has a server owner predicate; client positive IDs and mixed-owner response checks are only defense in depth and cannot repair the null path. /info has a positive-ID comparison (null fails via caught unboxing) and rejects unknown/mismatched owners before enrichment.

A separate backend guard packet is being reconstructed/reviewed. No fixed/deployed backend is asserted here. Production issuance remains blocked until independent backend acceptance and exact deployed-source verification. No private backend implementation has been copied into this native repository.

## Verification limits

Fresh local evidence: Python contracts, deterministic project/scaffold and touched-file Tree-sitter parsing only; see the separate packet manifest for exact totals/hashes. Authored Core/App/XCUITests cover exact routes, owner/table correlation, decimals, observable revocation/expiry, normal Account/list/detail navigation, no grant/guest, errors/empty, current/late401, restoration, cancellation/ABA and no monetary dispatch. Swift compiler/typechecking, XCTest, XCUITest, simulator/device, accessibility and live API/provider acceptance remain UNRUN locally. Old pre-reset execution claims are not reused as fresh proof.

No create/payment/cancel/refund/redemption/purchase/provider/credential grant, real API, upload, deployment or archive is added. This is read-only wiring, not completed registration/payment or release acceptance.
