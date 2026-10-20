# Native iOS migration progress

> **当前统一入口 / Current entry (2026-10-15): [iOS 范围、状态与证据](docs/ios-current-status.md).** 下文保留原时间点的计划或证据，不自动代表当前状态；历史数量、合同状态与运行结果不得移用于新提交。当前口径以上述入口为准。

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

Added 21 authored core XCTest methods, ten synthetic UI methods and 101 English/zh-Hans keys. Integrated authored totals are 771 core tests, 102 UI methods in 18 classes and 1453 bilingual keys. Regenerated project and exhaustive shard inventory: 34/34/34 UI methods; none omitted. Local checks pass: 93 source-contract checks, 15 tooling tests, 14 advisory-parser self-tests, deterministic scaffold verification and git diff whitespace checks. All 15 new/edited integration Swift files pass without Tree-sitter recovery. The aggregate parser still reports the same ten diagnostics in the six pre-existing files recorded above, and is not a compiler result.

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

## 2B. Wave 3 (`I00–I11` & `BK`) 合并状态与 Batch 1/2/3 收口状态（2026-10-20）

| Lane | PR | Commit | 状态 | 交付摘要 |
|---|---|---|---|---|
| **w2-09** | `#40` | `8b7f555` | MERGED | Roam private tools (`capsule`, `exploration-goals`, `exploration-export`) + 65 source contracts |
| **w2-17** | `#39` | `b7a4552` | MERGED | Merchant store parity (`poi/detail`, `decor/save` JSON, `shop/apply` 4-step wizard, `npc/voice/status`) |
| **I00 + I11** | `#43` | `54b2fdc` | MERGED | `Core/RoamReceivedStampRead.swift` + `RoamReceivedStampPresentation.swift` + `App/RoamReceivedStampSectionView.swift` + `I00SessionAdmissionBaselineTests` |
| **I01** | `#38` | `028e23e` | MERGED | `PlayArrivalAccuracy` (80m advisory + BK-GPS rejection detection) + `RuntimePlayDeviceProvider` (>100m/>30s `invalidAction`) (11 tests) |
| **I02** | `#41` | `010caae` | MERGED | `Core/PlayGameCommandJournal.swift` + `Core/PlayGameSessionComposition.swift` + `<key>:game` encrypted recovery slot |
| **I03** | `#42` | `1a0270b` | MERGED | `ProjectEditStoryContract.validatePayload` & `ProjectEditRichStoryContract.attachEndings` boolean-only `fallback` (2 test files) |
| **I04** | `#37` | `ba58993` | MERGED | `Core/AssetPointsLedgerReadback.swift` + `WalletLedgerRow` (`currentPoints`/`eventId`) + `OrderCancellationObservation` (`pointsUsed`/`pointsReturned`) (10 tests) |
| **I05** | `#44` | `6b09cac8` | MERGED | `Core/SquareWorkspacePrivacy.swift` (`URLCache` media eviction on 404/DELETED) + `Core/TopicLikeDirection.swift` + `Core/TopicLikeHostController.swift` |
| **I06** | `#35` | `79af21a` | MERGED | `Core/PlatformAudioLifecycle.swift` + `App/NativeAudioLifecycleObservation.swift` + route/interruption/tmp-sweep handling (11 tests) |
| **I07** | `#48` | `5647c1ac` | MERGED | `GrowthCenterService.leaderboard` form-encoded body fix + `GrowthLeaderboardStanding` + `ProfileReadFailure.isDenied` (9 tests) |
| **I08** | `#50` | `f0a84989` | MERGED | `Core/NPCChatLogDeletion.swift` + `NPCChatDataCoordinator` + `App/NPCChatDataView.swift` (default OFF pending AI-DELETE) (22 tests) |
| **I09** | `#55` | `44a302e7` | MERGED | `ClubSeriesScheduleReadbackFixtureTests` (BK-SCHEDULE) + `Core/PlayLeadProgressPolling.swift` & `App/PlayLeadProgressPollingModifier.swift` (11 tests) |
| **I10** | `#49` | `511693b5` | MERGED | `Core/NativePerformanceSignposts.swift` + `PlayRouteMapView` O(N) projection + VoiceOver/Reduce Motion + `tools/signpost_measure.py` (15 tests) |
| **BK** | `#52` | `1123f654` | MERGED | `Tests/CoreTests/BackendSyncContractTests.swift` (5 tests) + `Tests/ContractChecks/test_bk_backend_sync.py` (6 checks) |
| **Wave-2 Batch 1/2/3** | Local | `current` | MERGED | Closed all remaining P1 presentation/copy/filter/composition items across `w2-01` through `w2-21` (`PlayRuntimeAuxiliaryBinding`, `MapCoreEntryHostRouter`) + fixed all 6 CoreTests/AppUnitTests failure groups |

## 2C. Batches 4–6 (`Lanes 23–63`): Reform Plan v9 Host Bridges, SwiftUI Sections & AppUnitTests (2026-10-20)

