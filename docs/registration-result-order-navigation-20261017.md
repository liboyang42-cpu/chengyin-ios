# Registration receipt → owned-order detail

Status: SOURCE_DELIVERED_UNVERIFIED / NOT_RUN. Base `df85c8189810f0462992b1a1f75e57a99387dddc`. Backend control snapshot `60064301f61a72103e094cd9e5ec305bfe784b85`; no deployment or capability activation is implied.

## User flow

The existing activity registration form retains a known creation response and offers a separate explicit status read. It now also offers “Order details” when an independently configured owned-order reader is available. Close returns to the original form; detail can retry its existing read. No status read, payment, new registration or automatic navigation is triggered by this addition.

The continuation is not labelled registration/payment success. Zero payable amount, missing payment parameters, unknown payment status and conflicting status facts keep their existing meanings. An unknown create response cannot offer this route. Missing ticket identity fails closed. A durable-only unknown creation lock does not gain a guessed destination.

## Identity and authority

- Destination ID comes only from the current coordinator's known create response, correlated to the exact retained request ID. The form activity must equal the immutable submitted activity; ticket identity comes from that intent. No activity, team or merchant registration ID is substituted.
- Form account/full identity and a fresh opening UUID fence the destination. Leave/reopen and background retirement invalidate old presentations while preserving the operation lock. Reopening can offer a fresh continuation for a still-known response; it cannot recreate registration.
- The button captures the independent owned-order reader identity and rejects changes at activation. Every detail presentation has a unique UUID, so close/reopen of the same result cannot revive an old uncancelled reader. Presentation freezes that identity; reconstruction cannot adopt a replacement read grant. Neither waitlist nor creation permission grants order reading.
- `RegistrationResultOrderReader` permits only exact order lookup. It verifies order ID, member ID, ownerType 2, activity ID and ticket ID after reading. Missing/mismatched fields fail closed. Late success/error after retirement, cancellation or lost configuration is discarded. Adjacent `ProfileReading` methods reject.
- Existing `ProfileOrderDetailView` receives no lifecycleCoordinator, ticketReader or external-map injection. Payment/cancel/refund lifecycle navigation requires the absent coordinator. The result reader has no mutation protocol. The existing completion provider is object-identity-bound and cannot attach another reader's capability to this adapter.

Original waitlist CLAIMED/CONVERTED continuation is unchanged. No HTTP field, route, approval selector, journal operation, payment API or backend source is added. `SessionRegistrationSheet` already supplies `session.ownedOrderReader`; independent approval remains required and defaults stay unchanged.

## Files and authored regression coverage

- `Core/RegistrationUIFlow.swift`: result navigation visit retirement, independent of create/status state.
- `Core/RegistrationWaitlistOrderDestination.swift`: separate result destination, presentation and restricted reader; waitlist definitions unchanged.
- `App/RegistrationSheetView.swift`: explicit continuation and stale/scene guards.
- `App/RegistrationWaitlistOrderSheet.swift`: separate dismissible read-only sheet.
- `Tests/CoreTests/RegistrationWaitlistOrderDestinationTests.swift`: eleven added tests for known response/repeat read, unknown create/missing ticket, wrong activity, background/leave/reopen, session and independent read identity, wrong request/configuration, ownership tuple, replacement grant, late success/error, uncancelled close/reopen, cancellation and adjacent-method denial. Existing waitlist tests remain intact.

Production files are already registered in Xcode. The regression file is in the Swift Package test target. Existing localization keys are reused. No project generation or new test entry was needed.

## Verification limits

Exact original Git blobs were checked and a source diff inspected. No tests, parser, build, simulator, App, CI, business request, payment or deployment ran. Swift type checking, XCTest, SwiftUI presentation/dismiss/reopen, VoiceOver/Dynamic Type, physical devices and real-service acceptance are all NOT_RUN. Authored tests and static inspection are not runtime acceptance.
