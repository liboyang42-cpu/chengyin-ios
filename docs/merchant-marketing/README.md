# Merchant Marketing native package

Isolated source-backed package, 2026-10-02. Source: Flutter `a63e9e91c82a3282e8dd7138f943b1a8cbfc021d`, verified local source files. No shared-main edits or remote writes. This is a dormant native implementation, not live acceptance.

## Included

- Marketing aggregate: one marketing-home request after fresh `merchant:marketing:read`; coupon totals, content totals and server funnel. Missing values stay unknown, and zero claimed coupons has no redemption rate.
- Shop insight: mandatory deterministic `facts`; separate generated advice, nullable rates, low-sample notice, window, check-ins/hour buckets, audience counts/interests, supply, server metadata, AI degradation, recommended topics/partners. Navigation is a typed three-case client allowlist; arbitrary model routes never reach the host. Canonical partner `memberId` remains in retained metadata; no guessed profile link is constructed.
- Active subscriptions and commerce capabilities: empty is no active entitlement; null/missing endDate is permanent; quota is read from server, not computed into a grant. All source payload/metadata is retained for commerce and insight.
- Prediction inbox: fresh active merchant/project authority, direct-array response, per-round server deadline and participation copy, option selection, immutable review and coupon-effects acknowledgement. Confirm rechecks exact access and round before dispatch. Request uses string nodeId, playDay, settledOption. A valid nonnegative winners count is the only successful acknowledgement.
- Account/token/epoch/namespace response fences; persistent namespace/account/merchant/node/day replay locks exclude ephemeral epoch and secrets. Atomic exclusive intent is recorded before dispatch. Success remains locked, unknown/timeout/malformed/5xx remains locked, definite 4xx rejection (except timeout) can be reviewed again. No automatic mutation retry and no invented receipt endpoint. Display refresh never clears a lock.
- Native SwiftUI forms/lists, VoiceOver labels/identifiers, Dynamic Type friendly vertical content, bilingual resource fragment, debug synthetic fixture host, 35 authored core tests and 7 authored UI tests.

## Explicit exclusions

Digital-entitlement checkout is suppressed by the source on iOS. This package does not add commerce/order, a purchase button, StoreKit, a provider, or fake IAP. The source's known non-iOS ordinary checkout/status chain is not an iOS entitlement purchase contract. The UI provides an informational unavailable statement only.

No CRM/marketing-consent management, coupon authoring/distribution, CouponManagement ownership, real AI request, real purchase, prediction settlement, coupon issuance, external navigation, network request or other remote action was executed. Fixture requests are captured and answered in memory.

## Exact source contracts

| Endpoint | Method/body | Source evidence |
|---|---|---|
| `/api/merchant/access/me` | POST, no body | merchant_api.dart 238–243, 711–720 |
| `/api/merchant/marketing-home` | POST, no body | merchant_api.dart 574–578; merchant_marketing_page.dart 18–27; merchant_marketing.dart |
| `/api/ai/merchant/insight` | POST, no body, merchant resolved from session | merchant_api.dart 580–592; merchant_insight.dart |
| `/api/merchant/subscription` | POST JSON `{}`; data array | merchant_api.dart 1256–1280, 1453–1458 |
| `/api/merchant/commerce/capabilities` | POST JSON `{}`; data object | merchant_api.dart 1548–1561; merchant_subscription_page.dart 139–182, 298–338 |
| `/api/merchant/predict/inbox` | POST JSON `{}`; data array itself | merchant_predict_api.dart 31–56 |
| `/api/merchant/predict/settle` | POST JSON string nodeId/playDay/settledOption | merchant_predict_api.dart 58–84, 131–163 |

Permissions are not interchangeable: marketing read is `merchant:marketing:read`; prediction access is active plus `merchant:project:manage`, never inbox size or role inference. Insight/subscription/capability endpoints use authenticated session identity as in source, without inventing client merchant payloads. Commerce server error messages are preserved so login/onboarding failures remain distinguishable; the host owns any existing login/onboarding destination.