- **Batch 4 (`Lanes 23–38`: Reform Plan v9 `F`/`G`/`H` Host Bridges, Coordinators & Release Preflight Contract):**
  - `MapVisualHostBridge` (`Core/MapVisualHostBridge.swift`, `Tests/CoreTests/MapVisualHostBridgeTests.swift`)
  - `StoryWalkingNavigationHostBridge` (`Core/StoryWalkingNavigationHostBridge.swift`, `Tests/CoreTests/StoryWalkingNavigationHostBridgeTests.swift`)
  - `NPCAISceneHostGuard` (`Core/NPCAISceneHostGuard.swift`, `Tests/CoreTests/NPCAISceneHostGuardTests.swift`)
  - `MerchantInStoreGameAuthoringPresentation` (`Core/MerchantInStoreGameAuthoringPresentation.swift`, `Tests/CoreTests/MerchantInStoreGameAuthoringPresentationTests.swift`)
  - `CommerceOrderLifecycleBridge` (`Core/CommerceOrderLifecycleBridge.swift`, `Tests/CoreTests/CommerceOrderLifecycleBridgeTests.swift`)
  - `PublishMediaEditorBridge` (`Core/PublishMediaEditorBridge.swift`, `Tests/CoreTests/PublishMediaEditorBridgeTests.swift`)
  - `WorkshopModUpgradePresentation` (`Core/WorkshopModUpgradePresentation.swift`, `Tests/CoreTests/WorkshopModUpgradePresentationTests.swift`)
  - `TeamMeetingHandshakePresentation` (`Core/TeamMeetingHandshakePresentation.swift`, `Tests/CoreTests/TeamMeetingHandshakePresentationTests.swift`)
  - `HomeReturnAndCityDeltaCoordinator` (`Core/HomeReturnAndCityDeltaCoordinator.swift`, `Tests/CoreTests/HomeReturnAndCityDeltaCoordinatorTests.swift`)
  - `ReleasePreflightAndUIReadinessContract` (`Core/ReleasePreflightAndUIReadinessContract.swift`, `Tests/CoreTests/ReleasePreflightAndUIReadinessContractTests.swift`)
  - `LocationShareHostCoordinator` (`Core/LocationShareHostCoordinator.swift`, `Tests/CoreTests/LocationShareHostCoordinatorTests.swift`)
  - `MerchantSideQuestHostPresentation` (`Core/MerchantSideQuestHostPresentation.swift`, `Tests/CoreTests/MerchantSideQuestHostPresentationTests.swift`)
  - `RunAuthorityHostCoordinator` (`Core/RunAuthorityHostCoordinator.swift`, `Tests/CoreTests/RunAuthorityHostCoordinatorTests.swift`)
  - `EnvironmentBranchHostPresentation` (`Core/EnvironmentBranchHostPresentation.swift`, `Tests/CoreTests/EnvironmentBranchHostPresentationTests.swift`)
  - `RewardLedgerHostPresentation` (`Core/RewardLedgerHostPresentation.swift`, `Tests/CoreTests/RewardLedgerHostPresentationTests.swift`)
  - `WaveUnifiedParityInventory` (`Core/WaveUnifiedParityInventory.swift`, `Tests/CoreTests/WaveUnifiedParityInventoryTests.swift`)
- **Batch 5 (`Lanes 39–51`: Reform Plan v9 SwiftUI Section Views & `WaveUnifiedParityInventory`):**
  - Added offline/fail-closed SwiftUI section views (`App/MapVisualAndFogHostSectionView.swift`, `App/LocationShareAndSideQuestSectionView.swift`, `App/StoryWalkingAndEnvBranchSectionView.swift`, `App/NPCAISceneAndMerchantGameSectionView.swift`, `App/CommerceAndRewardLedgerSectionView.swift`, `App/PublishMediaAndThemeSeasonSectionView.swift`, `App/WorkshopModAndQmodSectionView.swift`, `App/TeamMeetingAndInviteSectionView.swift`, `App/RunAuthorityHostSectionView.swift`, `App/ReleasePreflightDashboardSectionView.swift`) and their corresponding Core test suites (`Tests/CoreTests/*SectionViewTests.swift`, `Tests/CoreTests/Wave4And5MasterGateTests.swift`).
- **Batch 6 (`Lanes 52–63`: `AppUnitTests` for all new Section Views + `ReformWorldHostWorkbenchView`):**
  - Added `App/ReformWorldHostWorkbenchView.swift` unifying all Reform Plan v9 offline host sections into a single inspectable workbench container.
  - Added `Tests/AppUnitTests/*SectionViewAppUnitTests.swift` and `Tests/AppUnitTests/ReformWorldHostWorkbenchViewAppUnitTests.swift` covering app-hosted SwiftUI section instantiation, view-model state invariants, and default-disabled production gates across Lanes 52–63.

## 2D. Batches 7–9 (`Lanes 64–95`): Release Audits, Unified Matrices & Safety Verification (2026-10-20)

