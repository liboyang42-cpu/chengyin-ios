# C07-ios shared hunk for dot

Exclusive owner: Cursor C07-ios (`cursor/c07-ios-fulfillment-projections-e504`).
Base: `migration/native-ios` @ `76ce1b313af2595f9b7d7ace49040866209c7974`.
This file is the only shared hunk. Do not treat it as authorization to edit AppSession / AppCompositionRoot / pbxproj / Localizable / OrderLifecycle / BundleBooking / payment verifiers from the Cursor line.

## Why this hunk exists

Issue 5 C07: merchant supply dry-run / entitlement hold / appointment-reschedule / in-store evidence / refund trial / aftercare / four-ledger reread / invoice UNKNOWN / transfer-sold WAITING_SOURCE. New Core types are SwiftPM-visible (`Package.swift` `path: "Core"`). Xcode `check_scaffold.py` still requires every `Core/*.swift` file to be listed in `Questify.xcodeproj/project.pbxproj`. C07 must not edit that project file.

Inventoried, not rewritten:

- `Core/MerchantAftercareEvidenceAdapter.swift` — aftercare upload remains evidence-adjacent owner
- `Core/OrderLifecycleService.swift` / `OrderLifecycleCoordinator.swift` / `OrderLifecycleProduction.swift`
- `Core/MerchantSettlementProgress.swift` / `MerchantSettlementEntryPresentation.swift`
- `Core/MerchantRedemptionContext.swift` / `MerchantRedemptionFilter.swift` / `MerchantRedemptionProgress.swift`
- `Core/OrderPaymentVerifier.swift` — payment verifier stays with Dot
- `App/AppSession.swift` / `App/AppCompositionRoot.swift`

## Dot-owned integration (do not apply from this PR)

1. **pbxproj** — from this SHA, run `python3 tools/generate_project.py` so these new sources join the Questify target. Do not edit pbxproj from C07:
   - `Core/MerchantSupplyDryRunProjection.swift`
   - `Core/EntitlementHoldProjection.swift`
   - `Core/FulfillmentEvidenceProjection.swift`
   - `Core/FourLedgerBillRereadProjection.swift`
   - `Core/InvoiceHistoryUnknownProjection.swift`
   - `Core/TransferSoldPolicyProjection.swift`
   CoreTests are SwiftPM-only (`Tests/CoreTests`); they are not Xcode app-unit sources.

2. **13 / 17 / 28 production, 13 Authority, 17 phone identity** — remain Dot. Exclusive transfer-sold policy is not D4 SMS identity. Do not wire phone-identity as sold-policy.

3. **BundleBookingService** — remain Dot. Supply dry-run never writes `capacity_reserved` / stock. Appointment / reschedule facts keep `originalRequestID`.

4. **Money writers / payment verifiers** — remain Dot. Refund trial is evidence only; no payout. Four-ledger reread does not start a new reconcile. Current projection is not the original receipt.

5. **AppSession / composition** — do not wire C07 into `AppSession` or `AppCompositionRoot` from this candidate.

6. **Localizable.xcstrings** — not edited. iOS 13.0 baseline, do not raise.

## C07 already landed (do not rewrite)

- SKU + validity + hours-capacity dry-run: ACCEPT / REJECT / UNKNOWN; null hours on a bookable SKU = UNKNOWN (not 24h); Asia/Shanghai server clock
- ACCEPT does not write stock or reservation; duplicate `originalRequestID` does not double-hold; UNKNOWN recover keeps original intent
- Holding entitlement occupies capacity and is not issuance; no reserve / redeem / award
- Appointment / reschedule keep the original request; in-store evidence is not a GPS fake
- Invoice file/history UNKNOWN keeps original intent and does not mint a new requestId; current projection is not original file success
- Transfer-sold missing designated recipient or missing sold-policy source is typed WAITING_SOURCE
- Untrusted / missing identity is Optional.none / JSON null, never empty-string coercion

## Verification note

Linux: Python contract `python3 -m unittest Tests.ContractChecks.test_c07_fulfillment_projections` from the iOS worktree cwd.
Swift XCTest / App / CI: authored isolation tests, **NOT_RUN** on Linux.
No real payment / refund / redeem / award.

WAITING_SOURCE: transfer-sold policy + designated recipient authorization + irrevocable-effect originals; invoice file storage; 25-App T01–20 / T43–58 not signed as Git objects on this public tree. Not 100% of T01–20.
