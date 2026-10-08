# Native iOS migration progress

Status: migration in progress, not release-ready. This is a chronological log; the latest batch evidence is at the end. Older counts below are retained history, not current coverage.

## Working convention

Continue implementation and validation on `migration/native-ios`. Do not open a new PR for every small slice. Open one overall migration PR when the complete scope is implemented and its acceptance evidence is available. Earlier small draft PRs remain historical evidence; closing them does not mean their features are complete or merged into main. The migration branch preserves their commits.

## Historical fully passing foundation baseline

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

## Bulk collections/cooperation and shared entity cards (2026-10-01 18:31 UTC)

Verified b754aa1131d52cc7368185e04333d4b26fb49d16, run 36903650207: 656 core tests, three unsigned builds, regional metadata and secrets all passed; 58/63 UI cases passed. Four Square failures were localized to accessibility identifier propagation / a label-versus-identifier assertion; the ticket notice query selected its decorative icon instead of text. The following batch moves identifiers onto semantic text, preserves retry assertions, and requires a fresh Apple rerun. No failed cases are removed.

Integrated cooperation inbox/history/pool/candidate reads and account favorite-topic pagination plus owned-coupon metadata list/detail, with fresh reads, independent failure states, current-session guards and bilingual UI. Existing participant addresses are reused, not duplicated. Favorite topics open the existing native topic detail. No coupon QR issuance or financial settlement is implied.

Applied a shared full-bleed artwork / bottom gradient / overlaid-text card without an outline to club, topic and favorite-topic surfaces. Merchant card composition is available, but no source-backed merchant artwork surface is claimed. The user's reference image is not copied into the public repository. Activity detail hierarchy and a gated native bottom booking opener are refined in the same batch. These changes still need Apple runtime verification.

The previous b754 home light and Chinese dark/accessibility3 screenshots were inspected. They demonstrate content/navigation test coverage, not acceptance of the new image-card design or actual device Reduce Motion/VoiceOver. DEBUG motion tests override our motion policy without writing the system's read-only environment value.

Current authored inventory: 695 core tests, 80 UI cases, 1257 bilingual keys. Local structural check, 14 tooling tests and 51 contract checks pass. Advisory Tree-sitter checks are not a compiler or CI acceptance gate. Production configuration, live backend/device flows, signing and release remain unverified.

### Creator reads integrated; publication blocked (2026-10-01 19:10 UTC)

Added source-backed My Project filters and creator-center read states/metrics/income, plus typed navigation to existing native topic/activity/play-template read previews. Source project management/editor actions, applications, deletion, publish/visibility changes and refunds are not represented as complete. The source fixed 200-result request cap is disclosed. Separate topic/story templates are not routed into play-template detail. Current authored total is 716 core tests, 85 UI cases and 1305 bilingual keys; 14 tooling and 61 source-contract checks pass locally. Apple execution remains pending.

GitHub tree creation encountered repeated automatic permission-review timeouts. One immutable tree object was confirmed, but no new commit/ref update or CI run exists for this local batch. Remote remains b754aa1. Source files are retained locally; API publication is paused after the allowed retry, while independent migration/audit continues. The user's subsequent explicit branch-push approval has been received; timeout is not evidence that code is unsafe or that the branch changed.

### Growth center reads integrated (2026-10-01 19:40 UTC)

Added an Account entry for source-backed growth overview, badge dates, read-only mission metadata, and point/EXP × week/total rankings. Exactly four audited JSON POST read routes are implemented. Independent source failures stay unknown rather than fabricating zero balances, badges or completions; any sibling 401 discards the private aggregate. Requests/results and unauthorized callbacks remain bound to account ID, epoch, token and a credential-free UI scope; leaderboard results are additionally bound to the requested filters. No reward claim, check-in, redemption or other write action is added. Badge/portrait URLs are retained as source fields without external image fetching; ranks use native ordered rows instead of the decorative podium.

AppSession wiring preserves the latest regional storage-scope gate and CNAccountSessionService restoration/logout fixes, as well as creator/collection integrations. Real API bases remain empty, and US production authentication remains disabled. New DEBUG fixtures are synthetic and offline.

Growth contributes 17 authored core tests, seven authored UI cases and 47 bilingual keys. The complete current tree now contains 750 authored core tests (including five regional-storage and 12 CN-account-session tests), 92 authored UI cases in 17 classes, and 1352 bilingual catalog keys. The exhaustive three-shard inventory is 30/31/31 tests, recorded in docs/ui-shard-inventory.json; no class or case is omitted.

Local checks pass: project generation/deterministic scaffold verification, 81 source-contract checks, 15 tooling tests, and 14 advisory-parser self-tests. All ten new Growth Swift files pass the supplementary parser. The aggregate parser reports ten recovery diagnostics across six pre-existing, untouched files (AuthChannelView, MerchantHomeView, MessagingComponents, RegistrationSheetView, RegistrationUIForm, ParticipantCoordinatorTests); these are not compiler results and are not silently excluded. Swift compilation, SwiftPM tests, Xcode builds, simulator/UI/screenshots, VoiceOver, and device Reduce Motion for this integrated batch remain NOT_RUN. No remote publication or real service/provider call was made for this integration.

### Official events read-only integration (2026-10-01 19:44 UTC)

Added a distinct Home entry for official events, preserving the ordinary ActivityBrowser and its different source routes. Seven audited GET reads support public status-filtered discovery and fresh detail, private joined events, publisher history, invitation inbox and ownership-checked broadcast statistics. Public guest discovery stays available; private guest views offer the existing account/login destination without sending requests. Publisher-denial copy is a permission state rather than a retryable failure. Publishing, registration, arrival verification, invite responses, broadcast submission/click tracking and all financial/backend writes remain absent.

Models preserve server facts, including status, V2 missions, reported collective progress and configured rewards. Missing status, dates, price and artwork are not replaced with invented defaults. Unzoned dates are displayed as supplied without invented countdowns. Public and private reads guard epoch/account/token changes, including guest → account → guest round trips; stale results and stale/cancelled 401 callbacks are discarded. The native surfaces use the shared full-bleed image card, lazy List rows, semantic text/labels, native navigation and motion policy; visual/accessibility behavior has not been runtime-accepted.

AppSession integration preserves all Growth/Creator/Collections/Cooperation additions, regional storage scope and CNAccountSessionService restoration/logout. The Home sheet is keyed/reset on official reader scope, and guest login requests navigate through the current account tab. Backend configuration and approval registries remain empty.