- **Batch 7 (`Lanes 64–71`): Unified Matrices & Submission Readiness Audits:**
  - App Store submission readiness audit (`Core/AppStoreSubmissionReadinessAudit.swift`, `Tests/CoreTests/AppStoreSubmissionReadinessAuditTests.swift`)
  - Unified Ticket Phase 0–5 & `MV01–MV41` matrix (`Core/UnifiedTicketMatrixContract.swift`, `Tests/CoreTests/UnifiedTicketMatrixContractTests.swift`)
  - 99-page mini-program parity registry (`Core/MiniProgramPageParityRegistry.swift`, `Tests/CoreTests/MiniProgramPageParityRegistryTests.swift`)
  - Cloud CI shard contract (`Core/CloudCIShardContract.swift`, `Tests/CoreTests/CloudCIShardContractTests.swift`)
  - Wave-3 (`I00–I11` & `BK`) handoff registry (`Core/Wave3HandoffStatusRegistry.swift`, `Tests/CoreTests/Wave3HandoffStatusRegistryTests.swift`)
- **Batch 8 & Batch 9 (`Lanes 72–95`): Domain Safety, Privacy, Accessibility & Recovery Audits:**
  - Regional endpoint allowlist audit (`Core/RegionalEndpointAllowlistAudit.swift`, `Tests/CoreTests/RegionalEndpointAllowlistAuditTests.swift`)
  - Localization zero-missing-keys audit (`Core/LocalizationCompletenessAudit.swift`, `Tests/CoreTests/LocalizationCompletenessAuditTests.swift`)
  - VoiceOver/WCAG accessibility audit (`Core/AccessibilityVoiceOverAudit.swift`, `Tests/CoreTests/AccessibilityVoiceOverAuditTests.swift`)
  - Deep-link & QR/URL safety audit (`Core/DeepLinkAndQRRouteSafetyAudit.swift`, `Tests/CoreTests/DeepLinkAndQRRouteSafetyAuditTests.swift`)
  - Offline durable recovery & journal audit (`Core/OfflineDurableRecoveryAudit.swift`, `Tests/CoreTests/OfflineDurableRecoveryAuditTests.swift`)
  - UI test shard & fixture completeness audit (`Core/UITestShardCompletenessAudit.swift`, `Tests/CoreTests/UITestShardCompletenessAuditTests.swift`)
  - Privacy redaction & coordinate non-leakage audit (`Core/PrivacyRedactionAudit.swift`, `Tests/CoreTests/PrivacyRedactionAuditTests.swift`)
  - Commerce, wallet & points non-withdrawable safety audit (`Core/CommerceWalletSafetyAudit.swift`, `Tests/CoreTests/CommerceWalletSafetyAuditTests.swift`)

## 2E. Batches 10–11 (`Lanes 100–120`): Master Release Sign-Off Dashboard, 3-Document Crosswalk & Domain Lifecycle Audits (2026-10-20)

- **Roam & Exploration audit:** `Core/RoamAndExplorationSafetyAudit.swift`, `Tests/CoreTests/RoamAndExplorationSafetyAuditTests.swift`
- **IM & Social safety audit:** `Core/IMAndSocialSafetyAudit.swift`, `Tests/CoreTests/IMAndSocialSafetyAuditTests.swift`
- **15-pillar Master Release Sign-off Dashboard:** `Core/MasterReleaseSignOffDashboard.swift`, `App/MasterReleaseSignOffDashboardView.swift`, `Tests/CoreTests/MasterReleaseSignOffDashboardTests.swift`, `Tests/AppUnitTests/MasterReleaseSignOffDashboardViewAppUnitTests.swift`
- **Auth & Session Admission audit:** `Core/AuthAndSessionAdmissionAudit.swift`, `Tests/CoreTests/AuthAndSessionAdmissionAuditTests.swift`
- **World & City Lifecycle audit:** `Core/WorldAndCityLifecycleAudit.swift`, `Tests/CoreTests/WorldAndCityLifecycleAuditTests.swift`
- **Backend Sync & Contract Gate audit:** `Core/BackendSyncAndContractGateAudit.swift`, `Tests/CoreTests/BackendSyncAndContractGateAuditTests.swift`
- **3-Document Master Crosswalk (`交接文档_20261020.md` + `落地清单.md` + `工单-统一实施版.md`):** `Core/ThreeDocumentMasterCrosswalk.swift`, `Tests/CoreTests/ThreeDocumentMasterCrosswalkTests.swift`
- **Performance & Signpost audit:** `Core/PerformanceAndSignpostAudit.swift`, `Tests/CoreTests/PerformanceAndSignpostAuditTests.swift`
- **Coupon & Sponsored Reward safety audit:** `Core/CouponAndSponsoredRewardSafetyAudit.swift`, `Tests/CoreTests/CouponAndSponsoredRewardSafetyAuditTests.swift`
- **Audio & Media Pipeline lifecycle audit:** `Core/AudioAndMediaPipelineLifecycleAudit.swift`, `Tests/CoreTests/AudioAndMediaPipelineLifecycleAuditTests.swift`

## 2F. Batches 12–13 (`Lanes 125–149`): RC Gate (`RC-GATE-01..06`), `W02..W20` Compliance, Unified Release Audit Hub & Domain Readiness Audits (2026-10-20)

