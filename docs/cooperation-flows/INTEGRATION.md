# Cooperation flow migration, isolated handoff

Source audited: `app-audit/lib/data/api/coop_api.dart`, `merchant_api.dart` (nearby/relation-home/clubs), `data/models/coop_*`, `nearby_merchant.dart`, `merchant_relation.dart`, `feature/coop/**`, `feature/merchant/merchant_recruit_sheets.dart`, `merchant_recruit_page.dart`, `merchant_relation_page.dart`, `merchant_clubs_page.dart`.

## Status

Source-backed implementation and static verification delivered; **not yet installed into the shared app**. No source repository or remote changes, no backend calls, invitations, submissions, agreements, messages, payment SDK calls, coupon issuance/redemption, refunds or financial reconciliation occurred.

- 9 Swift files parse with pinned Tree-sitter, zero diagnostics. This is not Swift compilation.
- 286 source/static assertions pass (including catalog assertions), not 286 runtime tests.
- Swift unit tests: NOT_RUN, Swift compiler unavailable.
- iOS build, UI tests, VoiceOver, Dynamic Type, device/simulator: NOT_RUN, Xcode/Apple runtime unavailable.
- 18 authored XCTest methods: domain/wire, fake-transport, and coordinator tests. Two authored XCUITest methods require the fixture branch below.

## Copy and project integration

1. Copy four `Core/CooperationFlow*.swift` files to app Core, three `App/CooperationFlow*.swift` files to App, one core test file to `Tests/CoreTests`, and the UI test file to the project's actual UI test target. Add Swift files to the Xcode target if it does not use folder-synchronized groups.
2. Merge the `strings` dictionary in `Resources/CooperationFlowLocalizations.xcstrings` into the existing `Resources/Localizable.xcstrings`. Do not overwrite the existing catalog. New keys all start `coopflow.`. Keeping the fragment as a separately named catalog without a matching table lookup will not satisfy current lookups.
3. Create `CoopFlowService(configuration: approvedConfiguration, transport: approvedTransport)` with its default `dormantWritesEnabled: false`. Configure no production fallback URL.
4. Wrap it in `CoopFlowSessionReader(service:current:unauthorized:)`. Map the existing signed-in account, authorization epoch and token to `CoopFlowSession`. Epoch must change on logout, token replacement, account switching and permission context replacement. Unauthorized handling must clear only the captured session. Compose the host under an observable session owner and recreate/identify its view using account/epoch on every change, so private UI disappears immediately.
5. Add a NavigationLink from the current CooperationBrowserView/merchant center to `CooperationFlowWorkbench(reader:)`. Keep existing inbox/history/candidate ownership; the workbench adds source-specific finance/business/relationships/template workflows, and source-exact local mutation previews. No shipping button sends a mutation.
6. Nearby input is opt-in: pass `authorizedCoordinates` only after the user authorizes the location supplied to this merchant lookup. Omission makes no location request. API form is multipart `longitude`, `latitude`, `radius=5000`, `limit=30`. Merchant id and recipient memberId remain separate.
7. In an explicit synthetic fixture branch, render `CoopFlowFixtureHost()` when launch arguments contain `--cooperation-flow-fixture`. Never permit fixture-to-live fallback. The fixture uses no image URLs, network, geolocation, payment SDK or current private records.
8. Run the core Swift package tests and add the UI tests to the actual iOS UI test target. Check current platform API/type availability with Xcode. See verification commands below.

## MerchantContent supply bridge

MerchantContent owns recruitment reads and returns its source-derived `MerchantContentSupplyContext`:
- applicationID is only an application id, never chapterId or offerId
- match the current approved application's chapterID to the current chapter's recruitStatus.termsMode
- enroll eligibility: status==1, !offerActive, known TRAFFIC/PERK/REVSHARE
- manage circle supply eligibility: offerActive, positive offerID, nonempty circleThemeCode

Construct `CoopFlowOfferContext(chapterID:termsMode:offerID:)` using `CoopFlowOfferContext.TermsMode(rawValue:)`; reject unknown mode. For enrollment keep offerID nil. Present `CoopFlowOfferEditor(context:eligibleTemplates:)`. It creates only:
- TRAFFIC: chapterId, termsMode
- PERK: chapterId, termsMode, perkTemplateId, quotaTotal
- REVSHARE: chapterId, termsMode, perHeadFee

For existing circle supply, present `CoopFlowSupplyManagementView(context:canManageCircleSupply:)`, using MerchantContent's fresh guard. Reconfirm sends offerId to `/api/coop/offer/circle-supply/reconfirm-current`; pause sends offerId to `/api/coop/offer/circle-supply/pause`. History is preserved. There is no inferred delete, replacement enrollment, or signature route.

The adapter also rejects unknown terms mode, strips id/topicId/merchantId/quotaUsed/status, and disallows unrelated request fields. A changed source mode must invalidate the draft; a source read must be repeated before any future dispatcher is enabled.

## Mutation review, permission, and ambiguity architecture

`CoopFlowMutation` is immutable and source-exact. `CoopFlowCoordinator` consumes a `CoopFlowReview` at most once, re-reads source evidence at prepare AND confirm, compares the complete relevant baseline, verifies account+epoch, checks cancellation, and persists an account/resource lock before dispatch. Overlapping work is rejected. Review lifetime is 120 seconds, and time moving backwards invalidates it.

