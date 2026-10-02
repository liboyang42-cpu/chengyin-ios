# Public merchant home: additive integration

This packet changes no shared `chengyin-ios` files. All endpoints and identities below are source-backed. Copy only files marked `copy` in MANIFEST.json; merge the string keys into `Resources/Localizable.xcstrings`. Do not add PublicMerchantHome.xcstrings as a separate table without changing lookups. Run normal project generation after copying App/Core/test files.

## Required existing dependencies

`APIConfiguration`, `HTTPTransport`, `AuthRequestBuilder`, and merchant-business `MerchantBusinessIntent`, `MerchantBusinessScope`, `MerchantBusinessIntentStore` + memory/file stores. No merchant-business owner files are replaced. Existing authenticated manage/reply/delete/update flows stay owned by merchant-business. Public review create/report was confirmed unowned and is an additive, text-only extension in this packet.

## Main host wiring (parent-owned)

1. AppSession exposes a PublicMerchantHomeContext. Keep DisabledPublicMerchantHomeReader as default. Keep image renderer nil, shopNpcChat false, npcDestination nil. Read adapters only become executable when explicitly given approved configuration and transport; no singleton, URLSession, real image, or provider is constructed by this packet.
2. Thread the context optionally through TopicDetailView and its existing host factory. For each TopicMerchant, validate `PublicMerchantOwnerID(merchant.memberID)`; if valid use `PublicMerchantHomeView(target: .ownerMemberID(id), context: context)` as NavigationLink destination. Invalid memberID remains non-interactive or routes to nil target for invalid-link presentation. Do not use index, title, guessed row ID, or source TopicMerchant.memberID as legacy row ID.
3. Canonical `/merchant/public-home/member/:memberId` routes ownerMemberID. Legacy `/merchant/public-home/:id` routes legacyMerchantRowID. Invalid values yield nil target, no network. Accept exactly one identity; never send both or neither. The typed enum prevents ambiguous requests.
4. Authenticated MerchantHome preview may pass an actually verified owner member ID, or a verified merchant row ID via the legacy discriminator. Do not infer owner ID from merchantID/access.merchantID. Account identity is not automatically merchant owner identity for operators.
5. DoorReferral routes must inspect their source identity. Pass memberID to ownerMemberID only where the source canonical link says member. Parent coordinates with the DoorReferral owner. No registry rewrite or identifier remapping is supplied here.
6. RoamService.merchantDetail and SearchMap retain their `/api/merchant/public-detail` row-ID contract. This is another endpoint, not a replacement. Do not replace their models or host behavior globally.
7. To install public review read host, set `context.publicReviews = { target in AnyView(PublicMerchantReviewsView(target: target, reader: approvedReader)) }`. Only a profile with both positive server-returned IDs produces a target. Never synthesize missing returned identities from the request. Default host can use DisabledPublicMerchantReviewReader. Public read is not merchant management.
8. PublicMerchantReviewHTTPReader supports anonymous reads by default. An explicitly supplied PublicMerchantReviewSession adds source raw Authorization for eligibility. Its realm must equal `configuration.baseURL.absoluteString`; rebuild the reader with a new scope whenever account, token, session epoch, or region changes. Anonymous reads must not be given credentials through a transport that injects auth/cookies globally. Host task keys discard stale values by target/scope. The writer additionally checks the current session before/after network work.
9. Public text-only writes are OPTIONAL: supply PublicMerchantReviewWriteContext(writer: approvedWriter, journal: the shared durable merchant-business file store) to PublicMerchantReviewsView. Keep writes nil by default. Never use the in-memory store for an activated production host. No file path is defaulted here; reuse the owner's protected Application Support journal. Unknown locks survive account/epoch change, refresh, navigation, and reconstruction. They contain only realm/account/merchant/action/requestID, no token or draft. There is no invented receipt-status endpoint; unknown outcomes stay locked. Explicit user-visible review precedes dispatch, and fresh server eligibility/registration or canReport/version evidence is required both at preparation and confirmation.
10. Source allows an anonymous public page. Do not force login to view it. Text-only mutation UI is intentionally available only with explicit session-backed writer and returned eligibility/canReport; it does not claim arbitrary guests can submit. Create uses merchantRowId; report uses merchantMemberId (owner), never interchange them. Request IDs are source-required, stable per reviewed command, not guessed server support. Create receipt distinguishes PENDING_REVIEW/VISIBLE/HIDDEN and replay; report receipt is PENDING_PLATFORM_REVIEW, not deletion. Successful write receives a receipt, not a claim of refreshed feed/publication.
11. Source NPC nuance: a returned named NPC + positive row ID permits the static card even when shopNpcChat is false. A chat entry additionally requires shopNpcChat and a supplied destination. No provider or conversation is activated. Existing source contract owns the provider.
12. Media remains OFF. Gallery/cover/logo/NPC and review photos use local accessible placeholders. The profile optionally accepts an approved renderer; image URL policy, download approval, caching, photo acquisition/upload, and signed OSS URL policy are separate activation work. Public review create sends imageUrls: [] and supports text only.