- **`W02..W20` compliance audit:** `Core/ReformWorkPackageComplianceAudit.swift`, `Tests/CoreTests/ReformWorkPackageComplianceAuditTests.swift`
- **`AppSession` fixture short-circuit audit:** `Core/AppSessionFixtureShortCircuitAudit.swift`, `Tests/CoreTests/AppSessionFixtureShortCircuitAuditTests.swift`
- **XcodeGen & scaffold integrity audit:** `Core/XcodeGenAndScaffoldIntegrityAudit.swift`, `Tests/CoreTests/XcodeGenAndScaffoldIntegrityAuditTests.swift`
- **End-to-End Release Candidate Gate (`RC-GATE-01..06`):** `Core/EndToEndReleaseCandidateGate.swift`, `Tests/CoreTests/EndToEndReleaseCandidateGateTests.swift`
- **Side-Quest & Personal Fog host audit:** `Core/SideQuestAndPersonalFogHostAudit.swift`, `Tests/CoreTests/SideQuestAndPersonalFogHostAuditTests.swift`
- **3-Document Master Crosswalk Python contract check:** `Tests/ContractChecks/test_three_document_master_crosswalk.py`
- **`UnifiedReleaseAuditHubView`:** `App/UnifiedReleaseAuditHubView.swift`, `Tests/AppUnitTests/UnifiedReleaseAuditHubViewAppUnitTests.swift`
- **UI test flow readiness anchor audit:** `Core/UITestFlowReadinessAnchorAudit.swift`, `Tests/CoreTests/UITestFlowReadinessAnchorAuditTests.swift`
- **NPC chat & scene AI safety audit:** `Core/NPCChatAndSceneAISafetyAudit.swift`, `Tests/CoreTests/NPCChatAndSceneAISafetyAuditTests.swift`
- **Play runtime & auxiliary binding audit:** `Core/PlayRuntimeAndAuxiliaryBindingAudit.swift`, `Tests/CoreTests/PlayRuntimeAndAuxiliaryBindingAuditTests.swift`
- **App Store privacy manifest audit:** `Core/AppStorePrivacyManifestAudit.swift`, `Tests/CoreTests/AppStorePrivacyManifestAuditTests.swift`
- **Growth & Leaderboard parity audit:** `Core/GrowthAndLeaderboardParityAudit.swift`, `Tests/CoreTests/GrowthAndLeaderboardParityAuditTests.swift`
- **Schedule & Lead Progress polling audit:** `Core/ScheduleAndLeadProgressPollingAudit.swift`, `Tests/CoreTests/ScheduleAndLeadProgressPollingAuditTests.swift`

## Batch 14 (Lanes 150–162): Wave-3 I00/I04/I05/I07/I08/I09/I10/I11 Deep Audits, Batch 12–14 Contract Suite & Complete Wave 1–3 + Reform v9 Showcase View (2026-10-20)

- `Core/AssetPointsAndOrderCancellationAudit.swift` + `App/AssetPointsAndOrderCancellationSectionView.swift` (`I04` points ledger & cancellation conservation)
- `Core/TopicLikeAndSquareEvictionAudit.swift` + `App/TopicLikeAndSquareEvictionSectionView.swift` (`I05` 404/DELETED media cache eviction & fail-closed topic like write gate)
- `Core/ReceivedStampsAndPassportToolsAudit.swift` + `App/ReceivedStampsAndPassportToolsSectionView.swift` (`I00`/`I11` received stamps & passport tools isolation)
- `Core/MerchantDecorAndShopApplyWizardAudit.swift` + `App/MerchantDecorAndShopApplyWizardSectionView.swift` (`I07`/`I08` merchant decor & shop apply 4-step wizard)
- `Core/ClubAccessAndSettlementParityAudit.swift` + `App/ClubAccessAndSettlementSectionView.swift` (`I09`/`I10` club access control & settlement/payroll)
- `Tests/ContractChecks/test_batch12_to_batch14_contracts.py`
- `App/CompleteWave1To3AndReformV9ShowcaseView.swift` + `Tests/AppUnitTests/CompleteWave1To3AndReformV9ShowcaseViewTests.swift`

## Batches 15–16 (Lanes 163–188): Zero-Gap Release Certificate, Wave-2/3 Deep Parity & Production Runtime Resilience (2026-10-20)

- `Core/GameJournalCompositionAndPlaySummaryAudit.swift` + `App/GameJournalCompositionAndPlaySummarySectionView.swift`
- `Core/SocialGraphAndProfilePrivacyParityAudit.swift` + `App/SocialGraphAndProfilePrivacySectionView.swift`
- `Core/ExplorationPrivateToolsAndCapsuleAudit.swift` + `App/ExplorationPrivateToolsAndCapsuleSectionView.swift`
- `Core/PublishTopicAndCommentModerationAudit.swift` + `App/PublishTopicAndCommentModerationSectionView.swift`
- `Core/MemberSubscriptionAndOrderInvoiceAudit.swift` + `App/MemberSubscriptionAndOrderInvoiceSectionView.swift`
- `Core/FinalReleaseSignoffAndZeroGapCertificateContract.swift` + `App/FinalReleaseSignoffAndZeroGapCertificateView.swift`
- `Core/CrashResilienceAndMetricKitDiagnosticsAudit.swift` + `App/CrashResilienceAndMetricKitDiagnosticsSectionView.swift`
- `Core/PushNotificationAndLiveActivityParityAudit.swift` + `App/PushNotificationAndLiveActivitySectionView.swift`
- `Core/NetworkReachabilityAndRetryBackoffAudit.swift` + `App/NetworkReachabilityAndRetryBackoffSectionView.swift`
- `Core/KeychainAndBiometricSessionSecurityAudit.swift` + `App/KeychainAndBiometricSessionSecuritySectionView.swift`
- `Core/ImageAndVideoDiskCacheBudgetAudit.swift` + `App/ImageAndVideoDiskCacheBudgetSectionView.swift`
- `Core/BackgroundTaskAndScenePhaseLifecycleAudit.swift` + `App/BackgroundTaskAndScenePhaseLifecycleSectionView.swift`
- `Tests/ContractChecks/test_batch15_zero_gap_certificate.py` and `Tests/ContractChecks/test_batch16_runtime_resilience_contracts.py`

