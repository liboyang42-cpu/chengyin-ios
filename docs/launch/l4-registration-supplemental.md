# L4 registration supplemental reads

Source-only client adapter for three existing public backend routes. This is not
launch acceptance, a payment capability, or a replacement for original-order recovery.

## Fixed public sources

- iOS base: `0a56746aca42158dda20c821a1d50f089f0d5ae8`.
- Backend reference: `liboyang42-cpu/hengyin` at
  `c6eac3b8cebf7311e8f00f208d294c3c8212aaec`.
- `chengyinhub-admin/src/main/java/com/chengyinhub/web/controller/api/ApiRegistrationController.java`:
  `paymentReadiness`, `getJoinRegistrationDetail`, `countByDate`.
- `chengyinhub-admin/src/main/java/com/chengyinhub/web/service/registration/RegistrationQueryApplication.java`:
  `getJoinRegistrationDetail`, `countByDate`.
- `chengyinhub-system/src/main/resources/mapper/business/CmsRegistrationMapper.xml`:
  `selectCountGroupByDate`.

## Exact scope

1. `POST api/registration/payment-readiness`, no form fields. Decode the server's
   optional `ready` and `message`; only literal `true` is ready. This is an observation,
   never permission to create an order, launch a payment SDK or charge an account.
2. `POST api/registration/join_info`, no form fields. The backend ignores legacy
   `member_id` and uses the token principal; the client never sends that selector.
   A success envelope without `data`, or with null `data`, means no joined registration.
   An object must decode as an existing order and its top-level buyer must match the
   captured account. The nested activity/topic publisher cannot substitute for buyer.
   This endpoint selects a current registration; it is not an original create receipt
   and cannot settle, clear, or replace an unknown create request.
3. `POST api/registration/count_by_date`, form fields `owner_type` and `owner_id`.
   Owner type 1 means topic and 2 means activity; these are not theme product types.
   The server enforces publisher/club/MerchantPermission rules. The client does not
   infer access from a role string. Preserve `participateDate` and `totalCount` as
   supplied; do not infer capacity, prices or eligibility. Missing, negative or
   malformed counts and duplicate day rows are errors, not zero-filled results.

All methods perform at most one HTTP request, do not retry or mutate, and preserve
business failures before attempting success-data decoding. A retained reader is bound
to the existing runtime context, including account, epoch, token, role, namespace,
market and base URL. Success and failure responses are fenced; stale 401 responses
cannot expire a replacement session. Cancellation/sign-out discards late results.

## Integration boundary

`RegistrationSupplementalReadService` requires an explicit API configuration and an
injected transport. `RegistrationSupplementalSessionReader` requires the captured
existing `RuntimeDependencyContext` and a current-context closure. Keep its service
nil until L2 supplies the approved, already-gated transport for these exact read paths.
No new grant, capability selector, authentication behavior or default configuration
is added here. The session reader is a data-lifetime fence, not server authorization.

L1 must register the three new Core sources in the app target, under its exclusive
ownership of the project and composition files. SwiftPM discovers Core and CoreTests
by their existing directory targets. L2/L1 must choose the normal read integration
after the capability decision; this change deliberately does not edit shared files.
The UI owner decides presentation. No UI copy, layout, navigation or disabled row is
added by this package.

## Verification and outstanding gates

Authored tests: 12 service-level XCTest methods plus 6 session-reader methods, using
injected recording/suspended HTTP transports and reserved example domains only.
Coverage includes exact request shapes, readiness unknown/malformed cases, absent
versus malformed joined orders, buyer isolation, server counts, owner-kind distinction,
business/HTTP failures, zero-dispatch invalid input and session lifetime races.

Swift/XCTest and app compilation are NOT_RUN because this executor has no Swift or
Apple toolchain. CI dispatch is not authorized. On an authorized existing toolchain:

```
swift test --filter RegistrationSupplemental
```

After L1/L2 integration, build the actual app target and verify normal-entry readback
against an approved test backend. Real transactions, production, credentials, money
rules, provider setup, private source and new dependencies are outside this package.
No backend, shared-file, authentication or funds change was made.