Added 21 authored core XCTest methods, ten synthetic UI methods and 101 English/zh-Hans keys. Integrated authored totals are 771 core tests, 102 UI methods in 18 classes and 1453 bilingual keys. Regenerated project and exhaustive shard inventory: 34/34/34 UI methods; none omitted. Local checks pass: 93 source-contract checks, 15 tooling tests, 14 advisory-parser self-tests, deterministic scaffold verification and git diff whitespace checks. All 15 new/edited integration Swift files parse without Tree-sitter recovery. The aggregate parser still reports the same ten diagnostics in the six pre-existing files recorded above, and is not a compiler result.

Swift compiler/SwiftPM, Xcode builds, simulator/UI/screenshots, VoiceOver, device Reduce Motion and live service acceptance remain NOT_RUN. No push, remote publication retry, CI run or deployment was initiated. See docs/official-event-module.md and docs/official-event-verification.md.

### Professional route editor integrated (2026-10-01 19:51 UTC)

Home and Account now expose a native local route editor for city orientation and free exploration. Guests can compose/review in memory; authenticated, reviewed deployment scopes support account-bound device-only secure draft save/restore. Native basic details, chapters/stops/story blocks, tickets, validation, immutable review and WHITELIST edit restrictions are implemented. Source detail/payload mappings preserve chapter merchant contract carry-over and distinguish missing ticket price from explicit free. No media, map, category or gameplay picker is falsely represented as connected.

Production service is deliberately disabled and contains no HTTP adapter. DEBUG fixtures alone demonstrate explicit simulation. Durable pending intent is stored before submission, rechecked for duplicate coordinators and retained for unknown outcomes across reopen/reauthentication; terminal fixture receipts are operation-bound, and completed receipts prevent same-draft replay. Full backend idempotency, ownership/capability verification, live edit-detail/publish, media upload, AI and advanced commerce/creator authoring remain deferred. See docs/project-edit-module.md for exact scope and differences.

Added 31 authored core methods, nine authored UI methods and 128 bilingual keys. Integrated totals: 802 core, 111 UI in 19 classes, 1581 catalog keys. Exhaustive three-shard inventory is 37/38/36; nothing excluded. Deterministic generation/scaffold, 107 source-contract checks, 15 tooling tests, 14 parser self-tests and diff whitespace checks pass locally. Seventeen new/edited Swift files pass supplementary parsing. All Swift compiler/SwiftPM/Xcode/simulator/visual/accessibility/live acceptance remains NOT_RUN. No remote publication or backend/provider requests were made. Regional storage/CN session, Growth and Official integrations are preserved.

### Settings, About and source legal documents integrated (2026-10-01 19:55 UTC)

Existing Settings keeps its independent market/language storage, picker, navigation stack, locale environment and Done action. Additive native sections now expose six serialized local sound/haptic preferences, actual native Bundle app/version/build metadata, source contact and offline attribution, and read-only legal documents. Preference reads distinguish missing defaults from corrupt data; failed saves retain the previous visible value. These flags do not operate hardware or imply audio/haptic playback integration.

CN source agreement v2.2 and cancellation notice v2.1 are copied verbatim with all 13/5 sections and dates. The source app privacy policy remains missing; all US documents and missing-market selection fail closed. English interface selection never changes market or translates legal text. Source text is labelled as requiring native-app legal review; reading never records acceptance. Privacy/marketing/account-deletion destinations explicitly explain unconnected controls without dummy switches or mutation actions. Personal-code source decoding is authored but its potentially generating POST and image fetch are not wired. No actual device setting, live consent, deletion, external launch or network call was performed.

Added 25 authored XCTest methods, 11 synthetic XCUITest methods and 49 bilingual keys. Current authored inventory: 827 core methods, 122 UI methods in 20 classes and 1630 catalog keys. Exhaustive UI shards are 40/41/41; no case is omitted. Local source checks pass: 115 contract checks, 15 tooling checks, 14 parser self-tests, exact Flutter legal/attribution parity, localization/side-effect boundaries, scaffold/deterministic project generation and whitespace checks. Twelve new/edited integration Swift files pass supplementary Tree-sitter parsing. Full-tree parser retains the same ten diagnostics in six previously documented files; it is not a compiler result.

Swift typechecking, XCTest execution, Xcode builds, simulator/UI/screenshots, device/accessibility checks and legal/live-service acceptance remain NOT_RUN. Native privacy/US legal text, source QR generation, consent management, cancellation workflow and audio/haptic consumers remain incomplete. See docs/settings-native-module.md for exact scope. Latest Home/Account route-editor entries, Growth/Official/Creator/Collections, regional storage and CN restoration/logout changes are preserved. No publication, CI, backend configuration or remote retry occurred.

### Club create/edit and owner operations integrated (2026-10-01 20:04 UTC)

Club Home now opens a native club-create form; governed Club Detail opens a retained club workspace. Source-canonical profile/type/preferences, priority signup/quota and supported joining policy are implemented with immutable review. Owner-only visibility/member-post/merchant-cooperation settings and legacy administrator role changes show exact club/account/member targets and consequences. Six exact source mutation descriptors are authored, while the production writer and coordinator remain hard-off before dispatch. Creation requires fresh server leader role/owned clubs; profile edits reject changed baselines; settings and member roles recheck current eligibility. No live mutation is enabled or performed.

Account/epoch/token-bound reads reject stale results. Repeated confirmation, screen ownership, same-account relogin, account changes and uncertain outcomes are covered in the retained coordinator. Unknown requests remain locked after navigation and current-state readback. Locks are in memory, so durable reconciliation/idempotency and verified capabilities remain production blockers. Existing media is preserved, uploads are disabled, and retired member pricing is omitted. Missing openness/role facts fail conservatively. Leader applications, v2 role/event permissions, dissolution, finance, notifications and broader club operations remain incomplete; this is not full club parity.

DEBUG fixture entry and normal navigation are mounted without constructing a production session in fixture mode. Forms use bilingual native controls and semantic accessibility labels, the existing full-bleed no-outline card, and Reduce Motion-aware state transitions. Existing Settings, Home/Account local editor, Official/Growth/Creator/Collections, regional storage and CN restoration/logout code is preserved.

