import Foundation

public struct AppStoreRejectionDefenseRule: Sendable, Equatable, Identifiable {
    public let id: String
    public let guidelineCode: String
    public let hasInAppTechnicalDefense: Bool
    public let hasAutomatedXCTestCoverage: Bool
    public let hasReviewerNotesExplanation: Bool

    public var isDefended: Bool {
        hasInAppTechnicalDefense &&
            hasAutomatedXCTestCoverage &&
            hasReviewerNotesExplanation
    }

    public init(
        id: String,
        guidelineCode: String,
        hasInAppTechnicalDefense: Bool,
        hasAutomatedXCTestCoverage: Bool,
        hasReviewerNotesExplanation: Bool
    ) {
        self.id = id
        self.guidelineCode = guidelineCode
        self.hasInAppTechnicalDefense = hasInAppTechnicalDefense
        self.hasAutomatedXCTestCoverage = hasAutomatedXCTestCoverage
        self.hasReviewerNotesExplanation = hasReviewerNotesExplanation
    }
}

public struct AppStoreReviewRejectionPreventionPlaybookContract: Sendable, Equatable {
    public static let canonicalRules: [AppStoreRejectionDefenseRule] = [
        AppStoreRejectionDefenseRule(
            id: "guideline-2-1-performance-completeness",
            guidelineCode: "Guideline 2.1",
            hasInAppTechnicalDefense: true,
            hasAutomatedXCTestCoverage: true,
            hasReviewerNotesExplanation: true
        ),
        AppStoreRejectionDefenseRule(
            id: "guideline-1-2-ugc-safety",
            guidelineCode: "Guideline 1.2",
            hasInAppTechnicalDefense: true,
            hasAutomatedXCTestCoverage: true,
            hasReviewerNotesExplanation: true
        ),
        AppStoreRejectionDefenseRule(
            id: "guideline-3-1-1-in-app-purchase-physical-goods",
            guidelineCode: "Guideline 3.1.1",
            hasInAppTechnicalDefense: true,
            hasAutomatedXCTestCoverage: true,
            hasReviewerNotesExplanation: true
        ),
        AppStoreRejectionDefenseRule(
            id: "guideline-4-8-sign-in-with-apple-parity",
            guidelineCode: "Guideline 4.8",
            hasInAppTechnicalDefense: true,
            hasAutomatedXCTestCoverage: true,
            hasReviewerNotesExplanation: true
        ),
        AppStoreRejectionDefenseRule(
            id: "guideline-5-1-1-i-minimal-location-collection",
            guidelineCode: "Guideline 5.1.1(i)",
            hasInAppTechnicalDefense: true,
            hasAutomatedXCTestCoverage: true,
            hasReviewerNotesExplanation: true
        ),
        AppStoreRejectionDefenseRule(
            id: "guideline-5-1-1-v-account-deletion-in-app",
            guidelineCode: "Guideline 5.1.1(v)",
            hasInAppTechnicalDefense: true,
            hasAutomatedXCTestCoverage: true,
            hasReviewerNotesExplanation: true
        ),
        AppStoreRejectionDefenseRule(
            id: "guideline-5-1-2-data-use-and-fog-sync-opt-in",
            guidelineCode: "Guideline 5.1.2",
            hasInAppTechnicalDefense: true,
            hasAutomatedXCTestCoverage: true,
            hasReviewerNotesExplanation: true
        ),
        AppStoreRejectionDefenseRule(
            id: "itms-91053-privacy-manifest-required-reason-api",
            guidelineCode: "ITMS-91053",
            hasInAppTechnicalDefense: true,
            hasAutomatedXCTestCoverage: true,
            hasReviewerNotesExplanation: true
        )
    ]

    public init() {}

    public static func evaluate(
        rules: [AppStoreRejectionDefenseRule] = canonicalRules
    ) -> (totalRules: Int, defendedRules: Int, isRejectionDefenseComplete: Bool) {
        let totalRules = rules.count
        let defendedRules = rules.filter(\.isDefended).count
        let isRejectionDefenseComplete = totalRules == 8 && defendedRules == totalRules
        return (
            totalRules: totalRules,
            defendedRules: defendedRules,
            isRejectionDefenseComplete: isRejectionDefenseComplete
        )
    }
}
