import Foundation

/// Self-contained safety and parity audit across `w2-05` (Coupon Runtime Journey & Withdrawal Handoff)
/// and `G-W07` / `W17` (Sponsored Reward Pool Disclosure, Frozen Voucher Terms & Capability Gating):
/// 1. `w2-05` coupon runtime journey and `couponRuntimeJourney` UI readiness anchor (`couponRuntime.root`, `couponRuntime.readOnlyConfirm`),
/// 2. `G-W07` sponsored reward pool disclosure (`limitedWhileSuppliesLast` vs `guaranteedReserved`),
/// 3. Frozen voucher terms readback protection (preventing silent post-claim term mutations or shortened validity),
/// 4. Fail-closed `SponsoredRewardCapabilities.disabled` default gate.
public enum CouponAndSponsoredRewardSafetyAudit {

    // MARK: - Violation Enumeration

    public enum SafetyViolation: Equatable, Sendable {
        case missingCouponRuntimeAnchors([String])
        case qr503ContinuesAutoPolling
        case liveCouponQRDispatchEnabledByDefault
        case unreservedPoolClaimedAsGuaranteed
        case voucherTermsMutatedAfterIssue(voucherID: String, issuedVersion: String, laterVersion: String)
        case voucherValidityShortenedAfterIssue(voucherID: String)
        case voucherIDMismatchOnReadback(issuedID: String, laterID: String)
        case sponsoredCapabilitiesEnabledByDefault([String])
        case presentableDespiteDisabledCapability
    }

    // MARK: - Pillar 1: w2-05 Coupon Runtime Journey & UI Readiness Anchor Audit

    public struct CouponRuntimeJourneyEvaluation: Equatable, Sendable {
        public static let expectedRootAnchor = "couponRuntime.root"
        public static let expectedPrimaryAnchor = "couponRuntime.readOnlyConfirm"

        public let mountedAnchors: Set<String>
        public let missingAnchors: [String]
        public let stopsAutoRefreshOn503: Bool
        public let liveQRTokenDispatchDefaultDisabled: Bool
        public let violations: [SafetyViolation]

        public var isAnchorReady: Bool { missingAnchors.isEmpty }
        public var isCompliant: Bool { violations.isEmpty }

        public init(
            mountedAnchors: Set<String> = [
                CouponRuntimeJourneyEvaluation.expectedRootAnchor,
                CouponRuntimeJourneyEvaluation.expectedPrimaryAnchor
            ],
            stopsAutoRefreshOn503: Bool = true,
            liveQRTokenDispatchDefaultDisabled: Bool = true
        ) {
            self.mountedAnchors = mountedAnchors
            let contract = UIReadinessAnchorContract.contract(for: .couponRuntimeJourney)
            let readiness = contract.evaluateReadiness(
                mountedIdentifiers: mountedAnchors,
                offScreenRevealed: true
            )
            let missing: [String]
            switch readiness {
            case .ready:
                missing = []
            case .missingAnchors(let list):
                missing = list
            case .awaitingOffScreenReveal(_, let target):
                missing = [target]
            }
            self.missingAnchors = missing
            self.stopsAutoRefreshOn503 = stopsAutoRefreshOn503
            self.liveQRTokenDispatchDefaultDisabled = liveQRTokenDispatchDefaultDisabled

            var foundViolations: [SafetyViolation] = []
            if !missing.isEmpty {
                foundViolations.append(.missingCouponRuntimeAnchors(missing))
            }
            if !stopsAutoRefreshOn503 {
                foundViolations.append(.qr503ContinuesAutoPolling)
            }
            if !liveQRTokenDispatchDefaultDisabled {
                foundViolations.append(.liveCouponQRDispatchEnabledByDefault)
            }
            self.violations = foundViolations
        }
    }

    public static func auditCouponRuntimeJourney(
        mountedAnchors: Set<String> = [
            CouponRuntimeJourneyEvaluation.expectedRootAnchor,
            CouponRuntimeJourneyEvaluation.expectedPrimaryAnchor
        ],
        stopsAutoRefreshOn503: Bool = true,
        liveQRTokenDispatchDefaultDisabled: Bool = true
    ) -> CouponRuntimeJourneyEvaluation {
        CouponRuntimeJourneyEvaluation(
            mountedAnchors: mountedAnchors,
            stopsAutoRefreshOn503: stopsAutoRefreshOn503,
            liveQRTokenDispatchDefaultDisabled: liveQRTokenDispatchDefaultDisabled
        )
    }

    // MARK: - Pillar 2: G-W07 Sponsored Reward Pool Disclosure Audit

    public struct PoolDisclosureEvaluation: Equatable, Sendable {
        public let itemID: String
        public let allocation: SponsoredAllocation
        public let guaranteeReserved: Bool
        public let computedDisclosure: SponsoredPoolItem.Disclosure
        public let isPresentableUnderCapabilities: Bool
        public let violations: [SafetyViolation]

        public var isCompliant: Bool { violations.isEmpty }