Added 26 authored core methods, ten authored UI methods and 105 bilingual keys. Current inventory is 853 core methods, 132 UI methods in 21 classes and 1735 bilingual keys. Exhaustive UI shards are 44/44/44. Deterministic project/scaffold checks, all 123 source-contract checks, 15 tooling tests, 14 parser self-tests and whitespace checks pass. All 15 new/edited Swift integration files pass supplementary parsing; full-tree parser retains the same ten diagnostics in six pre-existing files. Swift compiler/XCTest/Xcode, simulator/UI/screenshots, device/accessibility and live acceptance remain NOT_RUN. No remote publication, CI, configuration change or actual backend request was performed for this integration. See docs/club-operations-module.md and docs/club-operations-verification.md.


### Merchant store operations and resource catalogs integrated (2026-10-01 20:10 UTC)

Merchant workbench now opens native store profile, decor/gallery/story, hosting settings, store character, voice/3D resources, city-location/application catalog and private interaction-template catalog/editor. Nine exact source read routes preserve raw status uncertainty, first-page limits and owner-only template answers. Additional access/me projections use exact profile/coop/project permission keys; owner or entry intent alone never grants them. Hidden overwrite fields, canonical gallery/tag array strings, story's non-atomic two-operation topology and method-specific template validation are retained.

Native forms include memory-only local drafts, dirty back/reload confirmation, immutable review and source-conflict checks. Every live writer remains hard-off before transport; only DEBUG fixtures save synthetic examples. No real uploads, permissions, withdrawals/payments, deletion, publication, claims, QR redemption, recording/cloning/3D generation or provider mutation is added. Saved examples never claim approval or real business completion. Session epoch/account/token changes invalidate private data and stop the second read after access; unknown synthetic outcomes lock without automatic resend. Locks are memory-only, so durable reconciliation and backend idempotency remain production gates.

Added 43 authored core methods, five synthetic UI methods and 146 bilingual keys. Current inventory: 896 core methods, 137 UI methods in 22 classes and 1881 bilingual keys; exhaustive shards 47/45/45. All 133 source-contract checks, 15 tooling tests, 14 parser self-tests, deterministic project/scaffold and whitespace checks pass locally. Thirteen clean new/edited Swift files pass supplementary parsing; full-tree parser retains the same ten diagnostics in six pre-existing files. Swift compiler/XCTest/Xcode, simulator/UI/screenshots, accessibility/device and live acceptance remain NOT_RUN. No publication, CI or actual backend/provider request occurred. Regional storage/CN session and all previous Club/Settings/editor/Official/Growth/Creator/Collections integration is preserved. See docs/merchant-operations-module.md and docs/merchant-operations-verification.md for the precise boundary and remaining merchant modules.

### Owned teams and guarded team flows integrated (2026-10-01 20:18 UTC)

Account and the ticket wallet now expose a distinct My teams list with fresh team detail and roster. Five source status values remain distinct; server counts, ownerType/ownerId, expireTime, explicit membership/leadership and ordinary-member role 0 are retained. Local invitation preview/join review, activity-team creation form/review, leave/removal/dissolution review and a leave-instead alternative are implemented. Source consequences keep tickets, refunds and redemption separate from membership. Nearby teams/applications remain a separate, unmigrated domain.

Every live team write and invitation-sharing action is hard-off, and the AppSession team read service remains unconfigured pending module verification. Creation eligibility requires source registrationStatus==2/teamMode==2 and an activity owner; the existing ticket projection cannot invent missing teamMode/teamMaxMembers. Typed integration adapters and DEBUG create/invite fixtures are ready while the order-lifecycle projection is being migrated. The source join-mode setter explicitly documents an inferred payload, so native modification remains unavailable.

Immutable review, exact-target preflight, account/epoch/token/role/region/deployment scoping and cancellation guards reject stale operations. A minimal persistent journal is written before synthetic dispatch and blocks unknown-outcome replay across navigation, coordinator recreation and same-account reauthentication. Ordinary state refresh cannot clear uncertainty; only a correlated terminal fixture receipt can. No production receipt endpoint or backend idempotency has been invented. No actual service, invitation, membership, deletion, payment/refund or remote publication was performed.

Added 47 authored core methods, 12 synthetic UI methods and 74 bilingual keys. Current integrated inventory: 943 core methods, 149 UI methods in 23 classes and 1955 keys; exhaustive UI shards 49/50/50, nothing omitted. All 147 Python source-contract checks, 15 tooling tests, 14 parser self-tests, deterministic project/scaffold and whitespace checks pass. Sixteen new/edited Swift files pass supplementary parsing; full-tree parser retains the same ten diagnostics in six pre-existing files. Swift compiler/XCTest/Xcode, simulator/UI/screenshots, device/accessibility and live acceptance remain NOT_RUN. Prior merchant/club/settings/editor/official/growth and scoped CN-session integrations are preserved. See docs/team-module.md and docs/team-verification.md.

Cross-batch session fix: profile-save refresh now uses CNAccountSessionService with matching regional storage scope, retaining account/token/epoch/fresh.id checks. This prevents phone-only CN sessions from silently skipping refreshed account data because password entry is disabled; a dedicated source assertion was added. No authentication capability was enabled and runtime remains NOT_RUN.

### Global search, city-node search and manual-area maps integrated (2026-10-01 20:23 UTC)

Added a distinct Home global-search entry for topic/activity/club/merchant sources, without representing the Home feed's existing search as global parity. Source contracts preserve four-domain fan-out, local date/price filtering, category/type counts, first-page limits, partial failures and explicit guest gates. Recent searches remain local in account/region/deployment-scoped device-only Keychain storage. City-node search independently combines 50 source activities with authenticated 20 km city POIs; missing-coordinate activities remain list-only. Nearby route-node maps use the separate 2 km/50 source plus optional reverse-city lookup and its rate-limit/manual fallback states.

Typed topic/activity/club links reuse existing native details. Merchants open a proper public-detail surface by merchant ID; the source's member-ID public-user-home link is not misrepresented as migrated. City POIs use their own verified detail route, and nearby route node/template IDs never cross into unrelated POI/topic domains. Requests, results and unauthorized callbacks are fenced by account/epoch/token/guest scope; query/category generations, input changes, dismissal and mode changes reject stale completions. Back navigation preserves loaded results while session changes reset the stack. Existing regional/CN profile-refresh, team, merchant/club operations and all prior routes remain intact.