## Additive integration

1. Copy only the manifest-listed Core/App/Tests files into matching native folders. Existing Core target discovers new Core files; regenerate the Xcode project with the established tool. Do not overwrite shared navigation, AppSession, MerchantAccess, CouponManagement or MerchantBusiness implementations.
2. Merge `Resources/MerchantMarketingLocalizations.fragment.json` into the existing string catalog's `strings` dictionary. Preserve existing entries; prefix is unique. Keep both en and zh-Hans. The fragment is not a complete replacement catalog.
3. Construct one `MerchantMarketingService` per authenticated operational profile using the existing `APIConfiguration`, `HTTPTransport`, raw-token request builder, account ID and session epoch. Use a stable nonsecret profile/endpoint namespace (at most 64 UTF-8 bytes), not UI language. Endpoint/profile approval is a host prerequisite; no hostname is approved by this package. Default gates are all false.
4. Supply `currentSession` from the authoritative session and wire `onUnauthorized` to invalidate only the matching captured session. Immediately call coordinator.sessionChanged() on sign-out, token/account/epoch/profile changes, even while a review is on-screen. Do not rely exclusively on a SwiftUI onChange of the derived scope key; the enclosing host must publish session transitions.
5. For an approved future settlement deployment, inject a `MerchantPredictionFileLocks` rooted in private application support, shared across coordinators and retained across sign-out/relaunch. Do not use debug memory locks in production or clear them on logout. There is no source-supported reconciliation endpoint, so unknown outcomes remain blocked until an independently verified operator/product recovery contract exists. Reads, AI and settlement are separate gates. Do not enable any just to mount the entry.
6. Add `MerchantMarketingEntry(model:isSourceVisible:onSuggestion:)` only at the merchant host. Visibility defaults false. Existing merchant access projections do not currently include marketing permission in their enum; use this package's strict fresh source authority rather than widening another module's enum as an incidental edit. Passing a true feature-visibility value does not grant network or mutation access.
7. The typed suggestion callback maps `topicCooperation` to the existing cooperation surface, `decoration` to an existing approved decoration surface, and `content` to the existing publishing surface. The source allowlist is `/merchant/coop`, `/merchant/decor`, `/publish/pro`. Do not invent a new route or open a URL supplied by AI. Unmounted routes should be disclosed as unavailable by the host.
8. Debug only: recognize `--merchant-marketing-fixture <dashboard|insight|subscriptions|predictions>` plus `--merchant-marketing-scenario <normal|empty|denied|unknown|missing-facts>` at the existing fixture switch and return MerchantMarketingFixtureHost. No production factory references fixture transports. Add these names to the existing UI test selection workflow if desired. UI tests are authored against that explicit hook and are not claimed to run before it is integrated.

## Verification

Run from the sibling workspace:

```
python3 native-merchant-marketing-new/tools/check_merchant_marketing.py --syntax-python swift-syntax-venv/bin/python
```

After integration, pass `--flutter-root` and `--syntax-script` if their locations differ. The static script checks source contracts, safety boundaries, bilingual keys and authored test inventory. It does not run Swift unit/UI tests.

`validation.json` and `parser.txt` record the final results. Supplementary Tree-sitter parses all eight authored Swift files without recovery. Apple compiler/typechecking, Swift tests, iOS simulator/UI tests, screenshots, VoiceOver, Dynamic Type and CN/US builds are **NOT_RUN** because this executor has no Apple toolchain. Run the repository's documented `swift test`, unsigned simulator build and selected UI fixture suite on an approved Apple runner before merge/release acceptance.

Additional acceptance: validate the exact backend host/profile, permission revocation, interruption while review/submission is in flight, relaunch after unknown, English/Chinese maximum Dynamic Type, VoiceOver order, no purchase affordance, real server winners and coupon effects under separately authorized acceptance. No live gates should be enabled as part of source integration.
