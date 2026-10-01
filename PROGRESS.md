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

## Sixth batch UI result and follow-up

Run 36883873097 at d4022f0 passed 541 core tests, three unsigned builds (default simulator/device and US device), and secrets. UI finished 24/32. Seventeen explicit synthetic screenshots were exported successfully and three inspected; they show actual native controls with fixture data, not live business acceptance or all-state accessibility certification.

Eight failed UI assertions are retained. Club readback selected the decorative Refresh icon instead of membership text, and a separate counter lookup timed out with the recorded count still zero. Both selectors/accessibility semantics were corrected without changing write-count assertions. Registration now passes consent/confirmation/create, but its reference-backed status subview lacked an explicit update revision and its lower status rows also need bounded reveal. CN first-launch language switching and three default-profile entry checks failed; the follow-up restores nonoptional language storage and adds an explicit Info.plist source plus assertions on the actual built CN/US metadata. These explanations and fixes await runtime revalidation.

Computed UI labels now use LocalizedStringResource with the chosen locale. Apple's String(localized:locale:) uses its locale argument for interpolation formatting, not lookup-language selection; passing locale to that initializer alone is insufficient. Added an actual app-resource language-toggle UI case and a US English-to-Chinese market-preservation case. Native tint uses separate darker-light/lighter-dark purple values after screenshot review; this is not a claim of full accessibility compliance.

## Seventh integration batch (awaiting CI)

Added source-backed club application approve/reject and creator-only member removal, with target confirmation and conservative uncertain-outcome readback. Added self nickname/introduction editing with latest-field preservation and immutable confirmation. Unknown profile writes remain locked even when current values match; only acknowledged completion with matching readback permits subsequent changes. Image uploads, bindings, fine-grained club roles, dissolution and financial governance remain deferred.

Integrated authoring totals: 569 core tests, 43 UI cases, 952 bilingual keys. Twelve Python checks pass locally. UI execution is now split into two deterministic, exhaustive class groups; inventory checks reject omissions/duplicate classes and both jobs must pass. No case is excluded to achieve a green result. Failure screenshots are retained for direct inspection. Swift compilation and simulator results for this batch are pending.

## Seventh batch: verified intermediate result

At b47b34aeef78f736c70f8652b9af6f3bd63b802d, run 36891305859 passed all 569 Swift core tests, all three unsigned app builds, actual built CN/US profile metadata validation, and secrets scanning. Both exhaustive UI shards are still running; full UI success is not claimed.

## Eighth integration batch (awaiting CI)

Home now uses the source-backed feed with featured links, recommendation/highlight/upcoming sections, content/category selection and paged search. Activity/topic navigation opens the existing native detail modules. Price/date/place fields and Beta/LIVE states are represented; missing currency stays unknown, and location-free highlights make no proximity claim. Continue-session/countdown parity is still deferred. The template browser remains accessible from the native toolbar. Eight synthetic core tests and three UI cases were added.

The client-only US Apple challenge/exchange adapter and native authorization control are compiled into this batch but not mounted or enabled. Production gate stays false; no provider configuration, protected-account contract, host/session wiring or actual sign-in is implied. Thirty-two synthetic Swift tests and seven source-only contract checks cover the disabled adapter, nonce/state/TTL and identity boundaries. The worker-only shared-file hash assertion was replaced at integration by an explicit no-production-host-construction and empty-capability assertion; unrelated authorized modules necessarily change those shared files.

Integrated authored totals: 609 core tests, 46 UI cases and 996 bilingual keys. Twelve Python tooling checks and seven client source checks pass locally. Swift/App/Simulator execution for this batch remains unrun pending the next cloud run. No actual backend, provider or payment requests were performed.

## Seventh batch final UI result and next corrections

Run 36891305859 finished: 34/43 UI cases passed (19/21 and 15/22). All activity, club-join/application/unknown-outcome, registration, entry, messaging, topic and previous module tests in this run passed. Nine failures remain: two profile review selectors, four club management review selectors, one merchant cancel action and two region-switch navigation-title assertions. Actual failure screenshots show the profile/club SwiftUI modals were displayed but did not expose XCTest's Sheet type; tests now verify the review title/target and actionable button without assuming that container type. Club dynamic localization keys visibly leaked into the UI and are corrected, with the same key-construction correction applied to other matching native views. Settings and welcome navigation titles now use an explicitly locale-resolved string. Merchant submission uses an explicit native alert so Cancel remains available under regular/popover adaptation. These fixes require the next simulator run, not just source checks.

Ticket wallet has also been integrated: two independently fetched route/activity ticket lanes, partial failure, fresh detail, status/entitlement display and strict account/token/epoch isolation. A current 401 closes the private wallet. Redemption-code issuance, redemption, payment/refund and team navigation are not enabled. Fifteen domain tests and six UI cases are authored. The combined next batch has 624 authored core tests, 52 UI cases and 1050 bilingual keys; no pass claim is made for the new Swift/UI cases until CI.

## Eighth batch verified intermediate result

At a1be59e9a942bbb71bd22960ed13d4625997e4a0, run 36897202372 passed 624 Swift core tests, all three unsigned builds, built regional metadata and secrets. The 52-case UI run is still in progress; it is not a full green result.

The following local batch adds source-backed square feed/detail/comments (21 domain and 9 UI tests), the protected US session-proof client and nullable-avatar contract (11 additional domain tests), plus 2 synthetic Chinese/dark/large-text/Reduce-Motion presentation tests. US production remains hard-off. No deployed endpoint readiness or live identity verification is implied. Source-only checks pass; Apple execution for this next batch is pending.

Design direction now explicitly follows Apple native resources and inspected public Airbnb/Flighty patterns. See docs/native-design-and-motion.md for concrete hierarchy, accessibility and motion decisions and their evidence limits. Home/ticket visual and motion refinements are being implemented without changing business gates.

## Eighth batch final result and ninth integration

Run 36897202372 at a1be59e finished 44/52 UI passes (25/26 and 19/26). All four regional-language cases, three merchant-onboarding cases and six ticket-wallet cases passed. The remaining eight failures are one lazy registration status row, four club confirmation target-label queries, two profile test predicates unsupported by XCUIElementQuery, and one home card tap that did not reach its destination. Actual home failure screenshot remains on the feed; the new native card ButtonStyle supplies a whole-card hit shape, but navigation repair still requires rerun.

The follow-up retains every assertion and test. Registration reveals the actual status value rather than its already-visible section header; club checks preserve the full reviewed club/member identity inside native combined labels; profile targets enumerate actionable controls rather than querying the unsupported hittable key. Locale-resolved navigation titles now apply consistently across native product screens.

The integrated next batch adds square reads, the disabled US protected-session proof, native home/ticket visual hierarchy and interruptible motion, and successful synthetic screenshot capture. Home LIVE updates use a finite initial/start-boundary schedule rather than per-card one-second polling. Two Chinese/dark/accessibility3/Reduce-Motion environment fixture cases were added; these are not device-setting or VoiceOver certification.

Current authored totals: 656 core tests, 63 UI cases, 1108 bilingual keys. Twelve tooling checks and 22 source-contract checks pass locally. UI inventory is now partitioned into three exhaustive groups to shorten feedback as coverage grows; no tests are excluded. All new Apple/visual/motion runtime evidence awaits the next commit's CI.