MapKit is an explicit manual-area display with no device-location collection or map-pan uploads. Offline fixtures do not mount remote tiles/artwork. Route previews support injected geometry and an honest local straight-line fallback with no invented ETA or steps. Live road planning, location/privacy authorization, external Maps launch and turn-by-turn guidance remain unimplemented/unverified; this is not full source navigation parity. No live backend/provider/location operation, remote publication or user-computer action was performed.

Added 21 authored core methods, nine synthetic UI methods, eight aggregate Python contract methods and 103 bilingual keys. Including the independent editor stable-ticket-identity fix's four additional core tests, the current source inventory is 968 authored core methods, 158 UI methods in 24 classes and 2,058 bilingual keys. Exhaustive UI shards are 53/53/52; no class or test is omitted. All 155 Python contract checks, 15 tooling checks, 14 parser self-tests, 26 standalone search/map source/structure assertions, deterministic project/scaffold and whitespace checks pass. Nineteen new/edited Swift files parse without recovery; the full 380-file supplementary parse retains the same ten pre-existing diagnostics in six files. Swift compiler/XCTest/Xcode builds, simulator/UI/screenshots, actual accessibility/device and live acceptance remain NOT_RUN. See docs/search-map-module.md and docs/search-map-verification.json.


### Roaming passport, local history and server readback integrated (2026-10-01 20:31 UTC)

The existing map toolbar now opens a native roaming passport: protected local history and session-route cards, server-session status/settlement readback, incremental saved-tile memory, paged stamp album/detail, a memory-only city-stamp caption preview, honest voucher missing/unavailable states and a retired-hangout explanation. Five exact source reads preserve ACTIVE/FINISHED/NOT_FOUND distinctions, incomplete settlements, server page/cursor facts and unsubmitted vs rejected stamp moderation. Local records retain missing measurements rather than substituting zeros; storage errors cannot masquerade as empty history. A complete matching settlement receipt is required by the dormant history-save boundary.

History is scoped to account, market, reviewed deployment URL, native bundle and deployment realm; data stays in non-synchronizing, device-only Keychain storage. Full token/epoch snapshots fence reads and 401 handling. Refreshes, edited recovery targets and session replacement invalidate old results. Manual-area coordinates never become a device fix. Production GPS, presence, settlement, uploads, stamp exchange, voucher issuance/redemption and retired hangout writes remain hard-off; no actual permission prompt, backend/provider request, account/membership mutation, reward or photo-sharing action was performed. This is read/local-state parity, not end-to-end live roaming parity.

Added 49 authored core methods, ten synthetic UI methods, eight Python source-contract checks and 80 bilingual keys. Including the independent three-test team invitation-normalization fix, current inventory is 1020 authored core methods, 168 UI methods in 25 classes and 2,138 bilingual keys. The enlarged suite now has six exhaustive class-level shards (28/28/28/28/29/27) under the existing 25-minute job limit; no tests are omitted and no new CI execution occurred. All 163 Python source-contract checks, 16 tooling tests, 14 parser self-tests, deterministic project/scaffold and whitespace checks pass. Twenty-three new/edited Swift files pass supplementary parsing; full-tree parsing retains the same ten pre-existing diagnostics in six files. Swift compiler/XCTest/Xcode, simulator/UI/screenshots, device/accessibility and live acceptance remain NOT_RUN. Existing editor ticket identity, CN scoped profile refresh, team, search/map and other prior integrations are preserved. See docs/roam-experience-module.md and docs/roam-experience-verification.json.

### Order lifecycle, guarded action review and ticket verification contracts integrated (2026-10-01 20:39 UTC)

Existing profile-order and ticket-wallet details now link to native order lifecycle details while preserving their original fields. The new read projection and timeline retain independent payment/registration/verification facts, explicit refund application presence and payout status, manual after-sales precedence, refund policy, absolute payment expiry and source China-time schedules. Refund completion comes only from source payout status 1/4; cancellation alone never becomes a refund receipt. Registration acceptance is displayed separately from cash settlement. Read-only payment reconciliation has source 1.5s/5s/20s timing, monotonic deadline and cancellation/session fencing, including a transport that ignores cancellation.

Native bilingual action review uses an immutable exact-order snapshot with 60-second expiry, current account/session/target checks and explicit disabled production confirmation. Source-backed dormant request builders and a DEBUG fake-transport adapter cover cancel vs cancel-refund, payment parameters, ticket/coupon issuance and dynamic/legacy/coupon/chapter/station verification. The normal adapter cannot dispatch, and AppSession never constructs it. Ticket pass UI exposes no real code, token, remote QR image or scanner/camera action. Verification previews preserve choice-bearing error envelopes as non-redeemed; station choices require registrationMerchantId. Payment signatures/defaults, provider callbacks and settlement success are never fabricated.

The retained session coordinator keeps unknown-outcome attempts locked across dismissal, refresh and same-account reauthentication. These locks remain memory-only and are not sufficient for production financial enablement. Read responses and 401s are bound to the complete session; explicit server prose remains verbatim. Owned order team context now retains the exact registrationID plus activity ownerID, teamMode/teamMaxMembers and registration status. It grants no team mutation permission; the production team creation adapter remains unavailable pending independently verified fresh owned-registration integration. No actual backend/provider, purchase/refund/cancellation, credential issuance/redemption, external link or permission operation occurred.

Added 58 authored core methods, seven synthetic UI methods, ten aggregate source checks and 110 bilingual keys. The concurrent roaming follow-on adds thirteen core methods and three source checks: exact dormant presence/stamp/voucher request contracts plus session/role-safe local stamp-exchange review; all production mutation dispatch remains disabled. Its album navigation fix now cancels pending work without deleting the rows that own the pushed NavigationLink. No UI/key additions came from that follow-on.

Current integrated inventory is 1,091 authored core methods, 175 UI methods in 26 classes and 2,248 bilingual keys. All six UI shards are exhaustive (29/29/29/30/30/28). All 176 Python source-contract checks, 16 tooling tests, 14 parser self-tests, ten standalone order source checks, deterministic project/scaffold and whitespace checks pass. The combined 34 new/edited Swift files parse without recovery; full-tree parsing has the same ten pre-existing diagnostics in six files across 421 Swift files. Swift compiler/XCTest/Xcode, simulator/UI/screenshots, VoiceOver/dynamic type/device and live acceptance remain NOT_RUN. No publication or CI run was performed. See docs/order-lifecycle-module.md, docs/order-lifecycle-verification.json and the updated roaming documents for exact boundaries.

