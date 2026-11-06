import Foundation

/// Audit check for a single App Store Review Guideline 2.1 reviewer scenario (`USER`, `MERCHANT`, `CLUB_ADMIN`, and guest browse).
public struct AppStoreReviewerScenarioCheck: Sendable, Equatable, Identifiable {
    public let id: String
    public let roleOrScenario: String
    public let supportsOutOfCityLBSPreviewFallback: Bool
    public let zeroInfiniteLoadingOrBlankScreen: Bool
    public let hasReviewerWalkthroughNotes: Bool

    public init(
        id: String? = nil,
        roleOrScenario: String,
        supportsOutOfCityLBSPreviewFallback: Bool = true,
        zeroInfiniteLoadingOrBlankScreen: Bool = true,
        hasReviewerWalkthroughNotes: Bool = true
    ) {
        self.id = id ?? roleOrScenario
        self.roleOrScenario = roleOrScenario
        self.supportsOutOfCityLBSPreviewFallback = supportsOutOfCityLBSPreviewFallback
        self.zeroInfiniteLoadingOrBlankScreen = zeroInfiniteLoadingOrBlankScreen
        self.hasReviewerWalkthroughNotes = hasReviewerWalkthroughNotes
    }

    public var isCompliant: Bool {
        supportsOutOfCityLBSPreviewFallback &&
            zeroInfiniteLoadingOrBlankScreen &&
            hasReviewerWalkthroughNotes
    }
}

/// Pure auditor for App Store Review Guideline 2.1 (App Completeness) reviewer demo readiness:
/// pre-seeded city/POI roam preview when reviewer is outside target city (`LBS` fallback preview),
/// multi-role reviewer walkthrough (`USER`, `MERCHANT`, `CLUB_ADMIN`), and zero infinite-spinner
/// or blank screens when unauthenticated.
public struct AppStoreReviewDemoAccountAndFixtureReadinessAudit: Sendable, Equatable {
    public static let canonicalScenarioNames: [String] = [
        "guest-browse-and-city-roam-preview",
        "authenticated-player-story-and-stamps",
        "merchant-store-and-insight-walkthrough",
        "club-admin-enrollment-and-settlement-walkthrough"
    ]

    public static let canonicalScenarios: [AppStoreReviewerScenarioCheck] = [
        AppStoreReviewerScenarioCheck(
            id: "guest-browse-and-city-roam-preview",
            roleOrScenario: "guest-browse-and-city-roam-preview",
            supportsOutOfCityLBSPreviewFallback: true,
            zeroInfiniteLoadingOrBlankScreen: true,
            hasReviewerWalkthroughNotes: true
        ),
        AppStoreReviewerScenarioCheck(
            id: "authenticated-player-story-and-stamps",
            roleOrScenario: "authenticated-player-story-and-stamps",
            supportsOutOfCityLBSPreviewFallback: true,
            zeroInfiniteLoadingOrBlankScreen: true,
            hasReviewerWalkthroughNotes: true
        ),
        AppStoreReviewerScenarioCheck(
            id: "merchant-store-and-insight-walkthrough",
            roleOrScenario: "merchant-store-and-insight-walkthrough",
            supportsOutOfCityLBSPreviewFallback: true,
            zeroInfiniteLoadingOrBlankScreen: true,
            hasReviewerWalkthroughNotes: true
        ),
        AppStoreReviewerScenarioCheck(
            id: "club-admin-enrollment-and-settlement-walkthrough",
            roleOrScenario: "club-admin-enrollment-and-settlement-walkthrough",
            supportsOutOfCityLBSPreviewFallback: true,
            zeroInfiniteLoadingOrBlankScreen: true,
            hasReviewerWalkthroughNotes: true
        )
    ]

    public init() {}

    public static func evaluate(
        scenarios: [AppStoreReviewerScenarioCheck] = canonicalScenarios
    ) -> (totalScenarios: Int, compliantScenarios: Int, isReviewDemoReady: Bool) {
        let totalScenarios = scenarios.count
        let compliantScenarios = scenarios.filter(\.isCompliant).count
        let coveredNames = Set(scenarios.map(\.roleOrScenario))
        let hasAllCanonicalScenarios = Set(canonicalScenarioNames).isSubset(of: coveredNames)
        let isReviewDemoReady = totalScenarios >= canonicalScenarios.count &&
            hasAllCanonicalScenarios &&
            compliantScenarios == totalScenarios
        return (
            totalScenarios: totalScenarios,
            compliantScenarios: compliantScenarios,
            isReviewDemoReady: isReviewDemoReady
        )
    }
}
