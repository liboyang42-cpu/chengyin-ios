# Native order lifecycle and redemption boundaries

## Implemented and integrated

Profile order detail and ticket-wallet detail link to the new native order lifecycle screen without replacing existing contact, schedule or ticket detail fields. The session owns the reader/coordinator; the default command path is disabled. DEBUG fixtures have their own root, never construct `AppSession`, and contain only synthetic order/entitlement IDs and names.

- Fresh `/api/registration/info` projection includes explicit payment/registration/verification dimensions; refund-application presence, review/payout status and amount; manual after-sales status; owner timing; and owner member/team eligibility fields
- Source detail summary and timeline precedence, including manual after-sales, payout 1/4 only as refunded, rejected/zero-value refund fallback, paymentStatus-only paid timeline, expired registrations and China Standard Time timestamps
- Native bilingual detail, status, progress and refund sections; separate cancellation/refund/payment review sheets; absolute review expiry; explicit unavailable confirmation in production
- Read-only bounded payment reconciliation defaults: 1.5-second intervals, 5-second request budget, 20-second total monotonic deadline. A transport ignoring cancellation cannot publish a late result or keep the caller beyond the deadline
- Registration accepted and cash payment settled are distinct, even though Flutter's verifier calls either condition success. Provider success/cancel/failure is deliberately not accepted as a settlement verdict
- Ticket pass availability/expiry metadata, no live code, token, image URL or QR credential in native UI. Coupon status read and issuance metadata keep missing status/expiry unknown
- Chapter/station three-way verification receipt preview. Choice-bearing business-error envelopes remain choices, not success; authentication/authorization failures win first. Station selection requires registrationMerchantId rather than a generic station ID
- Exact dormant request builders and a fake-transport-only DEBUG adapter for cancel, cancel-refund, pay/app, dynamic ticket/coupon issuance, dynamic/legacy/coupon verification and chapter/station verification. Normal adapter initialization rejects all dispatch before transport. AppSession never constructs this adapter

## Source contracts and intentional differences

Evidence is the retained Flutter checkout at `app-audit/lib`:

| Source | Contract |
| --- | --- |
| data/models/activity.dart, RegistrationDetail | Exact owned registration ID, owner ID/type, activity-before-topic precedence, payment and refund fields, teamMode/teamMaxMembers |
| feature/orders/order_timeline.dart | Manual case → refund → registration → verification → policy → schedule precedence; no refund inferred from cancellation |
| feature/orders/payment_verifier.dart | Bounded readback, unknown after timeout/abort, server status required |
| data/api/activity_api.dart | cancel-refund for registrationStatus 2; cancel for unpaid; forms use id. Dynamic issue uses registrationId and server-derived dynamic verification type |
| data/api/coupon_api.dart | qr-token/status use couponHistoryId; verification forwards captured code; 410 means unavailable |
| data/models/scan_result.dart; data/api/registration_api.dart | Choice flags before business-code success; chapterId vs registrationMerchantId |
| feature/tickets/pass_page.dart | Absolute expiresAt, not local TTL countdown, is the expiry authority |
| feature/payment/wechat_payment.dart | All seven provider fields required; timeStamp > 0; no default signature/package value |

Intentional conservative differences: missing payment/verification/refundability cannot enable review; station.id is never substituted for registrationMerchantId; device location never grants redemption eligibility. Explicit ISO offsets are respected instead of rewriting an offset-bearing timestamp to China wall-clock. Unknown provider/configuration/authentication/authorization paths remain disabled. No endpoint, signature, status, provider payment, refund-success promise or server idempotency key is invented.

## Review, session and uncertainty

Reviews are immutable copies of the exact freshly read order, scoped to account plus session UUID, and expire 60 seconds after the read. Refresh, background, sign-out, same-account credential/epoch replacement and changed order target invalidate review. Confirmation compares the current order, target, scope, account and expiry. Source cancellation has no verified requestId contract: the local attempt UUID is never sent.

The default coordinator cannot dispatch. DEBUG simulation installs an account/order lock before suspension. Cancellation, timeout, stale session or unusable response stays outcome-unknown; dismissal, refresh and same-account relogin do not erase it. A received cancellation response retains independent cancellation/cash/points dimensions and does not locally rewrite the order. Locks are memory-only and therefore are not sufficient for production financial enablement; durable, deployment-scoped reconciliation is still required.

Read responses and 401 callbacks compare full current session identity/epoch/token. Old 401s cannot sign out a replacement session. Order views also pass the exact displayed registration ID into review preparation, preventing another surface's current order from becoming the reviewed target.

## Team integration

`OrderLifecycleDetail.teamCreationSource` preserves registrationID alongside `TeamCreationContext`. It requires ownerType 2, positive ownerId, registrationStatus 2, teamMode 2 and a nonempty activity title, retaining nullable teamMaxMembers. It supplies data only and grants no mutation permission. Future team adapters must reread this exact owned registration, verify the current session, then compare ownerID/context. Existing production TeamReadOnlyService.creationContext remains unavailable; no arbitrary activity ID is used to infer eligibility.

## Remaining gates

This is an integrated native read/review slice, not end-to-end production parity. Payment SDK registration/callback verification, production capabilities, live refund/cancellation/issuance/redemption, fresh server authorization and merchant role/candidate binding, durable financial journals, actual QR secure-display lifecycle, coupon auto-refresh UI, merchant continuous scanning, consent and complete after-sales/team entry parity remain unverified or unavailable. No real backend, provider, camera, location, external link, financial or redemption action was performed.

## Integration instructions

Owned Swift files are copied into Core/App/Tests, with UI tests in Tests/AppUITests. Merge only `orderLifecycle.*` entries from the fragment into Localizable.xcstrings. AppSession must retain the reader/coordinator and pass it through ProfileAccountLinks/ProfileOrdersView/ProfileOrderDetailView and TicketWalletView/TicketWalletDetailView. Maintain the exact existing session equality callback. The DEBUG `--uitesting-order-lifecycle-fixture` path must appear in both root routing and AppSessionContainer exclusion. Regenerate the Xcode project and exhaustive six-shard UI inventory after any file changes.