### Public profiles, invitation history and guarded social authoring integrated (2026-10-01 20:48 UTC)

Account now opens public profile, invitation history and play guide. Square feed/detail adds native text composition, author profiles and comment/reply/action review while preserving existing reads. Public headers remain guest-readable; author posts have a distinct login gate. Profile relationships and unavailable counts remain unknown. Invitation history keeps total separate from loaded records and distinguishes earned rewards, pending first purchase and incomplete/failed reward synchronization using the source's normalized invite IDs, event type 5 and 200-row scan boundary. Guide/info screens retain meaningful numeric titles, removed/empty/missing states and real Home/Roam tab destinations.

Exact dormant transport adapters cover text post create/edit, comments/replies, explicit LIKE/BOOKMARK, toggle-only comment likes, ID-only legacy reports, follows and conversation start. Editing preserves source association/media fields. Normal AppSession still mounts the disabled writer and visibly disabled Submit; no live action is enabled or executed. Immutable target/account/epoch/role reviews, fresh context checks and retained uncertain-outcome locks reject stale completion and duplicate retries. No post/comment identity, moderation success or conversation ID is fabricated. Locks remain memory-only and require durable reconciliation before production use.

Message details now include an opt-in native image-preview destination and injected HTTPS-origin-constrained credential-free media service. Local fixtures exercise decoding; production media remains unconfigured pending approved origins and bounded streaming. No upload, camera permission, remote card action or additional message-info endpoint is introduced. Back navigation preserves rows owning destination links; session changes fence private results. Professional v1 publishing, upload/media tools, governance/drafts, direct Club member links and sensitive account flows remain gaps, rather than claimed parity.

Added 44 authored core methods, eight synthetic UI methods, ten source checks and 102 bilingual keys. Current inventory: 1,135 authored core methods, 183 UI methods in 27 classes and 2,350 keys. All six UI shards remain exhaustive (30/32/31/31/30/29). All 186 source-contract checks, 16 tooling tests, 14 parser self-tests, deterministic project/scaffold and whitespace checks pass. Twenty-nine new/edited Swift files parse without recovery; full-tree supplementary parsing retains the same ten pre-existing diagnostics in six files across 440 Swift files. Swift compiler/XCTest/Xcode, simulator/UI/screenshots, actual accessibility/device and live acceptance remain NOT_RUN. No publication or CI run occurred. Existing order lifecycle, Roam, team, regional/CN session and prior flows are preserved. See docs/social-account-module.md and docs/social-account-verification.json.

Social/account correction (20:51 UTC): reward totals accept exact integral numeric strings such as `240.0`; fractional, malformed or negative totals fail closed. Missing/null totals retain “not synchronized” rather than proving completeness. One additional authored core regression test is included in the counts above.


### Local play-template authoring and prefab narrative preview integrated (2026-10-01 20:54 UTC)

Account now opens distinct native play-template creation, own-template catalog and local Prefab Life preview. Intro/name/editor replacement steps, completion/reward/story/audio fields, story timeline, preview and immutable submission review are implemented. Public play-template detail from normal Home and creator routes can seed a local draft, preserving originalTemplateId without copying hidden answers. Whole-topic templates and route editors remain separate identities and destinations.

The complete source TemplateDraft wire field set, six audited template/dictionary endpoints and exact dormant JSON/FormData multipart request construction are authored. Seven source-enabled advanced-game panels and timer preserve all 25 source section defaults; unknown and unsupported active sections are preserved locally and block submission. Production factories mount only the hard-off adapter. Existing server-template editing needs an owned full-detail contract; dictionary/category picker integration, upload/media tools, broader advanced panels and library/delete management UI remain gaps. Known library/delete contracts are implemented as dormant request adapters, not fabricated routes.

Local drafts use account/region/deployment-scoped non-synchronizing, unlocked-only device Keychain storage. Review compares the exact draft, account, epoch, role revision, target and generation. A persistent pending intent is written before synthetic dispatch; uncertain outcomes survive navigation/re-authentication and cannot be retried or cleared through title matching. No receipt endpoint is invented. Prefab has thirteen exact source scene IDs and source state/profile/dice/gain/restore semantics, but its view is an explicit local narrative-state preview rather than complete gameplay. No live backend/provider, publication, uploads, location/sensor actions, rewards or configuration change occurred.

The guide's Roam destination was corrected to actual tab tag 3, and a source assertion compares the mapping against real tab tags. Existing Social numeric reward-total handling, scoped CN session, order lifecycle, Roam, team, merchant/club operations and previous modules are preserved.

Added 65 authored core methods, ten synthetic UI methods, 21 module source checks and 211 bilingual keys. Including the concurrent one-test Social numeric-total fix, inventory is 1,200 authored core methods, 193 UI methods in 28 classes and 2,561 keys. All six UI shards remain exhaustive (33/33/33/31/31/32). All 207 source-contract checks, 16 tooling tests, 14 parser self-tests, deterministic project/scaffold and whitespace checks pass. Twenty-three new/edited Swift files parse without recovery; full-tree supplementary parsing retains the same ten pre-existing diagnostics in six files across 457 files. Swift compiler/XCTest/Xcode, simulator/UI/screenshots, actual accessibility/device/Keychain and live acceptance remain NOT_RUN. No publication or CI run occurred. See docs/template-authoring-migration.md and docs/template-authoring-validation.json.


### Source-backed operation adapters integrated (2026-10-01 21:05 UTC)

Project, Club, Merchant and Team now have injectable dormant HTTPTransport adapters rather than permanent throw-only placeholders where the Flutter contract is known. Exact JSON/multipart methods, owner scopes, permission/role/baseline/quota checks and scalar/teamId acknowledgments are preserved. Project/Team acknowledge separately from simulation and persist dispatch-start markers; Club/Merchant use minimal deployment/account/target journals. Merchant story is two sequential writes: ambiguous first response stops the second write, and partial completion remains locked. No receipt, reconciliation, retry-key or join-mode endpoint was invented. All default production grants remain absent and no real operation occurred.

Team's factory can consume an independently reviewed scoped read grant and typed OrderLifecycleTeamSource, rereading the exact owned registration before creating context; both inputs default to absent. Current Social, Template authoring, region/CN session and prior module integrations were retained by additive patches from current main files. Existing Project ticket identities and revision protections were not changed.

