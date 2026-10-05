# Ordinary legacy order lifecycle production path

This packet implements the source path; it grants no live authority. The ordinary app is
still OFF unless its composition root injects an explicit `OrderLifecycleProductionConfiguration`.
There are no production values, credentials, merchant IDs, legal versions or backend URLs
in this packet. The old dormant/DEBUG adapter remains unchanged.

## Scope and contract

- Ordinary existing registration orders only. `POST api/registration/info` reads the exact
  order. `cancel` and `cancel-refund` are independent per-order financial approvals, each
  sending multipart `id` only. No quote, requestId, owner-refund or invented retry endpoint
  is added. An acknowledgment without `data` is not a cancellation or payout assertion.
- Continue-payment uses the existing `pay/app` multipart builder, seven source provider
  fields, `TopicSelfPlayPaymentProviding`, the pending WeChat SDK bridge, and
  `PaymentProviderReturnFlow`/`OrderPaymentVerifier`. An SDK return never settles payment.
- Reviews also bind the current order-reader scope. A new dispatcher after same-account
  relogin cannot reuse an old review, even if the server detail is unchanged.
- Full immutable order projection equality is the available version check. The audited
  read contract has no version/ETag, so the client does not fabricate one. Server-side
  eligibility remains authoritative. The client rechecks status, owner IDs, amount,
  payment expiry and any supplied refund deadline before mutation and before SDK launch.
- Payment also checks the independently supplied current signup-sharing document URL and
  version against its exact approval, and the authenticated latest `AGREE` consent for
  `activity_host_data_sharing` / `activity_signup`. It reads again after awaited journal
  reservation and before provider invocation. It never accepts or writes legal consent.
  Cancellation/refund have no extra consent route in this source contract.
- One atomic file journal binds origin + CN market + namespace + account + order. Attempts
  are monotonic, across process relaunch, account changes and sheet dismissal. HTTP errors,
  malformed responses, business rejection, SDK cancellation and timeout do not unlock a
  retry. Server-confirmed paymentStatus=2 AND registrationStatus=2 may mark the existing
  payment record observed-paid; history is kept, another payment stays blocked, and only
  a separately approved refund can subsequently reserve that order. Registration acceptance
  alone never releases the lock.
- The journal is process-serialized on MainActor. Do not independently dispatch these
  actions from an app extension or second process using the same file. Corrupt journals
  fail closed and are not silently reset.
- An existing topic self-play journal owns its order. This ordinary path deliberately
  refuses that topic while any self-play record exists, including an unknown create.
  Use that retained flow's own recovery path; never erase its marker or create an alternate
  payment entry. Ordinary work and self-play share the same operation gate and SDK adapter.
- All final transport entries recheck context/cancellation/visibility and the exact request
  method, origin/path, authorization token, multipart boundary/body and active reservation.
  No public dispatch method can omit the journal or bypass its atomic reservation.
- App backgrounding before provider launch invalidates a review and prevents dispatch.
  During an already launched provider wait, the SDK round-trip may take the foreground;
  readback remains available after returning even if the short review deadline elapsed.
  Account/context changes still invalidate it. Dismissal never clears durable locks.

## Dependencies and integration order

Apply after integration56 payment04–07 (including the journal dispatch fences). This packet
reuses their Core types, `PaymentProviderReturnSheet`, the one retained WeChat driver/adapter,
and `selfPlayOperationGate`; it does not duplicate those files. It makes no changes to
registration creation, waitlists, owner refunds, banks, vouchers or pass issuance.

The packet has frozen-base hunks for AppSession and NativeRuntimeDependencies. On the pending
integration56 tree, use the explicit `integration56-native-dependencies.patch` instead of the
frozen NativeRuntimeDependencies hunk to preserve nativePlatform and payment dependency fields.
Apply the small `integration56-wechat-host.patch` after the AppSession hunk: it permits the
same SDK bridge when either existing self-play approval or the independent ordinary-order
payment configuration is valid. It does not install any approval.

Merge the five localization entries by key from the separate catalog fragment. Never replace
the full catalog. Regenerate the Xcode project only in the parent's integration checkout.

## External configuration checklist, all required before enabling live actions

1. Verify the currently deployed CN source contract independently, including ownership,
   payment expiry, eligibility, actual refund channels and independent cancellation/cash/
   points outcome fields. Bind the audited source revision. US remains unsupported.
2. Preserve the existing approved regional backend registry, authentication and legal gates.
   Configure the exact HTTPS origin/base path, namespace, authenticated account, and role.
   No wildcard or endpoint-only approval grants permission for an order.
3. Supply individual `OrderLifecycleOrderApproval` rows with exact registration ID,
   ownerType, ownerId, action and a finite expiry. Approve cancel and refund separately;
   approve payment separately. Keep amounts/status from fresh server snapshots, not UI input.
4. Use the existing ephemeral, no-cookie, no-redirect, non-retrying `URLSessionTransport`,
   or an independently approved transport with the same single-send behavior. Do not put
   retries or queued background mutation replay below the final context fence.
5. Provide an app-writable durable safety directory and one retained journal. Do not reset
   it on logout, role changes, relaunch or errors. Protect it according to the app's approved
   storage policy. Unknown locks need support/read-only reconciliation, not an automatic retry.
6. For payment, independently approve external-checkout product/storefront policy and device
   payment. Supply the current official signup notice provider and exact version/HTTPS URL;
   the user's latest server consent must already match. Missing/revoked/stale consent blocks
   payment and must be handled by the separately authorized consent experience.
7. Supply the existing WeChat SDK payment configuration, approved appID, merchant allowlist,
   universal link, URL routing, entitlements and supported physical-device installation.
   Auth/payment appID and universal link must agree. Use one shared adapter/operation gate;
   no SDK setup is inferred from having a backend URL or an order approval.
8. Run the ordinary fake HTTP Swift tests in both Debug and Release, full Core tests,
   unsigned CN/US app builds and hosted UI tests. Exercise double taps, stale sheets,
   account/role/namespace/token changes at every await, app switch/return, provider cancel/
   timeout/late callbacks, missing consent and transport uncertainty. Then separately validate
   source ownership/eligibility, legal policy, real device SDK, sandbox merchant and server
   readback. This packet's static checks are not that acceptance.

## Verification limits

The authoring environment has no Swift/Xcode executable or Apple SDK. Twenty-two ordinary
fake-HTTP tests are authored without DEBUG guards but NOT_RUN. Tree-sitter parsing and Python
contract assertions are supplementary source checks only. No real backend, account, payment,
refund, SDK device, legal acceptance, grant change, publication or production service was used.
