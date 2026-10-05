# Native direct verification and support entry

## Source-backed verification

The account's merchant workspace now opens a real native verification workflow instead of only the classification preview. The source participation detail's verification-statistics action closes its detail sheet before opening the same workflow. Fresh merchant access is still required; appearance of a player-detail field never grants merchant permission.

The workflow supports code capture (a native camera surface is present but default-grant off), private text input, exact-purpose review, server-returned chapter/station choice, server-result display, and ledger readback. Input is cleared before review; complete codes are not displayed, serialized or journaled. Reviews freeze the intended store and expire after sixty seconds. Confirmation fetches fresh permission and rejects a different merchant, even if the account token is unchanged.

Existing exact adapters remain authoritative: signed group, signed activity/topic ticket, signed `cq1` coupon and legacy JSON coupon/activity/topic. Current mini's `cq1` direct coupon path was missing and is added. Dynamic authenticity and ownership remain server decisions. City-node and unknown code families are not routed into this redemption adapter.

No new financial/verification endpoint was invented. Legacy choice posts retain `chapterId` or `registrationMerchantId`, never a station's unrelated `id`. Production MerchantBusinessService has no mutation transport; only explicitly injected offline-test transport can execute the adapter. The shipping camera grant is also false. This is implemented local workflow code, not live-provider authorization.

## Unknown results and lifetime

The existing durable merchant redemption intent is reserved before dispatch and contains only account/realm/merchant/target/local operation identity. It survives navigation, relogin and relaunch. A timeout, malformed response, lost session or dismissal during an in-flight write remains unknown. Neither viewing the first ledger page nor refreshing permissions clears that lock, and the UI prevents scanning another code while it remains unresolved.

The redemption coordinator now has a generation check around both access fetch and dispatch result. Leaving a screen during an in-flight request cannot resurrect a choice dialog or stale private result. A late result after dismissal keeps the journal lock rather than assuming that nothing happened. Review dismissal alone is a no-write operation and cannot reset an active submission phase.

Readback uses the existing `api/merchant/finance/redemptions` list and its permission boundary. There is no invented operation-receipt endpoint and no automatic resend, settlement inference or balance calculation.

## Source proof (read-only inspection, 2026-10-02)

- Mini utils/verification-scan.js: signed group/activity/topic/cq1 and legacy JSON routing; city-node explicitly belongs elsewhere
- Mini utils/verification-readback.js: unknown is not failure; current records cannot identify this exact request and must not unlock a repeated action
- Mini subpackageMember/components/scene-member-participation-detail/index.js:164–193: common scanner routing and chapter/station choice handoff
- Existing native Core/MerchantRedemptionContext.swift, Core/MerchantBusinessService.swift and Core/MerchantBusinessCoordinator.swift: exact request identities, protected merchant access, synthetic-only mutation transport and durable metadata-only journal

## Support configuration boundary

Mini uses WeChat `open-type=contact` (participation detail index.wxml:129–134), which supplies no email, phone, native service or support URL. The native participation support destination is implemented with an optional, independently approved fixed HTTPS channel and an explicit user-tapped Link. Its shipping configuration is nil. URLs containing credentials, query or fragment are rejected; no order/account/code details are appended or transmitted. No service provider or contact has been guessed. Activating this channel needs a verified destination, not missing screen code.

## Checks and remaining acceptance

PASS: 14 existing merchant-business static/source checks against the supplied Flutter checkout; native verification source assertions; deterministic project regeneration and bilingual-catalog/scaffold checks. Merchant-content optional external-source check could not complete because that supplied checkout lacks test/blocked_by_backend_test.dart; no merchant-content implementation was changed in this packet.

AUTHORED: 8 workflow/parser/lifecycle domain tests, 2 support-configuration tests and 3 offline UI flows. A DEBUG-only `--native-verification-fixture success|unknown` host enables synthetic flow execution without creating AppSession or contacting a backend.

NOT_RUN: Swift tests, Apple compilation, the authored UI flows, visual/VoiceOver/Dynamic Type inspection, camera and real account/backend/provider acceptance. The cloud executor has no Swift/Xcode. No actual redemption, financial request, camera permission, support contact or backend call was performed.