Added 24 fake-transport XCTest methods, seven source checks and 11 bilingual keys. Inventory: 1,224 authored core methods, 193 UI methods in 28 classes, 2,572 keys. Six UI shards remain unchanged (33/33/33/31/31/32). Structural/scaffold, 214 source-contract checks, 16 tooling tests, 14 parser self-tests and whitespace checks pass. All 22 new/edited Swift files parse without recovery; full-tree parsing retains the same 10 prior diagnostics in six files across 461 files. Swift/Xcode compilation, XCTest, UI/simulator/screenshots/device, actual persistence and live backend acceptance remain NOT_RUN. No remote writes or CI run occurred. See docs/operation-adapters-module.md and docs/operation-adapters-verification.json.

## 2026-10-01 21:24 UTC — Play runtime first slice integrated locally

Added source-backed dormant classic/branch completion, run timer persistence and tombstones, mode-2 stages, hints, ending/reward/leaderboard, leader controls, advanced idempotent runtime, PLAYER command/receipt recovery, circle record/answer readback and device/stopwatch/stillness state machines. CLUB director domain contracts/coordinator are included; dedicated director UI and the live-prefab bridge are still being finished separately. Existing narrow PlaySessionView is retained. Activity detail has a separate runtime destination when configured, and the DEBUG `playExperience` module exercises injected in-memory transport only.

Production PlayExperienceService capabilities stay empty. No network, location, camera, photo, microphone, media upload, provider, financial or remote action was executed. Write-journal persistence beyond the injected memory stores and retained controllers remains an activation gate; source endpoint coverage is not page parity.

Verification of the integrated local tree:
- Structural/project/catalog check PASS: 392 App/Core/UI Swift source files, 2,737 bilingual keys
- Python contract checks PASS: 231; tools tests PASS: 16
- Authored Swift Core tests: 1,255 (+31); authored UI tests: 200 (+7), distributed exhaustively across the existing six shards (34/34/34/33/32/33)
- Focused supplementary Tree-sitter check PASS: 20 new/modified Swift files, zero recovery diagnostics
- Whole-tree supplementary parser remains FAIL: 10 existing diagnostics in six untouched files; these are recorded grammar diagnostics, not Swift compiler findings. No filters or test exclusions were added
- Swift tests, Xcode builds, UI/device/accessibility/live-backend acceptance: NOT_RUN (no Swift/Xcode toolchain here)
- Swift Package macOS test minimum is now 14 for the new Observation-based coordinators; app minimum remains iOS 17

This local addition is later than the parent's frozen 1,224-Core/193-UI publication snapshot. It is not claimed to have been pushed or covered by that snapshot's CI. See docs/play-experience-module.md and docs/play-experience-verification.json.

## 2026-10-01 21:30 UTC — Club governance workspace integrated locally

Added a separately scoped club workspace with 34 source-backed reads, 23 executable dormant mutation adapters and isolated group-code media GET. Host profile drafts, CRM/customer/check-in records, series/occurrences/roster/attendance, v2 role assignments/governance/cases/notifications, club-specific topic/story/answer projection, contribution rankings, compensation editions, settlement verification and dissolution-blocker states now have mounted native destinations. The entry is outside the old owner/admin gate; access/me role and event permissions decide individual operations. One AppSession-lived coordinator binds immutable reviews to account/epoch/namespace/target facts and retains unknown/acknowledged-operation locks. Production write/media grants remain hard-off.

The existing Play first slice, operation adapters, Social, Template, six UI shards and Package macOS 14/iOS 17 minimums were preserved. No real messages, role/membership changes, attendance, refunds/dissolution, provider actions, credentials/media transmission or remote writes were performed. Club post/comment authoring, authoritative financial recovery/compensation confirmation, identity registration/upload, live group-code behavior and complete platform/visual acceptance remain explicit gaps; existing ClubOperations and Play/Merchant ownership boundaries are retained.

Local evidence:
- Deterministic project/scaffold PASS: 405 App/Core/UI Swift files and 3,064 English/Chinese keys
- 243 Python source-contract checks and 16 tooling tests PASS; module source/encoding/permission/catalog checks PASS
- Authored inventory: 1,313 core tests (+58), 206 UI tests (+6), 30 UI classes; six exhaustive shards contain 35/35/34/34/34/34 tests
- Focused pinned Tree-sitter PASS: 20 additive/modified Swift files, no recovery diagnostics
- Full-tree parser: 493 Swift files; the same ten existing recovery diagnostics in six untouched files remain. No filters or exclusions were introduced
- Swift/Xcode compilation, XCTest, simulator/UI/screenshots, device/accessibility and live-backend acceptance: NOT_RUN (toolchains absent)
- Whitespace check PASS. No push, branch/ref update or CI execution by this worker

This local batch is later than the parent's frozen older publication snapshot and is not claimed covered by its CI. See docs/club-governance-migration.md, docs/club-governance-integration.md and docs/club-governance-verification.json.

## 2026-10-02 00:23 UTC — Four recovered modules integrated locally

Merged the verified Play director/prefab/preference extension plus merchant business, merchant content and cooperation flows. Shared session/navigation files were edited additively; default capability gates, session/role fencing, distinct IDs, scoped storage, macOS 14/iOS 17 floors and six exhaustive UI shards remain. Activity journey/director, merchant workspaces and source-typed supply previews are reachable. Active supply without known source terms stays blocked. Computed/dynamic localization integration defects were fixed without relaxing validation or runtime gates.

Final local evidence: 1,497 authored Core and 230 authored UI tests in 35 classes; six shards 39/39/39/38/38/37; 3,923 bilingual keys. Deterministic project/scaffold, 271 Python contracts (12 new integration checks), 16 tooling tests, 14 pinned-parser advisory tests, merchant source gates and existing module source checks PASS. Focused parser: 70 Swift files, zero diagnostics. Whole-tree parser: 547 files, the same ten existing diagnostics in six files, unsuppressed. Whitespace check PASS. Authored Swift tests are not claimed passed: Swift/Xcode/XCTest, simulator/device/accessibility and live backend/provider validation are NOT_RUN. No remote writes or CI run occurred here.

See `docs/recovered-modules-integration.md`, `docs/recovered-modules-integration-manifest.json` and the regenerated `docs/ui-shard-inventory.json` for exact scope and evidence. This integration is not covered by any earlier published commit or CI result.