`CoopFlowSourceEvidenceReader` supplies actual fresh reads for pool apply/withdraw, received club decline, merchant confirm/reject, template creation/deletion, attaching perks, invitation handling, peer review, contact and eligible complaint selection. It does not confuse club IDs with member identities. Unknown statuses fail closed.

Creation of a new invitation and merchant offer enrollment/reconfirm/pause need the `additional` evidence provider tied to current topic ownership and MerchantContent's current permission+application+chapter reads. Until supplied, these prepare attempts fail closed. It is intentionally not an invented generic permission endpoint or trust in cached screen roles.

`CoopFlowDormantExecutor` is a real request adapter, closed by default. Invitation creation/handling, contact, complaint and offer enrollment remain blocked even when ordinary dormant writes are opted in. No current native UI can enable any writes. Future activation requires separate product/security authorization, verified provider/back-end contracts, full iOS tests, appropriate legal/financial confirmation UI and reviewed permission adapters.

Persist `CoopFlowFileLocks` under Application Support, not caches/tmp in production. It stores only account/resource keys, never tokens, comments, amounts or request bodies. Failed storage aborts before dispatch. Any ambiguous post-dispatch error, cancellation, malformed response, server rejection or account change retains the lock. Changing epoch or draft content does not reset it. No automatic retry, “try again anyway,” or speculative reconciliation exists. A future authorized support/reconciliation mechanism must establish the actual backend outcome before removing an unknown lock. Do not delete this file on routine logout.

Current UI previews are explicitly local drafts; they are not `CoopFlowReview` confirmations and do not invoke coordinator.confirm. This is deliberate while live execution is disabled. Do not attach confirm directly to an editable form or treat a preview as a legal acceptance.

## Important source semantics

- Withdrawal: topicId, not applyId. Club decline: applyId and exact optional scope. Merchant confirm/reject: registrationId.
- Invitations target a single memberId (merchant) or clubId (club). Ordinary compensation permits traffic=0/fixed=2, never ordinary revenue share=1. Multi-recipient clients must prepare and report per-recipient outcomes independently; no batch endpoint exists.
- Handle status is target status 1/2/3. Acceptance/rejection reason uses handleReason; cancellation uses message. Accepted cancellation requires a reason. Historical inviteType=2 and frozen terms are read-only. Detail cancellation follows Flutter sent-direction affordance.
- Candidate confirmation occupies a slot; it is not a sent terms invitation. Existing candidate detail must route next to a separately reviewed invitation, never auto-send it.
- Template save is create-only. No id/update UI. Money uses Decimal; absent unitCost stays absent, absent finance income never becomes zero. Source currency remains CNY independently of app market.
- Finance source is data.topics; merchant settlements source is mybiz.settlements. Detail re-reads the right list and requires exactly one matching record. No fabricated detail/withdraw/reconcile endpoint.
- Merchant, club, member, application, registration, settlement, invite, offer and topic IDs are explicit domains. Unknown payee/status remains source/unknown, not assumed merchant/paid.
- Complaints must select from `/api/coop/complaint/topics`; body is only topicId/reason. No fault, handler, compensation, refund or other adjudication fields.
- Reviews use comment, not content, rating 1–5, no self-review. Sent club invitation cannot be treated as a member review recipient.
- Perk template/coupon types do not issue or redeem coupons. OrderLifecycle retains all dynamic-code/issuance/redemption ownership.
- Financial source-only paths are documented constants: deposit/create/app, deposit/status, deposit/refund/retry. Only status is a read adapter. Provider callbacks never confirm ledger state. Refund receipt requires code==200, string data.refundState, nonempty source msg; otherwise unknown. No financial write adapter or fabricated agreement signing exists.

## Exact remaining gaps

1. Shared app/project/navigation/catalog installation is pending parent integration, as requested. Existing main files were untouched.
2. New invitation target/topic pickers must provide current authorized typed selections to `CoopFlowInviteEditor`; freeform ID entry is intentionally not allowed. Nearby partner reads do not auto-invite or dial.
3. MerchantContent must connect the typed offer views and fresh permission/terms provider. New invite ownership also needs a fresh source-backed additional evidence provider. Missing providers deny prepare.
4. Per-topic candidate confirmation entry remains owned by the existing candidate slice; the new aggregate merchant registration workflow is available. Candidate success-to-invite routing is documented and must not auto-send terms.
5. Backend behavior, provider readiness, Swift typecheck/compile, UI test host routing, signed iOS builds, localization rendering, accessibility and actual source server compatibility are unverified here. Do not label runtime or end-to-end parity complete.
6. No payment/deposit/refund or signature execution, broad monitoring, reconciliation or real external operation was enabled. These are intentional deployment gates, not fabricated endpoints.

## Verification

`python native-cooperation-flows-new/tools/check_cooperation_flows.py`

`swift-syntax-venv/bin/python chengyin-ios/tools/check_swift_syntax.py --root native-cooperation-flows-new <all nine explicit Swift paths>`

After integration on Apple tooling: `swift test` in chengyin-ios, then the actual project's xcodebuild build/test command and fixture UI tests. Re-run source/static and parser checks after any merge edits.
