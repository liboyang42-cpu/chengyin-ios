# Waitlist order navigation

Current mini checkout exposes order-detail navigation in both CLAIMED and CONVERTED states. Its handler uses the status response's registrationId, not a new claim or order. The native form now provides the corresponding explicit order-detail action and a dismissible read-only sheet.

The destination binds the authoritative status to account/session, activity, ticket and exact order ID. The tap separately freezes the existing owned-order reader's full identity, including viewer and approval revision. Rebuilding the sheet cannot attach a replacement approval to that old destination. Scope/session replacement invalidates the route, and the read-only detail subtree is keyed by live fenced identity to mask old state. Before displaying an order, the adapter validates exact order, member, ownerType=2, activity and ticket identity. Missing or mismatched fields fail closed. Errors permit read retry; dismissal returns to the registration form.

Production injects session.ownedOrderReader, never the participant reader. No new grant or endpoint is issued, no lifecycle/payment coordinator is injected, and the independently gated owned-order approval remains required. CLAIMED/CONVERTED also block replacement registration even when inventory reappears. Navigation does not mutate durable locks, retained intent, unknown-write state, payment reconciliation or waitlist state. Converted status does not synthesize a paid order.

## Source evidence

Inspected private backend/mini source at immutable 0bf8a3b13e601a82ed8b4902d775a6ed290bc26b. No private source bytes are included in this native patch.

- Mini checkout WXML CLAIMED/CONVERTED states both expose goWaitlistOrder.
- Mini checkout JavaScript goWaitlistOrder passes the exact waitlistRegistrationId to the existing order-detail page.
- ClubWaitlistEntry includes activityId/ticketId/memberId/registrationId; ClubWaitlistServiceImpl binds the consumed offer to its registration and converts by that registration.
- Existing registration info returns CmsRegistration with owner/member/ticket fields; activity registration has ownerType 2.

## Verification limits

Synthetic core tests cover route filtering, invalid IDs, owner/activity/ticket mismatches, no grant, session/epoch/viewer/approval changes, late success/error, cancellation, reissued-grant reconstruction, and no replacement creation. New synthetic UI tests cover both states/languages, close/reopen, and failed read/retry. Python checks and supplementary parsing are offline structural evidence only. This Linux workspace has no Swift/Apple compiler or simulator: XCTest/XCUITest, real device rendering, live backend and payment-provider execution remain unrun. No production calls, writes or publication were performed.
