import XCTest
@testable import QuestifyCore

final class CouponAndSponsoredRewardSafetyAuditTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func makePoolItem(
        kind: SponsoredPrizeKind = .coupon,
        allocation: SponsoredAllocation = .fixedMilestone,
        guaranteeReserved: Bool = false
    ) -> SponsoredPoolItem {
        SponsoredPoolItem(
            itemID: "pool-item-1",
            pledgeID: "pledge-1",
            pledgeVersion: "v1",
            merchantID: "m-1",
            storeID: "s-1",
            kind: kind,
            allocation: allocation,
            title: "Synthetic Perk",
            termsVersion: "tv-1",
            termsText: "Valid in store",
            validFrom: t0,
            validUntil: t0.addingTimeInterval(86_400),
            remaining: 10,
            guaranteeReserved: guaranteeReserved,
            asOf: t0
        )
    }

    func testW205CouponRuntimeJourneyAnchorsAnd503AutoRefreshStop() {
        let readyEval = CouponAndSponsoredRewardSafetyAudit.auditCouponRuntimeJourney()
        XCTAssertTrue(readyEval.isAnchorReady)
        XCTAssertTrue(readyEval.isCompliant)
        XCTAssertTrue(readyEval.stopsAutoRefreshOn503)
        XCTAssertTrue(readyEval.liveQRTokenDispatchDefaultDisabled)

        let missingAnchorEval = CouponAndSponsoredRewardSafetyAudit.auditCouponRuntimeJourney(
            mountedAnchors: ["couponRuntime.root"],
            stopsAutoRefreshOn503: false,
            liveQRTokenDispatchDefaultDisabled: false
        )
        XCTAssertFalse(missingAnchorEval.isAnchorReady)
        XCTAssertFalse(missingAnchorEval.isCompliant)
        XCTAssertEqual(missingAnchorEval.missingAnchors, ["couponRuntime.readOnlyConfirm"])
        XCTAssertTrue(missingAnchorEval.violations.contains(.missingCouponRuntimeAnchors(["couponRuntime.readOnlyConfirm"])))
        XCTAssertTrue(missingAnchorEval.violations.contains(.qr503ContinuesAutoPolling))
        XCTAssertTrue(missingAnchorEval.violations.contains(.liveCouponQRDispatchEnabledByDefault))
    }

    func testGW07SponsoredPoolDisclosureRulesEnforceLimitedUnlessReserved() {
        let unreservedGuaranteed = makePoolItem(allocation: .guaranteed, guaranteeReserved: false)
        let evalUnreserved = CouponAndSponsoredRewardSafetyAudit.auditPoolDisclosure(item: unreservedGuaranteed)
        XCTAssertEqual(evalUnreserved.computedDisclosure, .limitedWhileSuppliesLast)
        XCTAssertFalse(evalUnreserved.isPresentableUnderCapabilities)
        XCTAssertTrue(evalUnreserved.isCompliant)

        // Attempting to claim guaranteedReserved on an unreserved item is flagged as a violation
        let spoofedEval = CouponAndSponsoredRewardSafetyAudit.auditPoolDisclosure(
            item: unreservedGuaranteed,
            claimedDisclosureOverride: .guaranteedReserved
        )
        XCTAssertFalse(spoofedEval.isCompliant)
        XCTAssertEqual(spoofedEval.violations, [.unreservedPoolClaimedAsGuaranteed])

        var caps = SponsoredRewardCapabilities()
        caps.nonCash = true
        caps.guaranteed = true
        let reservedGuaranteed = makePoolItem(allocation: .guaranteed, guaranteeReserved: true)
        let evalReserved = CouponAndSponsoredRewardSafetyAudit.auditPoolDisclosure(
            item: reservedGuaranteed,
            capabilities: caps
        )
        XCTAssertEqual(evalReserved.computedDisclosure, .guaranteedReserved)
        XCTAssertTrue(evalReserved.isPresentableUnderCapabilities)
        XCTAssertTrue(evalReserved.isCompliant)
    }

    func testFrozenVoucherTermsVerificationBlocksSilentTermMutationAndShortenedValidity() {
        let issued = SponsoredVoucherTerms(
            voucherID: "voucher-1",
            termsVersion: "terms-v1",
            validUntil: t0.addingTimeInterval(86_400)
        )

        let unchanged = CouponAndSponsoredRewardSafetyAudit.auditFrozenVoucherTerms(
            issued: issued,
            later: SponsoredVoucherTerms(
                voucherID: "voucher-1",
                termsVersion: "terms-v1",
                validUntil: t0.addingTimeInterval(172_800)
            )
        )
        XCTAssertTrue(unchanged.readbackAccepted)
        XCTAssertTrue(unchanged.rejectionReasons.isEmpty)
        XCTAssertTrue(unchanged.isProtectedAgainstSilentMutation)

        let mutatedTerms = CouponAndSponsoredRewardSafetyAudit.auditFrozenVoucherTerms(
            issued: issued,
            later: SponsoredVoucherTerms(
                voucherID: "voucher-1",
                termsVersion: "terms-v2",
                validUntil: t0.addingTimeInterval(3_600)
            )
        )
        XCTAssertFalse(mutatedTerms.readbackAccepted)
        XCTAssertTrue(mutatedTerms.isProtectedAgainstSilentMutation)
        XCTAssertEqual(
            mutatedTerms.rejectionReasons,
            [
                .voucherTermsMutatedAfterIssue(
                    voucherID: "voucher-1",
                    issuedVersion: "terms-v1",
                    laterVersion: "terms-v2"
                ),
                .voucherValidityShortenedAfterIssue(voucherID: "voucher-1")
            ]
        )
    }

    func testFailClosedSponsoredRewardCapabilitiesDefaultGate() {
        let defaultGate = CouponAndSponsoredRewardSafetyAudit.auditDefaultCapabilitiesGate()
        XCTAssertTrue(defaultGate.isFailClosedCompliant)
        XCTAssertTrue(defaultGate.enabledSwitchNames.isEmpty)
        XCTAssertFalse(defaultGate.permitsAnyCombination)

        var opened = SponsoredRewardCapabilities()
        opened.cash = true
        opened.random = true
        let openedEval = CouponAndSponsoredRewardSafetyAudit.auditDefaultCapabilitiesGate(capabilities: opened)
        XCTAssertFalse(openedEval.isFailClosedCompliant)
        XCTAssertEqual(openedEval.enabledSwitchNames, ["cash", "random"])
        XCTAssertEqual(
            openedEval.violations,
            [.sponsoredCapabilitiesEnabledByDefault(["cash", "random"])]
        )
    }
}