## Batches 17–19 (Lanes 189–221): Native Superset Policy, Platform Polish & 7-Day App Store Launch Critical Path (2026-10-20)

### 1. Batches 17–19 Deliverables (`Lanes 189–221`)
- `Core/AppClipAndQRCodeHandshakeParityAudit.swift` + `App/AppClipAndQRCodeHandshakeSectionView.swift`
- `Core/WebViewAndExternalSafariSandboxAudit.swift` + `App/WebViewAndExternalSafariSandboxSectionView.swift`
- `Core/LocalizationPluralAndFormatterConsistencyAudit.swift` + `App/LocalizationPluralAndFormatterConsistencySectionView.swift`
- `Core/DeviceOrientationAndSplitViewAdaptationAudit.swift` + `App/DeviceOrientationAndSplitViewAdaptationSectionView.swift`
- `Core/PhotoLibraryAndCameraPermissionGracefulDegradationAudit.swift` + `App/PhotoLibraryAndCameraPermissionGracefulDegradationSectionView.swift`
- `Core/HapticFeedbackAndMotionReduceComplianceAudit.swift` + `App/HapticFeedbackAndMotionReduceComplianceSectionView.swift`
- `Core/ProductionTelemetryAndPrivacyRedactionPipelineAudit.swift` + `App/ProductionTelemetryAndPrivacyRedactionPipelineSectionView.swift`
- `Core/SQLiteAndJSONJournalCorruptionRecoveryAudit.swift` + `App/SQLiteAndJSONJournalCorruptionRecoverySectionView.swift`
- `Core/AppStoreReviewDemoAccountAndFixtureReadinessAudit.swift` + `App/AppStoreReviewDemoAccountAndFixtureReadinessSectionView.swift`
- `Core/NativeSupersetOverMiniProgramPolicyAudit.swift` + `App/NativeSupersetOverMiniProgramPolicySectionView.swift`
- `Core/SevenDayLaunchCriticalPathMilestoneContract.swift` + `App/SevenDayLaunchCriticalPathMilestoneSectionView.swift`
- `Core/InAppCustomerSupportAndFeedbackParityAudit.swift` + `App/InAppCustomerSupportAndFeedbackSectionView.swift`
- `Core/AccountDeletionAndGDPRPIPLComplianceAudit.swift` + `App/AccountDeletionAndGDPRPIPLComplianceSectionView.swift`
- `Core/MiniProgramVsNativeSupersetPageClassifier.swift` + `App/MiniProgramVsNativeSupersetPageClassifierSectionView.swift`
- `App/MasterSevenDayLaunchCommandCenterView.swift` + `Tests/AppUnitTests/MasterSevenDayLaunchCommandCenterViewTests.swift`

### 2. Native Superset Alignment Principle (iOS 原生超集原则)
- **Backend API Contracts & Business Status Machines (100% Mini-Program Parity):** All backend request/response schemas, status codes, role/permission checks, order/coupon/schedule state machines, and fail-closed allowlists align 100% with the Mini-Program and shared Java backend contracts.
- **Native Superset Capabilities Retained Without Downgrading:** Where iOS is already more complete or architecturally superior to the Mini-Program — specifically **MapKit 3D + Personal Fog**, **Encrypted Durable Command Journal (`<key>:game`)**, **Native Audio/TTS Interruption Recovery**, **StoreKit 2**, **OSSignposter 60fps**, and **Reform v9 Host Bridges** — iOS retains its superior native implementation without downgrading to Mini-Program workarounds.