## DEBUG UI fixture hook

Only under `#if DEBUG`, recognize explicit launch arguments `--public-merchant-home-fixture <scenario>` and mount PublicMerchantHomeFixtureView(scenario: scenario) instead of the app root. Scenarios: profile, invalid, unavailable, retry, missing-ids, unknown. Its fake transport returns local JSON, never makes network calls, and uses in-memory locks deliberately. Run Tests/AppUITests/PublicMerchantHomeFlowTests after this parent-owned hook is installed. Do not install this fixture in release or report authored tests as executed.

## Verification

From workspace root:

- `python native-public-merchant-home-new/Tests/ContractChecks/check_public_merchant_home.py`
- `swift-syntax-venv/bin/python chengyin-ios/tools/check_swift_syntax.py --root native-public-merchant-home-new $(find native-public-merchant-home-new -name '*.swift' -printf '%P ')`
- On a Swift/Apple host after integration: run focused PublicMerchantHomeTests, PublicMerchantReviewHTTPWriteTests, PublicMerchantReviewWriteTests, then the six UI flow tests and the app build, plus aggregate repository gates.

Read-only/fake transport tests cover exact identity bodies, anonymous headers, nil body/query review requests, unavailable vs retryable, absent returned IDs, NPC gate, paging/public-mode/eligibility rejection, write JSON/auth/realm fences, fresh eligibility, reviewed stable request IDs, cancellation/session changes, durable unknown locks, and exact receipt validation. No real requests or images are used.

## Source map

- `app-audit/lib/data/api/merchant_api.dart:1481–1495,1534–1544,1641`
- `app-audit/lib/feature/merchant/merchant_public_home_page.dart:19–109,121–205,300–430`
- `app-audit/lib/feature/topic/topic_detail_page.dart:923–939`
- `app-audit/lib/core/router/app_router.dart:707–734,1195–1204`
- `app-audit/lib/data/api/merchant_review_api.dart:64–85,125–139,191–218,221–269`
- `app-audit/lib/data/models/merchant_review.dart:28–287,323–367,405–505,550–558`
- `app-audit/lib/feature/merchant/merchant_public_reviews_page.dart:69–98,152–229,281–329,1039–1074`

## Remaining scope and limits

Full media parity is not claimed: no picker, image upload, approved OSS policy, zoom viewer, or real media renderer. No NPC provider activation. Public reviews are source-backed native read + text-only create/report, with server-controlled permissions, not a completed end-to-end Apple-certified public review migration. Date strings are displayed as returned, without inventing time zones. Apple runtime/build/typecheck remains NOT_RUN in this Linux environment. Source assertions and Tree-sitter are supplementary evidence only.