## Official event actions integration — 2026-10-02

- Added unsent event draft editing/publishing; explicit audience/channel unified or role-specific broadcast review; merchant-selection invitation review; source-status signup/legacy completion/arrival review; and OFFICIAL versus MERCHANT/CLUB invitation responses
- Added exact injected dormant POST adapters and invitation tracking/click adapters, immutable fresh-snapshot review, account/epoch/environment isolation, disk-before-send persistent unknown locks, and server-only participation/reward facts
- Existing official readers stay read-only. Home → official browser now passes an optional review coordinator to published/detail/inbox hosts. AppSession permits review only, with write closure disabled; merchant selection/arrival integration remains blocked until verified candidates and approved roam/location evidence are supplied. Synthetic fixture bypasses production AppSession
- Added 74 bilingual keys, 24 authored core and 3 authored UI tests. Cumulative inventory: 1521 core, 233 UI, 3997 bilingual keys. Six UI shards and Package iOS17/macOS14 baseline preserved
- Local source checks and supplementary parsing are passing; Swift/Xcode/UI/device/accessibility/runtime are NOT_RUN because toolchain/simulator are unavailable. No remote writes or real invitations/broadcasts/participation/location actions occurred
- Explicit gaps: supplied official API has no persisted-event edit endpoint; merchant invitation authoring is limited to source-tested merchantIds; acknowledged participation/party/arrival locks need a separately reviewed authoritative reconciliation policy. See docs/official-action-integration.md

Official-action final integration checks: 276 Python contract tests and 16 tool tests PASS; 243 module source assertions PASS; deterministic structural regeneration PASS; all 14 changed Swift files parse cleanly. Whole-checkout supplementary Tree-sitter check reports ten diagnostics in six unrelated files (AuthChannelView, MerchantHomeView, MessagingComponents, RegistrationSheetView, RegistrationUIForm, ParticipantCoordinatorTests); it is not a Swift compiler pass. Six-shard dry-run covers all 233 UI tests exactly once. No GitHub publication performed.


## Nearby/public-team integration — 2026-10-02

Added source nearby/apply/withdraw/applications/handle/my-applications contracts, native cards/mine/applicant/review screens, server-expiry semantics and exact errorCode transitions. Team retains my-team/detail/invitation/create/join/quit/kick/disband ownership; typed Team/Roam bridges preserve distinct team/applicant/activity/owner identities and manual-only browsing coordinates. Normal Team/Roam entries, private session binding, existing destination routing and an isolated DEBUG fixture are installed. The read adapter accepts explicit deployment/account/namespace/path approval and injected HTTPTransport; default grants remain absent. Mutations remain concrete-fake-only; no real application or membership/location action occurs. Unknown results persist an account-scoped replay lock; no receipt endpoint, join-mode setter or retired hangout is invented.

Added 22 authored Core methods, 3 UI methods and 82 bilingual keys. Exact cumulative inventory: 1543 Core / 236 UI methods in 37 UI classes / 4079 keys. Six exhaustive shards: 41/39/39/39/39/39. All 289 aggregate source contracts, 16 tooling tests, 14 parser advisory tests and module source gates PASS; deterministic project/scaffold PASS with 469 App/Core/UI Swift references. Seventeen changed/new Swift files parse cleanly. Whole-tree supplementary parse covers 567 Swift files with the same ten existing diagnostics in six unrelated files, unsuppressed. Swift compiler, XCTest/Xcode, simulator/UI/screenshots, device/accessibility and live backend acceptance remain NOT_RUN. No remote writes or CI execution occurred. Existing OfficialActions and all previous modules were preserved. See docs/nearby-team-source-map.md and docs/nearby-team-verification.json.


## 2026-10-02 — Coupon author and management integration

Added source-backed publication draft/review, owned definition list/detail and stop-distribution review through the existing marketing/recruiting host. Distinct definition IDs do not replace claimed-history identities. Exact injectable read and dormant publish/stop HTTP serialization, nullable money/counts, immutable review, fresh owner/publisher checks and persistent cross-epoch unknown-outcome locks are present. AppSession supplies no read approval, publisher grant or write enablement by default. The isolated DEBUG fixture never constructs the production session. No claim route, dynamic-code owner, payment, receipt or backend transition was invented; claim and fresh publisher entitlement contracts remain explicit gaps.

Inventory: 1,624 authored Core tests (+22), 250 authored UI tests (+5) in 40 classes, 4,328 bilingual keys (+71), six exhaustive shards at 41/41/42/42/42/42. All 313 aggregate source contracts, 16 tooling tests, 14 parser-advisory tests and all module source gates PASS; deterministic project/scaffold PASS at 498 App/Core/UI references. Focused supplementary parse: 14 Swift files, zero diagnostics. Swift/Xcode compilation, XCTest, simulator/UI/device/accessibility and live backend acceptance remain NOT_RUN. No network, backend/provider or remote repository action was taken. See docs/coupon-management/INTEGRATION.md and integration-manifest.json for the additive scope and exact evidence.

## 2026-10-02 — Source-backed IM expansion integration

Added exact injected dormant HTTP adapters for conversation start, read, mute, image upload and image/route/location card send. Ordinary Account → Messages navigation now carries stable account/epoch/conversation owners, a start-conversation entry, current-history action review, image selection/upload/send consent stages, and typed native card actions. Existing text-send, conversation/history and SocialMessageMedia opt-in image preview remain in place. Trusted review results require system sender ID 0, including the existing preview badge. Concrete HTTP service defaults writes OFF, AppSession supplies service:nil and the native image picker is dormant. No backend, upload, media permission, external link, microphone/camera/photo or socket action was performed.

Retained source explicitly has no WebSocket/IM voice contract; neither feature is counted as migrated. Explicit manual-refresh generation gates are provided, not a realtime replacement. Unknown writes retain immutable intent/client IDs within their exact session owner; crash/relaunch durable upload recovery and cross-epoch anti-replay remain live-enablement gaps alongside approved bounded no-redirect transport and a vetted native image provider. No server contract was invented.

