import Foundation

/// Wave 1–5 Unified Master Parity Inventory cataloging:
/// - All 21 Wave-2 mini-program parity scopes (`w2-01` through `w2-21`)
/// - All 13 Wave-3 handoff scopes (`I00` through `I11`, plus `BK`)
/// - All Reform Plan v9 `F`, `G`, and `H` work packages (`W02` through `W20`, `U01` through `U08`)
/// - Release-readiness verification ensuring high-risk write/payment/cash switches remain fail-closed (`false`) by default.
public enum WaveUnifiedParityInventory {

    // MARK: - Models

    public struct Wave2ScopeEntry: Equatable, Sendable {
        public let id: String
        public let ordinal: Int
        public let domain: String
        public let isIntegrated: Bool

        public init(id: String, ordinal: Int, domain: String, isIntegrated: Bool = true) {
            self.id = id
            self.ordinal = ordinal
            self.domain = domain
            self.isIntegrated = isIntegrated
        }
    }

    public struct Wave3HandoffEntry: Equatable, Sendable {
        public let id: String
        public let slug: String
        public let handoffDocument: String
        public let isClosed: Bool

        public init(id: String, slug: String, handoffDocument: String, isClosed: Bool = true) {
            self.id = id
            self.slug = slug
            self.handoffDocument = handoffDocument
            self.isClosed = isClosed
        }
    }

    public enum ReformPlanOwnerTrack: String, CaseIterable, Equatable, Sendable {
        case agentF = "F"
        case agentG = "G"
        case agentH = "H"
        case unifiedDecision = "U"
    }

    public struct ReformWorkPackageEntry: Equatable, Sendable {
        public let id: String
        public let track: ReformPlanOwnerTrack
        public let title: String
        public let defaultFailClosed: Bool

        public init(id: String, track: ReformPlanOwnerTrack, title: String, defaultFailClosed: Bool = true) {
            self.id = id
            self.track = track
            self.title = title
            self.defaultFailClosed = defaultFailClosed
        }
    }

    public struct HighRiskSwitchStatus: Equatable, Sendable {
        public let name: String
        public let isEnabled: Bool
        public var isFailClosed: Bool { !isEnabled }

        public init(name: String, isEnabled: Bool) {
            self.name = name
            self.isEnabled = isEnabled
        }
    }

    public struct ReleaseReadinessReport: Equatable, Sendable {
        public let wave2Count: Int
        public let wave3Count: Int
        public let reformWorkPackageCount: Int
        public let unifiedDecisionCount: Int
        public let missingWave2IDs: [String]
        public let missingWave3IDs: [String]
        public let missingReformPackageIDs: [String]
        public let missingUnifiedDecisionIDs: [String]
        public let openHighRiskSwitches: [String]

        public init(
            wave2Count: Int,
            wave3Count: Int,
            reformWorkPackageCount: Int,
            unifiedDecisionCount: Int,
            missingWave2IDs: [String] = [],
            missingWave3IDs: [String] = [],
            missingReformPackageIDs: [String] = [],
            missingUnifiedDecisionIDs: [String] = [],
            openHighRiskSwitches: [String] = []
        ) {
            self.wave2Count = wave2Count
            self.wave3Count = wave3Count
            self.reformWorkPackageCount = reformWorkPackageCount
            self.unifiedDecisionCount = unifiedDecisionCount
            self.missingWave2IDs = missingWave2IDs
            self.missingWave3IDs = missingWave3IDs
            self.missingReformPackageIDs = missingReformPackageIDs
            self.missingUnifiedDecisionIDs = missingUnifiedDecisionIDs
            self.openHighRiskSwitches = openHighRiskSwitches
        }

        public var allScopesAccountedFor: Bool {
            wave2Count == 21
                && wave3Count == 13
                && reformWorkPackageCount == 19
                && unifiedDecisionCount == 8
                && missingWave2IDs.isEmpty
                && missingWave3IDs.isEmpty
                && missingReformPackageIDs.isEmpty
                && missingUnifiedDecisionIDs.isEmpty
        }

        public var allHighRiskSwitchesFailClosed: Bool {
            openHighRiskSwitches.isEmpty
        }

        public var isReleaseReady: Bool {
            allScopesAccountedFor && allHighRiskSwitchesFailClosed
        }
    }