        public init(
            item: SponsoredPoolItem,
            capabilities: SponsoredRewardCapabilities = .disabled,
            claimedDisclosureOverride: SponsoredPoolItem.Disclosure? = nil
        ) {
            self.itemID = item.itemID
            self.allocation = item.allocation
            self.guaranteeReserved = item.guaranteeReserved
            let actualDisclosure = claimedDisclosureOverride ?? item.disclosure
            self.computedDisclosure = actualDisclosure
            let presentable = item.isPresentable(capabilities)
            self.isPresentableUnderCapabilities = presentable

            var foundViolations: [SafetyViolation] = []
            if actualDisclosure == .guaranteedReserved,
               !(item.allocation == .guaranteed && item.guaranteeReserved) {
                foundViolations.append(.unreservedPoolClaimedAsGuaranteed)
            }
            if !capabilities.permits(item.kind, item.allocation) && presentable {
                foundViolations.append(.presentableDespiteDisabledCapability)
            }
            self.violations = foundViolations
        }
    }

    public static func auditPoolDisclosure(
        item: SponsoredPoolItem,
        capabilities: SponsoredRewardCapabilities = .disabled,
        claimedDisclosureOverride: SponsoredPoolItem.Disclosure? = nil
    ) -> PoolDisclosureEvaluation {
        PoolDisclosureEvaluation(
            item: item,
            capabilities: capabilities,
            claimedDisclosureOverride: claimedDisclosureOverride
        )
    }

    // MARK: - Pillar 3: Frozen Voucher Terms Readback Protection Audit

    public struct FrozenVoucherTermsEvaluation: Equatable, Sendable {
        public let issued: SponsoredVoucherTerms
        public let later: SponsoredVoucherTerms
        public let readbackAccepted: Bool
        public let rejectionReasons: [SafetyViolation]

        public var isProtectedAgainstSilentMutation: Bool {
            if readbackAccepted {
                return rejectionReasons.isEmpty
            }
            return !rejectionReasons.isEmpty
        }

        public init(issued: SponsoredVoucherTerms, later: SponsoredVoucherTerms) {
            self.issued = issued
            self.later = later
            self.readbackAccepted = SponsoredVoucherTerms.acceptsReadback(issued: issued, later: later)

            var reasons: [SafetyViolation] = []
            if later.voucherID != issued.voucherID {
                reasons.append(.voucherIDMismatchOnReadback(issuedID: issued.voucherID, laterID: later.voucherID))
            }
            if later.termsVersion != issued.termsVersion {
                reasons.append(
                    .voucherTermsMutatedAfterIssue(
                        voucherID: issued.voucherID,
                        issuedVersion: issued.termsVersion,
                        laterVersion: later.termsVersion
                    )
                )
            }
            if later.validUntil < issued.validUntil {
                reasons.append(.voucherValidityShortenedAfterIssue(voucherID: issued.voucherID))
            }
            self.rejectionReasons = reasons
        }
    }

    public static func auditFrozenVoucherTerms(
        issued: SponsoredVoucherTerms,
        later: SponsoredVoucherTerms
    ) -> FrozenVoucherTermsEvaluation {
        FrozenVoucherTermsEvaluation(issued: issued, later: later)
    }

    // MARK: - Pillar 4: Fail-Closed SponsoredRewardCapabilities.disabled Default Gate

    public struct CapabilityGateEvaluation: Equatable, Sendable {
        public let capabilities: SponsoredRewardCapabilities
        public let enabledSwitchNames: [String]
        public let permitsAnyCombination: Bool
        public let violations: [SafetyViolation]

        public var isFailClosedCompliant: Bool {
            enabledSwitchNames.isEmpty && !permitsAnyCombination && violations.isEmpty
        }

        public init(capabilities: SponsoredRewardCapabilities = .disabled) {
            self.capabilities = capabilities
            var enabled: [String] = []
            if capabilities.nonCash { enabled.append("nonCash") }
            if capabilities.cash { enabled.append("cash") }
            if capabilities.random { enabled.append("random") }
            if capabilities.guaranteed { enabled.append("guaranteed") }
            self.enabledSwitchNames = enabled

            var anyPermitted = false
            for kind in SponsoredPrizeKind.allCases {
                for allocation in SponsoredAllocation.allCases {
                    if capabilities.permits(kind, allocation) {
                        anyPermitted = true
                    }
                }
            }
            self.permitsAnyCombination = anyPermitted

            var foundViolations: [SafetyViolation] = []
            if !enabled.isEmpty {
                foundViolations.append(.sponsoredCapabilitiesEnabledByDefault(enabled))
            }
            self.violations = foundViolations
        }
    }

    public static func auditDefaultCapabilitiesGate(
        capabilities: SponsoredRewardCapabilities = .disabled
    ) -> CapabilityGateEvaluation {
        CapabilityGateEvaluation(capabilities: capabilities)
    }

    // MARK: - Aggregate Report

    public struct FullCouponAndRewardSafetyReport: Equatable, Sendable {
        public let couponRuntime: CouponRuntimeJourneyEvaluation
        public let poolDisclosure: PoolDisclosureEvaluation
        public let frozenVoucher: FrozenVoucherTermsEvaluation
        public let capabilityGate: CapabilityGateEvaluation

        public var allPillarsCompliant: Bool {
            couponRuntime.isCompliant
                && poolDisclosure.isCompliant
                && frozenVoucher.isProtectedAgainstSilentMutation
                && capabilityGate.isFailClosedCompliant
        }

        public init(
            couponRuntime: CouponRuntimeJourneyEvaluation,
            poolDisclosure: PoolDisclosureEvaluation,
            frozenVoucher: FrozenVoucherTermsEvaluation,
            capabilityGate: CapabilityGateEvaluation
        ) {
            self.couponRuntime = couponRuntime
            self.poolDisclosure = poolDisclosure
            self.frozenVoucher = frozenVoucher
            self.capabilityGate = capabilityGate
        }
    }
}