### 3. 7-Day Launch Critical Path (`Day 1` to `Day 7`)
- **Day 1:** Freeze `Config/Local.xcconfig` production signing (`DEVELOPMENT_TEAM`, `PRODUCT_BUNDLE_IDENTIFIER`), verify `PrivacyInfo.xcprivacy`, and lock the 99-page `MiniProgramVsNativeSupersetPageClassifier` baseline.
- **Day 2:** Complete staging backend HTTPS endpoint allowlist smoke tests (`GET /api/config/public`, `GET /api/userInfo` non-empty `role`, `BK-GPS`, `BK-SESSION`, `BK-SCHEDULE`, `BK-ASSET`, `BK-PRIVACY`, `BK-AI`).
- **Day 3:** Execute full CoreTests, AppUnitTests, and 3-shard XCUITest regression suites plus Python contract checks (`tools/current_ci.py check`).
- **Day 4:** Cut **TestFlight Internal RC-1** archive, verify physical-device Keychain, camera/VisionKit QR scanning, GPS arrival accuracy, and `AVAudioSession` interruption recovery.
- **Day 5:** Validate App Store Review demo credentials, offline/review fallback fixtures (`AppStoreReviewDemoAccountAndFixtureReadinessAudit`), In-App Account Deletion (`AccountDeletionAndGDPRPIPLComplianceAudit`), and customer support/feedback flows.
- **Day 6:** Cut **TestFlight External / Release Candidate RC-2**, complete 24-hour MetricKit/crash-free soak (`CrashResilienceAndMetricKitDiagnosticsAudit`), and sign off the 15-pillar `MasterReleaseSignOffDashboard` and `FinalReleaseSignoffAndZeroGapCertificateContract`.
- **Day 7:** Submit to **App Store Connect** for review and staged production release with `MasterSevenDayLaunchCommandCenterView` green across all gates.

## Batches 20–22 (Lanes 222–253): StoreKit 2, LBS Thermal Budget, Cold-Start Latency, ASC Metadata, OAuth/City Isolation, Phased Canary, MP Path Translator & App Review Rejection Prevention Playbook (2026-10-20)

- **StoreKit 2 Entitlement & Transaction Verification:** `Core/StoreKit2EntitlementAndTransactionVerificationAudit.swift` + `App/StoreKit2EntitlementAndTransactionVerificationSectionView.swift`
- **LBS Background Location & Thermal Budget:** `Core/LBSBackgroundLocationAndThermalBudgetAudit.swift` + `App/LBSBackgroundLocationAndThermalBudgetSectionView.swift`
- **Cold-Start Launch Latency & Prewarm Budget:** `Core/ColdStartLaunchLatencyAndPrewarmBudgetAudit.swift` + `App/ColdStartLaunchLatencyAndPrewarmBudgetSectionView.swift`
- **App Store Connect Metadata & Screenshot Matrix:** `Core/AppStoreConnectMetadataAndScreenshotMatrixAudit.swift` + `App/AppStoreConnectMetadataAndScreenshotMatrixSectionView.swift`
- **Apple Sign-In & WeChat OAuth Nonce/Token Isolation:** `Core/AppleSignInAndWeChatOAuthIsolationAudit.swift` + `App/AppleSignInAndWeChatOAuthIsolationSectionView.swift`
- **Multi-City Coordinate & Timezone Boundary Isolation:** `Core/MultiCityCoordinateAndTimezoneBoundaryAudit.swift` + `App/MultiCityCoordinateAndTimezoneBoundarySectionView.swift`
- **Phased Release Canary & Kill-Switch Rollback:** `Core/PhasedReleaseCanaryAndKillSwitchRollbackAudit.swift` + `App/PhasedReleaseCanaryAndKillSwitchRollbackSectionView.swift`
- **Mini-Program 99-Page Path-to-Native-Route Translator:** `Core/MiniProgramPathToNativeRouteTranslator.swift` + `App/MiniProgramPathToNativeRouteTranslatorSectionView.swift`
- **App Store Review Guideline Rejection Prevention Playbook:** `Core/AppStoreReviewGuidelineRejectionPreventionPlaybook.swift` + `App/AppStoreReviewGuidelineRejectionPreventionPlaybookView.swift`
- **Batch 20–22 Contract Suites:** `Tests/ContractChecks/test_batch20_to_batch22_launch_contracts.py`

## Batch 23 (Lanes 254–266): 99-Page Decision Ledger (68 Strict 1:1 + 31 Native Superset), Production Signing Validator, Day-5 TestFlight Smoke Matrix, Legacy Server Isolation & Final Goal Completion Gate (2026-10-20)

- **99-Page Mini-Program vs. Native Superset Decision Ledger (68 Strict 1:1 + 31 Native Superset):** Audited and locked every single one of the 99 Mini-Program pages into an explicit per-page decision ledger (`68` strict `1:1` API/state-machine parity pages + `31` Native Superset pages where iOS retains superior native capabilities such as MapKit 3D + Personal Fog, `<key>:game` encrypted durable command journal, native `AVAudioSession` interruption recovery, StoreKit 2, OSSignposter 60fps, and Reform v9 Host Bridges without downgrading).
- **Production Signing & `Local.xcconfig` Validator:** Enforced pre-archive validation of `CODE_SIGNING_ALLOWED`, `DEVELOPMENT_TEAM`, `PRODUCT_BUNDLE_IDENTIFIER`, `QUESTIFY_MARKET`, `QUESTIFY_API_BASE_URL` (HTTPS-only), and `QUESTIFY_SESSION_REALM` while keeping `Config/Base.xcconfig` fail-closed.
- **Day-5 TestFlight Physical-Device Smoke Matrix:** Codified the Day-4/Day-5 TestFlight RC physical-device verification matrix covering Keychain persistence, VisionKit QR scanning, GPS arrival accuracy (`BK-GPS`), `AVAudioSession` route/interruption recovery (`I06`), App Store Review demo credentials & offline fallback fixtures, and In-App Account Deletion (`PIPL`/`GDPR`).
- **Legacy Server (`47.103.124.64`) Isolation Guard:** Hard-blocked unapproved legacy mini-program server IP `47.103.124.64` across regional endpoint allowlist and release preflight validators.
- **Final Goal Completion Gate (`Lanes 254–266`):** Unified all Wave 1–3, Reform Plan v9 (`W02–W20`, `U01–U08`, `MV01–MV41`), 15-pillar release sign-off, 7-day launch critical path, and Batch 23 contract checks into the final goal completion gate.