    // MARK: - 21 Wave-2 Mini-Program Parity Scopes (w2-01 .. w2-21)

    public static let expectedWave2IDs: [String] = (1...21).map { String(format: "w2-%02d", $0) }

    public static let wave2Scopes: [Wave2ScopeEntry] = [
        .init(id: "w2-01", ordinal: 1, domain: "Auth, Session & Account Lifecycle"),
        .init(id: "w2-02", ordinal: 2, domain: "Home Discovery & Featured Feeds"),
        .init(id: "w2-03", ordinal: 3, domain: "Topic Catalog & Detail Presentation"),
        .init(id: "w2-04", ordinal: 4, domain: "Play Runtime, Checkpoints & Story Flow"),
        .init(id: "w2-05", ordinal: 5, domain: "Roam Map, Tiles & Presence Readback"),
        .init(id: "w2-06", ordinal: 6, domain: "Search Map & Walking Route Explorer"),
        .init(id: "w2-07", ordinal: 7, domain: "Creative Square & Community Posts"),
        .init(id: "w2-08", ordinal: 8, domain: "Social Comments, Likes & Bookmarks"),
        .init(id: "w2-09", ordinal: 9, domain: "Team Lobby, Invites & Formation"),
        .init(id: "w2-10", ordinal: 10, domain: "Activity Sign-Up & Registration"),
        .init(id: "w2-11", ordinal: 11, domain: "Member Profile, Favorites & Collections"),
        .init(id: "w2-12", ordinal: 12, domain: "Coupons, Vouchers & QR Redemption"),
        .init(id: "w2-13", ordinal: 13, domain: "Member Orders & Aftercare Status"),
        .init(id: "w2-14", ordinal: 14, domain: "Workshop Templates & Purchased Library"),
        .init(id: "w2-15", ordinal: 15, domain: "Pro Editor & Topic Publishing"),
        .init(id: "w2-16", ordinal: 16, domain: "Merchant Workbench & Store Profile"),
        .init(id: "w2-17", ordinal: 17, domain: "Merchant Decor, AI NPC & Game Nodes"),
        .init(id: "w2-18", ordinal: 18, domain: "Merchant Marketing & Perk Validity"),
        .init(id: "w2-19", ordinal: 19, domain: "Merchant Ledger, Orders & Redemptions"),
        .init(id: "w2-20", ordinal: 20, domain: "Merchant Team & Operator Roles"),
        .init(id: "w2-21", ordinal: 21, domain: "Coop Finance, Asset Center & Settings")
    ]

    // MARK: - 13 Wave-3 Handoff Scopes (I00 .. I11, BK)

    public static let expectedWave3IDs: [String] = [
        "I00", "I01", "I02", "I03", "I04", "I05", "I06", "I07", "I08", "I09", "I10", "I11", "BK"
    ]

    public static let wave3HandoffScopes: [Wave3HandoffEntry] = [
        .init(id: "I00", slug: "baseline-governance", handoffDocument: "docs/handoff/ios-I00-20261019.md"),
        .init(id: "I01", slug: "auth-session-boundary", handoffDocument: "docs/handoff/ios-I01-20261019.md"),
        .init(id: "I02", slug: "play-session-authority", handoffDocument: "docs/handoff/ios-I02-20261019.md"),
        .init(id: "I03", slug: "roam-presence-tile-isolation", handoffDocument: "docs/handoff/ios-I03-20261019.md"),
        .init(id: "I04", slug: "square-workspace-draft-isolation", handoffDocument: "docs/handoff/ios-I04-20261019.md"),
        .init(id: "I05", slug: "privacy-likes", handoffDocument: "docs/handoff/ios-I05-20261019.md"),
        .init(id: "I06", slug: "social-bookmark-comment-guards", handoffDocument: "docs/handoff/ios-I06-20261019.md"),
        .init(id: "I07", slug: "team-activity-deadline-fences", handoffDocument: "docs/handoff/ios-I07-20261019.md"),
        .init(id: "I08", slug: "profile-collection-favorite-readback", handoffDocument: "docs/handoff/ios-I08-20261019.md"),
        .init(id: "I09", slug: "workshop-install-binding", handoffDocument: "docs/handoff/ios-I09-20261019.md"),
        .init(id: "I10", slug: "merchant-operator-permission-scope", handoffDocument: "docs/handoff/ios-I10-20261019.md"),
        .init(id: "I11", slug: "order-aftercare-voucher-readback", handoffDocument: "docs/handoff/ios-I11-20261019.md"),
        .init(id: "BK", slug: "backend-sync-contracts", handoffDocument: "docs/handoff/ios-BK-20261019.md")
    ]