Inventory: 1,636 authored Core tests (+12), 252 authored UI tests (+2) in 41 UI classes, 4,364 bilingual keys (+36). Six exhaustive UI shards cover 43/41/42/42/42/42 methods. All 322 aggregate source contracts, 16 tooling tests, 14 parser-advisory tests and all 13 module source gates PASS. Deterministic project/scaffold PASS at 506 App/Core/UI Swift references. Focused supplementary parse: 15 changed/new Swift files, zero diagnostics. Whole-tree parse: 609 Swift files, the same ten pre-existing diagnostics in six unrelated files, unsuppressed. Swift compiler, XCTest/Xcode, simulator/UI/device/accessibility and live backend acceptance remain NOT_RUN. See docs/im-expanded-integration.md and docs/im-expanded/integration-manifest.json.

## 2026-10-02 — integrated native repair batch (offline only)

Integrated object cards/badges, nearby executable writes, protected cooperation adapters, merchant engagement extension and unknown-outcome repair, plus publishing/wallet request-credential binding repair. Current IM work was preserved. The earlier nearby fake-only limitation is superseded: exact injectable HTTP writes now exist but default write approvals/evidence are nil. Object API/media and all live/device effects remain dormant.

PASS: 343 contracts, 16 tooling, 14 advisory, scaffold, 13 existing module scripts and four packet checks. Focused Tree-sitter: 56 changed/new files zero diagnostics; edited MerchantHomeView retains its one historical recovery in full parse. Full parse remains FAIL with the same unsuppressed 10 historical diagnostics across 6 of 645 Swift files. Swift/Apple/runtime/backend validation NOT_RUN. Authored inventory: 1,758 Core methods; 263 UI methods/43 classes; 4,549 bilingual keys; six shards. Exact scope and remaining invitation-router/receipt-consumer boundaries: `docs/native-repair-batch-integration.md`.

## 2026-10-02 — Native safety and app-unit target closeout (offline)

Integrated app-hosted QuestifyAppUnitTests wiring, consent-first NPC voice sample capture/upload seams, metadata-only durable image upload recovery, and disabled bounded streaming transport. The normal resource editor visibly shows the missing voice-configuration gate; no production capture limits were invented. Image and voice upload permissions remain independent. Unknown/acknowledged upload recovery stays locked without an authoritative manual recovery policy; WeChat SDK adapter remains absent.

PASS: 414 source contracts, 24 tooling tests, 14 parser-advisory tests, prior/new module checks, deterministic project/scaffold, all six UI shard dry-runs and app-unit target inclusion. Focused parser: 26 changed Swift files, zero diagnostics. Whole-tree parser remains FAIL: 804 files, same ten historical diagnostics unsuppressed. Authored inventory: 2,125 Core methods, 313 UI/56 classes, 12 app-unit methods, 5,145 bilingual keys. All Apple/compiler/XCTest/runtime/live-provider acceptance NOT_RUN. No remote writes or CI execution. See docs/native-closeout/integration.md and exact hash/check manifests.

## 2026-10-02 02:41 UTC — Independent final local checkpoint

All finite source closeout packets are integrated. Independent verification: 414 contracts, 24 tooling tests, 14 advisory self-tests and all invoked module gates pass. Six dry-run shards cover all 313 UI methods once; deterministic project/scheme output is unchanged. Canonical UI inventory was refreshed from actual sources. Whole parser remains FAIL with ten historical diagnostics; Apple/Swift/XCTest/device/live acceptance remains NOT_RUN. Remote remains b754aa1 with the older failed CI; no new commit/ref/CI is claimed. WeChat SDK adapter remains unimplemented pending authoritative interface evidence; live configuration and unknown-upload reconciliation gates remain. See docs/LATEST_VERIFICATION.md and the preserved independent logs.

## 2026-10-08 — six-domain source increment, awaiting exact-commit Apple verification

Base: published migration commit `6eb3af76d977537a455cc203197125db78b8c7e0`.
This batch restores previously saved media source and adds bounded improvements under the six responsibility domains. It does not complete all requirements in the overall implementation plan.

- W01/W09 compatibility: Square's file-part bound now matches the repository backend's 10 MiB limit, and unsupported WebP-only selections are rejected before reading/uploading. JPEG/PNG representations retain actual type/decoder checks. The backend's 20 MiB multipart request limit is distinct; deployment overrides and actual uploads remain unverified.
- W02 professional editing: image-only cover (3:4) and gallery (16:9) selection, cropping, inspection, explicit upload/readback application and local draft saving use a separate, default-disabled Topic capability. Maximum nine gallery entries and existing URL/CSV constraints are preserved. Production approval/configuration and live upload are not established; video is not delivered.
- AI26: merchant NPC foreground interruption clears local conversation data; an explicitly requested fresh conversation may resume only under the same still-authorized owner. Old send/retry callbacks cannot act on the new request. Revocation is terminal. New Core regression cases are authored, not executed here. The newly authored UI extension remains a separately saved pending patch; all baseline UI test sources are unchanged in this batch.
- W20.16/W13: official CITY snapshot reads recover once from a snapshot conflict, cancel old reads on disappearance/backgrounding and reacquire authoritative current state for the active owner. This does not implement occupation, business turns, charging, challenges or rewards.
- W16: matched quit/disband receipts retire the current Team workflow's member projection and old action tokens only after successful journal cleanup. Unknown outcomes stay locked. This is not persistent cross-instance membership truth, stranger-meeting verification, real-name integration, dynamic QR or NFC completion.
- W06/W07: merchant Home permissions are loaded through appearance/request/reader/authorization-generation ownership. Stable typed destination hosting preserves existing authorized navigation without retaining stale Home grants. No financial, redemption or reward write is added.

Local evidence on the combined source: 2,211 Python source-contract tests, with 46 explicitly skipped external-source comparisons and all remaining tests passing; 9 project-target checks passed after final deterministic project registration. Structural checks passed for 1,419 Swift source files and 8,093 bilingual keys. An earlier 465-test tooling pass reported only the then-stale generated-project comparison as failing; that check was subsequently regenerated and rerun in the 9-test target suite. This is not a fresh all-tooling green result on the final tree.

These are static/tooling checks, not Swift compilation or App execution. Swift/Core/AppUnit/UI, simulator and physical-device verification of this batch are pending the exact published SHA. Run 131's successful builds and failed runtime tests apply only to the preceding `6eb3af76` commit. All existing required CI gates and test profiles are retained; a build-only result cannot authorize merging main.

The earlier missing CI131 repair workspace was not reconstructed from summaries. Only hash-verified saved originals and newly authored/reviewed changes are in this batch. Cancelled Next50 work is excluded, and the twenty externally reserved Muse paths remain byte-identical to the base.
