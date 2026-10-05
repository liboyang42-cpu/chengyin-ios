# AccountCompliance native package

## Delivered

Concrete dormant `HTTPTransport` adapter, typed server-owned consent and cancellation status, customer marketing preferences, server-truth readback, a durable atomic operation journal, account/market/namespace/epoch and view-generation fences, injected roam tracking/privacy cleanup, and native SwiftUI sheets. No network, SMS, consent, deletion, token, location or private-data operation was performed while developing this package.

`AccountComplianceService` defaults all read/write capabilities OFF and all legal approvals false. The initializer deliberately requires an injected transport, endpoint, existing session/token access, and durable journal. There is no standalone auth stack, hardcoded service endpoint, production factory, auto-retry, cooling-off constant, or invented provider API.

## Additive integration (parent-owned; not applied by this package)

1. Copy `Core/AccountCompliance*.swift` into Core, `App/AccountComplianceViews.swift` into App, tests into Tests/CoreTests and the catalog into Resources. Run the existing project generator to enumerate App/resources. Pure Core is included by the existing Swift package target automatically.
2. Use the existing AppSession account ID, authentication epoch, active configured market and endpoint namespace to build `ComplianceSession`. These must reflect authenticated state, never UI language. Existing token access supplies Authorization; do not persist or log tokens here.
3. Create one retained `ComplianceFileJournal` at an app-private Application Support URL per installation. Keep journal metadata through sign-out and relaunch, because a new token does not prove a previously timed-out mutation failed. Corrupt files fail closed. Do not erase journals as a retry mechanism.
4. Keep capabilities false in the production host. Inject fake HTTPTransport and synthetic sessions for fixture previews/tests. Release activation requires reviewed endpoint, legal, security and provider approvals; a source document's presence is not legal approval.
5. Inject the existing `AuthChannelService` through `AuthChannelServing`; no SMS transport is added. Inject roam controller stop and map-privacy clear/cache invalidation as `ComplianceRoamEffects`. The coordinator never operates OS location directly.
6. The session invalidation callback must compare its supplied session to the current session before signing out through the existing auth controller. Accepted apply revokes sessions on the server. Never sign out a newly switched account. Call coordinator.invalidate on logout, account/market/epoch changes and view dismissal. The sheet handles its own dismissal; the host still owns global session changes.
7. Replace only the existing explanatory privacy rows with `AccountComplianceSettingsSection(makeCoordinator:market:legalReader:)`, preserving surrounding settings navigation. Do not duplicate old unavailable rows. Keep `SettingsLegalDocumentView`, `SettingsBundledLegalReader`, and the exact source Chinese agreement/cancellation catalog. The sheet has notice, server blockers, SMS, explicit review, apply, pending/cancel, fresh-login and unknown states.
8. For registration and merchant-on-site flows mount `ComplianceConsentReviewSheet` with approved source text and a typed subject. Obtain merchant ID only from the current authoritative server node. Supply `authoritativeMerchantID` closure returning that same current node identity; defaults deny merchant scope. On confirmation use only returned exact matching record to continue the existing flow. Do not enable registration/payment/redemption runtimes merely because this bridge exists.

## Source evidence

Flutter revision audited: `a63e9e91c82a3282e8dd7138f943b1a8cbfc021d`.

- `lib/data/api/account_api.dart:97–153`: POST consent/latest with optional scope and absent-data no-consent; POST consent without any client-supplied docVersion.
- `account_api.dart:32–42,162–198,232–268`: registration sharing and merchant-on-site doc/scene constants; positive merchant ID from authoritative node; exact scope/event readback.
- `account_api.dart:200–229`; `lib/feature/settings/settings_page.dart:838–879`: roam REVOKE, no scope; only after confirmed readback stop tracking, then clear map privacy, with independent failure boundaries.
- `lib/data/api/page_parity_api.dart:296–339`; `lib/data/models/marketing_consent.dart:1–64`: customer opt-in GET/POST, both merchant identities, IN_APP/COUPON, boolean state, requestId and matching readback. This is not merchant marketing analytics.
- `account_api.dart:75–95,270–295`; `lib/data/models/deregistration.dart:1–50`: GET status, POST precheck, multipart apply(smscode/requestId), POST cancel; server blocker strings and execution date.
- `lib/feature/account/deregister_page.dart:93–197`: status/precheck/notice/SMS/review/apply, accepted session invalidation, fresh authentication before cancellation. Native client additionally reads back cancellation NORMAL and fails closed on unknown/missing status.
- Native `Core/AuthChannelService.swift:70–74`: existing SMS contract reused. `Core/SettingsLegal*.swift`, `App/SettingsSupportSections.swift`: existing legal reader/view reused.

## Safety and failure semantics

Mutation journal metadata is written before transport dispatch. Timeout, cancellation, malformed envelope, stale account/epoch/scope, or mismatched readback retains an unknown-operation lock; another request ID cannot bypass it. Explicit decoded business rejection clears that operation. Successful consent/marketing resolves only after exact matching truth. Apply keeps its journal until a new authentication epoch and a pending status allow cancellation; accepted applications invalidate only the original session. Unknown status never grants eligibility. The server alone supplies blockers and executeAfter.

Roam partial progress is represented as serverConfirmed / trackingStopped / complete. Retrying resumes only unfinished local boundaries. After sheet recreation it checks authoritative latest consent before any new REVOKE; an existing REVOKE resumes cleanup without another write. Failure clearing local privacy invalidates cached map data.

Durable unresolved marketing/application operations conservatively remain locked when no authoritative reconciliation can establish their result. No universal receipt endpoint exists in source; no automatic retry or fabricated reconciliation API is provided. Consent has an explicit read-only reconciliation function. Cancellation checks a fresh epoch, pending server state and final NORMAL readback.

No passwords/phone/SMS codes are journaled. SMS input is ephemeral; submitted code is cleared from view/coordinator. Phone uses the existing CN validation contract, not an invented US number/SMS contract.

## Content/activation gates

CN privacy source text and all US legal text remain missing. Existing source Chinese cancellation/agreement paragraphs are displayed through the existing reader without edits or invented translation. `SettingsLegalDocument.isReleaseApproved` is currently false; do not derive approval from its presence. Signup/merchant scopes require separately supplied approved source text. Interface labels have English and Simplified Chinese translations, which are not legal-policy translations. No market is selected from UI language.

## Verification

Executed: Python source-contract checker and JSON fixture validation; pinned Tree-sitter parser for all five Swift files. Authored: 13 XCTest methods using a concrete fake HTTPTransport, covering latest absence, exact scope, no docVersion, stale merchant scope/account, persistent mismatch lock, disabled grants, multipart apply/fresh epoch, server BLOCKED/UNKNOWN, wrong marketing owner, consent/SMS failure, accepted session invalidation, ordered roam partial cleanup and fresh-login cancel readback.

Not executed: Swift type checking, XCTest, Apple build, SwiftUI runtime, simulator, VoiceOver or live APIs. No Swift/Apple compiler is installed. Tree-sitter is supplementary syntax evidence only. Host must run `swift test` and Apple simulator/UI checks after integration. Suggested UI checks: dismiss/reopen at every step, account switch while suspended, SMS resend failure, double tap, fresh-login cancel, Dynamic Type, VoiceOver toggle identification, and disabled/missing-content states.
