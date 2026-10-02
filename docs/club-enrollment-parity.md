# Native club enrollment packet

## Added slice

The dedicated club-wide enrollment screen uses the existing topics and registrations readers. Teams expand lazily into ticket groups and registrants; optional topic focus expands the requested team without filtering others. It shows server ticket labels, capacity, signup/paid counts, refundable-count availability, deadline, and explicit unknown/pending/checked-in states. Registrant profiles use the existing public-profile screen; checkin links use the existing club-scoped checkin reader.

Both list and nested receipts are account-epoch/generation scoped. Permission loss clears private rows. Ordinary refresh failures retain visibly stale data. Refresh reloads every expanded roster and discards collapsed caches so a return from checkin cannot silently show pre-action rows. Duplicate identities, malformed nested lists and cross-club/topic responses are rejected.

Refundable count is descriptive only. Missing payment/checkin evidence produces an unknown count instead of an invented zero or permission. Group status is a source label only; no retired formation-progress engine is introduced.

## Source proof (read-only inspection, 2026-10-02)

Paths below refer to the separately supplied source checkouts; no source implementation is included in this packet.

- Mini `pages/club/enroll/index.js:46–49,279–299,327–347`: focused topic, all teams retained, lazy JSON roster reads
- Mini `pages/club/enroll/index.js:363–402`: ticket fields, paid/refundable summary, deadline; `:378–384` preserves unknown checkin status
- Mini `pages/club/enroll/index.wxml:34–80`: expandable team/ticket hierarchy and profile/checkin destinations
- Mini `pages/club/enroll/index.js:67–70,435–454`: return refresh and scoped checkin/profile navigation
- Mini `pages/club/enroll/index.js:244–250,460–474`: permission failure clears private snapshots
- Backend `ApiClubController.java:1213–1255`: club topics include paid theme and session registration counts
- Backend `ApiClubController.java:1364–1384`: authenticated owner/admin roster read and club/topic ownership checks
- Backend `ApiClubController.java:1385–1450`: theme and session tickets, with server-generated session labels preserved
- Backend `ApiClubController.java:1452–1487`: whitelist ticket/registrant fields plus clubId/topicId/canRefund
- Backend `ClubRegistrationRosterVO.java:22–29`: ticket mode is an integer

## Intentional differences and remaining gap

Current mini moved refund controls out of roster rows to checkin detail (`enroll/index.wxml:73–80`, `checkin-detail/index.wxml:77–90`). Flutter still has an obsolete inline control (`club_enroll_page.dart:751–759`) and defaults missing verification status to pending. The native packet follows the current mini boundary and preserves unknowns.

The source permits null registration lists as empty; malformed non-list values are rejected. Count metadata absent from topics remains unknown. For a paid row with unknown checkin state, refundable count also remains unknown rather than assuming it is refundable.

The native checkin view remains the existing generic fact presentation. This packet does not add cancellation execution, a refund review contract, payment-provider code, or new financial authorization. Full refund parity needs a separate source-backed owner-only cancellation/review/receipt/reconciliation slice: form POST `api/registration/cancel-by-owner` with registration `id`, fresh server `canRefund`, distinct acknowledged/manual-review/unknown outcomes, and no resubmission after ambiguous receipts. These facts are supported by mini `checkin-detail/index.js:80–91,111–172` and backend `ApiRegistrationController.java:371–392`.

## Integration

Merge the additive `Resources/ClubEnrollmentLocalizations.fragment.json` entries into the catalog, rejecting conflicting existing keys. Do not replace the catalog wholesale. Run `tools/generate_project.py` after integrating all packets. The packet contains exact small hooks for governance entry/topic routes, the governance context, ClubDetailView, and the AppSession profile-reader factory; apply those hunks against their recorded preimages rather than replacing concurrently edited files.

## Validation scope

Offline Python contracts and structural project checks are recorded in `club-enrollment-verification/`. Authored XCTest domain cases and XCUITest flows are not evidence of execution. Swift, Xcode, simulator, visual/accessibility acceptance, real accounts and backend requests were not run in this environment. No backend or financial mutations, uploads, or publication were performed.