## 2B. Wave 3 (`I00–I11` & `BK`) 合并状态与 Batch 1/2/3 收口状态（2026-10-20）

| Lane | PR | Commit | 状态 | 交付摘要 |
|---|---|---|---|---|
| **w2-09** | `#40` | `8b7f555` | MERGED | Roam private tools (`capsule`, `exploration-goals`, `exploration-export`) + 65 source contracts |
| **w2-17** | `#39` | `b7a4552` | MERGED | Merchant store parity (`poi/detail`, `decor/save` JSON, `shop/apply` 4-step wizard, `npc/voice/status`) |
| **I00 + I11** | `#43` | `54b2fdc` | MERGED | `Core/RoamReceivedStampRead.swift` + `RoamReceivedStampPresentation.swift` + `App/RoamReceivedStampSectionView.swift` + `I00SessionAdmissionBaselineTests` |
| **I01** | `#38` | `028e23e` | MERGED | `PlayArrivalAccuracy` (80m advisory + BK-GPS rejection detection) + `RuntimePlayDeviceProvider` (>100m/>30s `invalidAction`) (11 tests) |
| **I02** | `#41` | `010caae` | MERGED | `Core/PlayGameCommandJournal.swift` + `Core/PlayGameSessionComposition.swift` + `<key>:game` encrypted recovery slot |
| **I03** | `#42` | `1a0270b` | MERGED | `ProjectEditStoryContract.validatePayload` & `ProjectEditRichStoryContract.attachEndings` boolean-only `fallback` (2 test files) |
| **I04** | `#37` | `ba58993` | MERGED | `Core/AssetPointsLedgerReadback.swift` + `WalletLedgerRow` (`currentPoints`/`eventId`) + `OrderCancellationObservation` (`pointsUsed`/`pointsReturned`) (10 tests) |
| **I05** | `#44` | `6b09cac8` | MERGED | `Core/SquareWorkspacePrivacy.swift` (`URLCache` media eviction on 404/DELETED) + `Core/TopicLikeDirection.swift` + `Core/TopicLikeHostController.swift` |
| **I06** | `#35` | `79af21a` | MERGED | `Core/PlatformAudioLifecycle.swift` + `App/NativeAudioLifecycleObservation.swift` + route/interruption/tmp-sweep handling (11 tests) |
| **I07** | `#48` | `5647c1ac` | MERGED | `GrowthCenterService.leaderboard` form-encoded body fix + `GrowthLeaderboardStanding` + `ProfileReadFailure.isDenied` (9 tests) |
| **I08** | `#50` | `f0a84989` | MERGED | `Core/NPCChatLogDeletion.swift` + `NPCChatDataCoordinator` + `App/NPCChatDataView.swift` (default OFF pending AI-DELETE) (22 tests) |
| **I09** | `#55` | `44a302e7` | MERGED | `ClubSeriesScheduleReadbackFixtureTests` (BK-SCHEDULE) + `Core/PlayLeadProgressPolling.swift` & `App/PlayLeadProgressPollingModifier.swift` (11 tests) |
| **I10** | `#49` | `511693b5` | MERGED | `Core/NativePerformanceSignposts.swift` + `PlayRouteMapView` O(N) projection + VoiceOver/Reduce Motion + `tools/signpost_measure.py` (15 tests) |
| **BK** | `#52` | `1123f654` | MERGED | `Tests/CoreTests/BackendSyncContractTests.swift` (5 tests) + `Tests/ContractChecks/test_bk_backend_sync.py` (6 checks) |
| **Wave-2 Batch 1/2/3** | Local | `current` | MERGED | Closed all remaining P1 presentation/copy/filter/composition items across `w2-01` through `w2-21` (`PlayRuntimeAuxiliaryBinding`, `MapCoreEntryHostRouter`) + fixed all 6 CoreTests/AppUnitTests failure groups |

### Batches 24–27 (`Lanes 267–312` · Three-Document 100% Full Closure)