    // MARK: - Reform Plan v9 Work Packages (W02 .. W20) & Unified Decisions (U01 .. U08)

    public static let expectedReformPackageIDs: [String] = (2...20).map { String(format: "W%02d", $0) }
    public static let expectedUnifiedDecisionIDs: [String] = (1...8).map { String(format: "U%02d", $0) }

    public static let reformWorkPackages: [ReformWorkPackageEntry] = [
        .init(id: "W02", track: .agentH, title: "World, Season, Theme Release & Content Ownership"),
        .init(id: "W03", track: .agentH, title: "Authoritative Run State, CAS & Idempotent Action Receipts"),
        .init(id: "W04", track: .agentG, title: "Scene AI Scope Isolation, Memory Layers & Kill Switches"),
        .init(id: "W05", track: .agentG, title: "Merchant AI Authoring, In-Store Game & Environment Branches"),
        .init(id: "W06", track: .agentG, title: "Commerce Order Line Fulfilment, Entitlements & Refunds"),
        .init(id: "W07", track: .agentG, title: "Merchant Staff Scope, Redemption & Append-Only Reward Ledger"),
        .init(id: "W08", track: .agentG, title: "Payment Callback & Outbox Boundary (Server-Only / Client Query)"),
        .init(id: "W09", track: .agentH, title: "Content Moderation & Preflight Gate Contracts"),
        .init(id: "W10", track: .agentH, title: "Media Asset Pipeline & Digest Readback Verification"),
        .init(id: "W11", track: .agentF, title: "Map Visual Style Tokens, Contrast & Day/Night Appearance"),
        .init(id: "W12", track: .agentF, title: "Coordinate Observation, CRS Normalization & Fog Grid Foundations"),
        .init(id: "W13", track: .agentF, title: "Typed Map Layer Sources, Place Identity & Voluntary Location Sharing"),
        .init(id: "W14", track: .agentF, title: "Independent Merchant Side-Quests, Evidence Guard & Personal Fog"),
        .init(id: "W15", track: .agentF, title: "In-App Walking Navigation & Authoritative Story Stop Sequence"),
        .init(id: "W16", track: .agentH, title: "Team-First Stranger Meeting & Dynamic QR Handshake"),
        .init(id: "W17", track: .agentG, title: "Sponsored Reward Pools, Voucher Terms & Non-Cash Isolation"),
        .init(id: "W18", track: .agentH, title: "Play Library, Creator Marketplace & Explicit Mod Upgrades"),
        .init(id: "W19", track: .agentH, title: "Private Home Base & Return-Home Resource Restore"),
        .init(id: "W20", track: .agentH, title: "Resident CITY Business Game Actions & Delta Stream")
    ]

    public static let unifiedDecisionPackages: [ReformWorkPackageEntry] = [
        .init(id: "U01", track: .unifiedDecision, title: "Image & Video Publishing Media Chain Evidence"),
        .init(id: "U02", track: .unifiedDecision, title: "In-App Multi-Select Friend Invites with Stable Request IDs"),
        .init(id: "U03", track: .unifiedDecision, title: "Phone-Zone Display with Governing Beijing Deadlines"),
        .init(id: "U04", track: .unifiedDecision, title: "Revoke-Wins Terminal State Ledger"),
        .init(id: "U05", track: .unifiedDecision, title: "Meet Only After Confirmed Team Formation"),
        .init(id: "U06", track: .unifiedDecision, title: "Scoped Real-Name Requirement for Stranger Team Meeting Only"),
        .init(id: "U07", track: .unifiedDecision, title: "Dynamic QR Handshake with NFC Kept Disabled"),
        .init(id: "U08", track: .unifiedDecision, title: "Standard qmod Manifest Contract with H5 Design-Only")
    ]

