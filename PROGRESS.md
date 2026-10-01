# Native iOS migration progress

Status: migration in progress, not release-ready.

## Working convention

Continue implementation and validation on `migration/native-ios`. Do not open a new PR for every small slice. Open one overall migration PR when the complete scope is implemented and its acceptance evidence is available. Earlier small draft PRs remain historical evidence; closing them does not mean their features are complete or merged into main. The migration branch preserves their commits.

## Last verified code revision

`1860c2880b24e4d82805a9bcb5f2cd5f8ec07a4d`

[Native checks run 36848589415](https://github.com/liboyang42-cpu/chengyin-ios/actions/runs/36848589415)

- 94 Swift unit tests passed
- 6 Python importer tests passed
- 9 iPhone Simulator UI tests passed
- Unsigned simulator Debug and device Release builds passed
- Gitleaks passed

The five entry UI cases cover persisted language switching, repeated player/merchant entry dismissal, unconfigured login blocking, repeated Settings presentation after cold launch, and the scanner's unsupported-Simulator/Cancel path. They do not exercise real credentials, business data, camera recognition or payment.

## Implemented, with limits

- Independent SwiftUI project with iOS17 provisional minimum; English/Chinese resource catalogs and app language preference
- Existing-account password sign-in code, Keychain session storage, bootstrap/logout/cancellation guards; live server and physical Keychain behavior unverified
- Read-only activity client, searchable/paged native list, detail, ticket display, MapKit for valid coordinates and explicit club gate; four isolated offline UI scenarios passed in run 36848589415; visual screenshot review and backend validation remain outstanding
- Registration request/response contracts, quote signature preservation and stable retry identifiers; no order/payment execution
- VisionKit/UIKit scanner component, permission/lifecycle/retry/one-shot-delivery handling; outside production navigation pending a validated business host, and physical-device recognition untested
- Reviewed-key ARB conversion tool; candidate resource conversion is not completed UI translation

## Not yet completed

New-account registration; native Apple/WeChat provider flows; the full original home and primary navigation; roam and game/check-in loops; registration/quote/order/payment/ticket verification/refund UI; merchant and club workflows; messaging/collaboration; remaining source features; full content localization; accessibility/visual/device acceptance; signing and distribution.

No migration percentage is claimed. Source route declarations, resource keys, test counts and compiled files are different measures.

## Next acceptance sequence

1. Add controlled activity and session UI fixtures, screenshots and lifecycle regression coverage
2. Complete a discover → detail → quote → registration/order-status vertical slice with explicit confirmation and authoritative status readback
3. Migrate remaining player, merchant, club and messaging workflows against source contracts
4. Validate using an approved non-production API and purpose-built accounts/data; do not use production data as disposable tests
5. Complete device, privacy/legal, accessibility, asset-license and release checks; release/signing/production changes require separate authorization

## Known verification history

An earlier UI run failed because the test queried a native Picker option as StaticText; another inherited a Picker identifier onto its children. Tests now use the observed native Button labels. A later run lost a synthesized Settings tap; readiness/post-navigation checks and repeated cold-launch coverage were added. One rerun also encountered Xcode simulator launch/DTX failures. These failures remain recorded; subsequent green runs do not erase them or prove universal runtime reliability.

## Activity UI regression follow-up

Run 36846622633 compiled both app configurations and passed the existing five entry UI cases, but all four newly added activity cases failed. The rendered hierarchy exposed an empty detail destination before its loading task started, inherited accessibility identifiers, and scrolling obscured by the keyboard. Concrete state roots, leaf identifiers and unobscured gestures passed all four cases in run 36848589415. These failures are not excluded or relabeled as passing.

Registration networking now includes source-aligned quote/create and one explicit known-ID status readback, with 25 synthetic service tests. It remains unwired to live UI/credentials/payment.

## Parallel module batch (awaiting integrated CI)

- Discovery home, separate route/game template shelves, play detail and read-only route preview; six source-backed public reads
- Personal orders with fresh detail, participant information with owned detail, badge wall and badge detail; session-isolated reader
- Merchant access/me gate, owner dashboard, permission-scoped filtered orders and hosted projects with summary sheets
- Explicit guest browse entry; account tab returns guests to identity/login selection
- 228 new bilingual module keys plus guest entry; the catalog now has 317 keys
- 86 new synthetic domain/service tests authored across the modules; three offline module UI smoke cases and guest navigation case authored

These are partial read-only module migrations, not complete workflows. Publishing/editing, verification/refunds, full feed, chat, club and play loops remain outstanding. The static mapping report fixes the source denominator at 130 mini-program mappings plus six extra App-route splits; it is not a work-completion percentage. The latest pre-batch a17b4ff run passed domain/build checks but timed out in one search UI expectation, so full regression remains open.

## Second parallel read batch (awaiting integrated CI)

Club home/directory/detail/member visibility, manual-area roaming map/list/details, and conversations/history have been integrated with session-scoped readers. No location permission, GPS sampling, message sending, marking read, join/invite, payment or other remote mutation was executed. Roaming has no default real location: the manual coordinate form is empty, keeps data in memory, and explains how a configured search uses its center.

114 additional synthetic domain/service tests and 214 bilingual keys were authored in this batch. Integrated totals are 315 authored domain tests and 531 catalog keys, not pass counts. The previous 1846552 batch passed 201 domain tests and both unsigned builds; its UI run passed 12/13, with a strict separate-text match for the order number failing. The updated assertion also recognizes the native combined label and retains the required reference value. It awaits revalidation along with the new module flows.

## Second batch verification

Run 36866520275 at e66571d passed native/domain/build and secrets jobs; UI passed 15/16. All six module smoke cases passed, including order detail, club members, messaging history and roam details. Pagination reached its empty result but XCTest could not calculate a tappable activation point for a static ContentUnavailableView title. Its assertion now checks existence and the expected text/absence of rows rather than requesting hittability of a noninteractive label. Full integrated revalidation remains pending.

## Third batch: interaction foundations (awaiting CI)

Phone OTP request/login is integrated behind explicit user actions and approved API configuration. Native Apple authorization remains disabled until capability/audience/legal/device verification. Source phone validation is domestic eleven-digit format; international/US support is not claimed. Participant create/edit/delete forms use confirmation, shared metadata preservation and uncertain-outcome readback; the default-address capability has no UI, preserving the retained source. Play session/task views are reachable from a selected activity, with server-gated text/choice answer logic exercised only by offline fixtures; production answer dispatch remains off pending acceptance/reconciliation. No actual SMS, OAuth, participant mutation, play submission or other backend action was executed.

85 additional domain tests were authored (21 authentication, 34 participant, 30 play), bringing the authored domain total to 400. Catalog total is 652 bilingual keys. These are implementation counts, not whole-App completion or release acceptance.

## Fourth batch (awaiting integrated CI)

Activity registration form/quote display and explicit raw-status readback are wired to a stable session coordinator. Production creation remains disabled; the demo consent and fake creation path exist only in offline DEBUG fixtures. Nullable ticket/total currency remains unconfirmed, with CNY limited to fields explicitly named/documented Yuan. Text-message composition uses source multipart requests and a retained client message ID; duplicate/unknown-outcome/closed/stale-identity guards and explicit retry are implemented. No actual message, quote, registration, payment, read receipt or other live request was performed.

Added 29 domain tests (18 registration UI, 11 message actions), with 429 authored domain tests and 736 bilingual keys in the integrated tree. Third-batch run 36870420339 passed 400 domain tests and both builds, and 18/19 UI cases. The remaining play test did not find its choice control before attempting to scroll the long form. Since Form can instantiate offscreen rows lazily, bounded reveal and navigation/diagnostic assertions were added; the cause and fix still await runtime revalidation. No failed case was excluded.

## Fourth batch verification and follow-up

Run 36874733922 at f521ac9 passed domain/build and secrets jobs, with 19/22 UI tests passing. The play choice case now passes. The first activity case timed out waiting for an initial row during unusually slow simulator/AX startup (the failure hierarchy contains the expected row); the bounded readiness timeout is now 30 seconds. The new registration case tapped Review without showing confirmation; enabled/consent checks and hierarchy diagnostics are being added rather than excluding it. Message send reached the synthetic transcript but its receipt/draft presentation did not update; observation attachment now follows the visible composer lifecycle and completion synchronizes its state. All three require rerun verification.

## Club action integration (awaiting CI)

Join/application/reapplication and leave now use a stable session-owned coordinator, fresh rights checks, native confirmation, conservative uncertain-outcome locks and server membership readback. Unknown receipt and current membership remain separate facts. Added 50 synthetic domain tests and three offline UI cases; totals are 479 authored domain tests, 25 UI cases and 760 bilingual catalog keys. No real membership request was sent. Six Python structural tests and scaffold checks pass locally; Apple compilation and simulator execution for this batch remain pending.

## Fifth batch verification in progress

Run 36879776914 at b596b6b has passed all 479 domain tests, both unsigned app builds and secret scanning. The 25-case simulator job is still running; this is not a full green result. A subsequent uncommitted workflow change prepares one-day, synthetic-only screenshot artifacts for visual inspection and boots the simulator before UI readiness checks. Neither screenshot export nor visual acceptance has yet been verified.

## Merchant application slice (awaiting CI)

The native four-step application/status flow now has Account and MerchantHome entry points, a retained session-scoped coordinator, separately confirmed license upload and frozen application submission, rejected-data backfill, and explicit pending/activation/effective/disabled states. Forty-one new core tests and three offline UI cases are authored (520 core / 28 UI total before the next topic slice); 848 bilingual keys are present. Existing registered identities can use the source contract only after approved backend configuration and acceptance. New US identity enrollment remains blocked because the retained source supports a Chinese resident-ID prerequisite rather than a verified international enrollment contract. No real document selection/upload, personal-data transmission, submission or approval was performed.

## Fifth UI result and regional/topic batch

Run 36879776914 finished with 21/25 UI cases passing. The previous activity readiness and composer receipt cases pass. Three new club-action cases reached a visible native confirmation sheet but could not target its nested confirmation buttons; their selectors are being corrected without removing mutation-count or membership assertions. Registration diagnostics show the outer consent Toggle row remained off: its actual nested UISwitch must be tapped. The review remained correctly disabled. These corrections still require another simulator run.

The subsequent integrated batch adds read-only public route/topic pagination, supplied chapter/node stories, tickets/comments and explicit locked/unavailable states. It performs no purchase, like, start, hidden-chapter or Play.nodes request. Thirteen domain tests and two UI cases are authored.

CN/US operational profiles now remain independent of UI language. CN defaults Chinese, US English; saved English/Chinese/System choices remain available. Market metadata fails closed, endpoints require an independently reviewed per-market allowlist (currently empty), and credentials/tombstones are namespaced by market with no automatic legacy migration. Existing CN phone/password adapters cannot dispatch from the US profile. US authentication and all payment/payout capabilities remain blocked pending actual contracts/provider/entity verification. Eight regional domain tests and two entry UI cases are authored. There are 541 authored core tests, 32 UI cases and 897 bilingual keys after these integrations. Compile/runtime verification for this batch is pending.