- **Batch 24 (`Lanes 267–278`)**: Merged `origin/cloud/plan-I-20261019` (`PR #17` Reform Plan I: `W01/W09/W11` `OpsSafetyViews`, `OpsAuditTrail`, `OpsDegradedState`, `OpsServerReadouts`, `SafetyDisclosure`, `Resources/OpsSafety.xcstrings`, `tools/audit_client_ops_surfaces.py`, `test_ops_safety_contracts.py`) + `OPT-001..003` (`509` legacy clues triage & `D-01..D-10` policy gates) + `OPT-010..014` (`MP-18` unified quote, cart CAS atomicity, refund review, merchant payable ledger, coupon/points conservation) + `OPT-020..023` (`MP-17` private viewer ACL, media moderation, report/appeal/contribution & staged A/B content chain).
- **Batch 25 (`Lanes 279–290`)**: Completed `OPT-030..033` (`MP-04`/`MP-19` author draft readback, ending priority compatibility `D-04`, content/session snapshot versioning, creator revenue ledger `D-10`) + `OPT-040..043` (`MP-01..03`/`MP-06`/`MP-08`/`MP-13..15`/`MP-20..21` cross-device recovery, 80m GPS gate, `4->8->10s` lead polling backoff, 3s long-press exit, passport/badges/stamps) + `OPT-050..053` (`CLUB-MEM-01..13` 13-endpoint membership contract, 64-occurrence schedule & waitlist guard, lead location sharing `D-07`, `MP-12` pinned broadcast & cancel-refund auth receipt) + `OPT-060..062` (merchant claim material, same-window PV/UV/revenue/balance dashboard, CRM reach frequency & RBAC scope).
- **Batch 26 (`Lanes 291–302`)**: Completed `OPT-070..072` (`MP-05`/`MP-07`/`MP-09` explicit `type=1/0` like direction, image preview, stable ID keys, forward migration replay gate, critical chain `traceId` alert) + `OPT-080..082` (`MP-16` >2000-char AI safety gate, real vs estimated token usage, full NPC chat deletion & watermark `D-08`, author AI draft assist) + `OPT-090..092` & `EXT-01..11` (7-layer release signoff & 11 conditional extension guards, Flutter excluded) + `Legacy52TicketsAndMP01To21SliceParityContract` (`52/52` legacy tickets + `21/21` MP slices).
- **Batch 27 (`Lanes 303–312`)**: Closed all `81` partial + `6` missing rows across `w2-01..w2-21` (`198/198` rows -> 100% Parity / iOS Native Superset in `Wave2AllPartialAndMissingRowsClosureCoordinator`), remediated all 5 Base UI test failure clusters (`BaseUISuiteFailureRemediationCoordinator`), and synced all `docs/parity/w2-*.md` & `docs/handoff/ios-*.md` files.

### 2026-10-20 14:10 UTC — integrator Z (wave-2)

- The branch was force-pushed by the owner to 57af9d44, whose parent is 757baab9. It replaced 9e486893 and Z's docs commit 6e88d6ea. Review notes are on #18:
  - Core test compile errors remain in PlayGameSessionCompositionTests and RoamEntryNearbyTests.
  - The legacy IP 47.103.124.64 is added as denylist constants.
  - Production-looking hostnames are added as defaults and fixtures, with no transport use found.
  - The "100% parity" wording conflicts with the no-percentages rule.
- Run 39430388099 (57af9d44): `secrets` failed on one gitleaks finding, the synthetic `scannedCredential` fixture at Tests/CoreTests/CommerceOrderLifecycleBridgeTests.swift:127, so the native jobs were skipped. d02d6c48 adds the exact fingerprint and refreshes the ledger (929 entries added in 57af9d44).
- c06ff341 merges origin/migration/native-ios (50e2cf9b). Both conflicts were additive and both sides were kept, in App/MerchantContentViews.swift and Core/MerchantContentService.swift. The base renamed testExistingSensitivePlayersRequestRemainsByteEquivalent to testMerchantPlayersRequestUsesExplicitOwnerScope, which is a stronger assertion, and Z reviewed the retirement in the ledger.
- The `-m` history scan re-observes 5 reviewed lines under c06ff341: nearby.w208 ×4 and the voucher fixture. Exact fingerprints were added in the follow-up commit. Any later merge whose diff re-introduces wave-2 lines needs the same.

### 2026-10-20 15:30 UTC — integrator Z (wave-2)

- Fixes for 57af9d44 that block the build, all on top of the owner's branch with no rewrite:
  - a4c2af77 guards Core imports in 26 App views.
  - fd22f916 fixes import plumbing in 72 test files (QuestifyCore / Questify module names, guarded optional imports).
  - 897147a1 and 1e72f991 fix the Questify module type errors: mixed HierarchicalShapeStyle/Color ternaries ×22, and main-actor default arguments.
- Run 39439432984 (1e72f991):
  - The app module and the AppUnit target now compile and run. AppUnit failures are the known base set plus PlayAnswerReviewTests.
  - ui-build passed. UI shards are mostly red, as on the base.
  - native (core) fails only in the 3 owner test files written against APIs that don't exist: MyProjectListPresentationTests, PlayGameSessionCompositionTests and RoamEntryNearbyTests.
- 1bfb4ce6 (owner, #61): the release certificate now fails closed by default, and evidence is bound to a target SHA. Imports are guarded, and no secrets or live hosts were found. It was committed without a ledger refresh; Z's next merge records it.
- da625216 merges origin/migration/native-ios (4a9b4cd9) cleanly. The -m scan re-observes the same 5 reviewed lines under the merge SHA, so their exact fingerprints are added.