    // MARK: - Fail-Closed Switch Inspection & Release Readiness Verification

    public static func evaluateHighRiskSwitches() -> [HighRiskSwitchStatus] {
        let gates = MerchantAICommerceGates.disabled
        let world = ReformWorldCapabilities.disabled
        var statuses: [HighRiskSwitchStatus] = [
            .init(name: "MapLayerFeature.aggregatedQueryEnabled", isEnabled: MapLayerFeature.aggregatedQueryEnabled),
            .init(name: "SideQuestFeature.acceptEnabled", isEnabled: SideQuestFeature.acceptEnabled),
            .init(name: "PersonalFogFeature.revealSyncEnabled", isEnabled: PersonalFogFeature.revealSyncEnabled),
            .init(name: "MerchantAICommerceGates.paymentAndCashEnabled", isEnabled: gates.paymentAndCashEnabled),
            .init(name: "MerchantAICommerceGates.merchantAuthoringPublish", isEnabled: gates.merchantAuthoringPublish),
            .init(name: "MerchantAICommerceGates.orderLineReadback", isEnabled: gates.orderLineReadback),
            .init(name: "MerchantAICommerceGates.staffScopeReadback", isEnabled: gates.staffScopeReadback),
            .init(name: "MerchantAICommerceGates.rewardLedgerReadback", isEnabled: gates.rewardLedgerReadback),
            .init(name: "MerchantAICommerceGates.reviewedEndpointsNonEmpty", isEnabled: !MerchantAICommerceGates.reviewedEndpoints.isEmpty),
            .init(name: "SceneAIAvailability.globalGenerationEnabled", isEnabled: gates.sceneAI.globalGenerationEnabled),
            .init(name: "SceneAIAvailability.allowsStreamingDisplay", isEnabled: gates.sceneAI.allowsStreamingDisplay),
            .init(name: "SponsoredRewardCapabilities.nonCash", isEnabled: gates.sponsoredRewards.nonCash),
            .init(name: "SponsoredRewardCapabilities.cash", isEnabled: gates.sponsoredRewards.cash),
            .init(name: "SponsoredRewardCapabilities.random", isEnabled: gates.sponsoredRewards.random),
            .init(name: "SponsoredRewardCapabilities.guaranteed", isEnabled: gates.sponsoredRewards.guaranteed),
            .init(name: "CommerceClientPaymentRules.paymentEnabled", isEnabled: CommerceClientPaymentRules.paymentEnabled)
        ]
        for feature in ReformWorldCapabilities.Feature.allCases {
            statuses.append(
                .init(name: "ReformWorldCapabilities.\(feature.rawValue)", isEnabled: world.allows(feature))
            )
        }
        return statuses
    }

    public static func verifyReleaseReadinessInvariants() -> ReleaseReadinessReport {
        let presentWave2 = Set(wave2Scopes.filter(\.isIntegrated).map(\.id))
        let presentWave3 = Set(wave3HandoffScopes.filter(\.isClosed).map(\.id))
        let presentReform = Set(reformWorkPackages.filter(\.defaultFailClosed).map(\.id))
        let presentDecisions = Set(unifiedDecisionPackages.filter(\.defaultFailClosed).map(\.id))

        let missingWave2 = expectedWave2IDs.filter { !presentWave2.contains($0) }
        let missingWave3 = expectedWave3IDs.filter { !presentWave3.contains($0) }
        let missingReform = expectedReformPackageIDs.filter { !presentReform.contains($0) }
        let missingDecisions = expectedUnifiedDecisionIDs.filter { !presentDecisions.contains($0) }

        let openSwitches = evaluateHighRiskSwitches()
            .filter { !$0.isFailClosed }
            .map(\.name)

        return ReleaseReadinessReport(
            wave2Count: wave2Scopes.count,
            wave3Count: wave3HandoffScopes.count,
            reformWorkPackageCount: reformWorkPackages.count,
            unifiedDecisionCount: unifiedDecisionPackages.count,
            missingWave2IDs: missingWave2,
            missingWave3IDs: missingWave3,
            missingReformPackageIDs: missingReform,
            missingUnifiedDecisionIDs: missingDecisions,
            openHighRiskSwitches: openSwitches
        )
    }
}
