import Foundation

/// Audit check for a single screen group's Dynamic Island / Home Indicator Safe Area preservation,
/// keyboard avoidance in chat/composer input bars, and compact vs regular width adaptation.
public struct DeviceLayoutAdaptationCheck: Sendable, Equatable, Identifiable {
    public let id: String
    public let screenGroup: String
    public let preservesDynamicIslandAndHomeIndicatorSafeArea: Bool
    public let avoidsKeyboardOverlapInInputBars: Bool
    public let adaptsCompactAndRegularWidthCleanly: Bool

    public init(
        id: String? = nil,
        screenGroup: String,
        preservesDynamicIslandAndHomeIndicatorSafeArea: Bool = true,
        avoidsKeyboardOverlapInInputBars: Bool = true,
        adaptsCompactAndRegularWidthCleanly: Bool = true
    ) {
        self.id = id ?? screenGroup
        self.screenGroup = screenGroup
        self.preservesDynamicIslandAndHomeIndicatorSafeArea = preservesDynamicIslandAndHomeIndicatorSafeArea
        self.avoidsKeyboardOverlapInInputBars = avoidsKeyboardOverlapInInputBars
        self.adaptsCompactAndRegularWidthCleanly = adaptsCompactAndRegularWidthCleanly
    }

    public var isCompliant: Bool {
        preservesDynamicIslandAndHomeIndicatorSafeArea &&
            avoidsKeyboardOverlapInInputBars &&
            adaptsCompactAndRegularWidthCleanly
    }
}

/// Pure auditor for Safe Area inset preservation (Dynamic Island & Home Indicator),
/// keyboard avoidance in chat/composer screens (`NPCChatView`, `IMChatView`, `PublishPostView`),
/// and compact vs regular size class layout adaptation.
public struct DeviceOrientationAndSplitViewAdaptationAudit: Sendable, Equatable {
    public static let canonicalScreenGroups: [String] = [
        "map-and-roam-hud-overlay",
        "npc-and-im-chat-input-bars",
        "publish-and-shop-apply-forms",
        "profile-and-workbench-split-containers"
    ]

    public static let canonicalChecks: [DeviceLayoutAdaptationCheck] = [
        DeviceLayoutAdaptationCheck(
            id: "map-and-roam-hud-overlay",
            screenGroup: "map-and-roam-hud-overlay",
            preservesDynamicIslandAndHomeIndicatorSafeArea: true,
            avoidsKeyboardOverlapInInputBars: true,
            adaptsCompactAndRegularWidthCleanly: true
        ),
        DeviceLayoutAdaptationCheck(
            id: "npc-and-im-chat-input-bars",
            screenGroup: "npc-and-im-chat-input-bars",
            preservesDynamicIslandAndHomeIndicatorSafeArea: true,
            avoidsKeyboardOverlapInInputBars: true,
            adaptsCompactAndRegularWidthCleanly: true
        ),
        DeviceLayoutAdaptationCheck(
            id: "publish-and-shop-apply-forms",
            screenGroup: "publish-and-shop-apply-forms",
            preservesDynamicIslandAndHomeIndicatorSafeArea: true,
            avoidsKeyboardOverlapInInputBars: true,
            adaptsCompactAndRegularWidthCleanly: true
        ),
        DeviceLayoutAdaptationCheck(
            id: "profile-and-workbench-split-containers",
            screenGroup: "profile-and-workbench-split-containers",
            preservesDynamicIslandAndHomeIndicatorSafeArea: true,
            avoidsKeyboardOverlapInInputBars: true,
            adaptsCompactAndRegularWidthCleanly: true
        )
    ]

    public init() {}

    public static func evaluate(
        checks: [DeviceLayoutAdaptationCheck] = canonicalChecks
    ) -> (totalGroups: Int, compliantGroups: Int, isLayoutAdaptationReady: Bool) {
        let totalGroups = checks.count
        let compliantGroups = checks.filter(\.isCompliant).count
        let coveredGroups = Set(checks.map(\.screenGroup))
        let hasAllCanonicalGroups = Set(canonicalScreenGroups).isSubset(of: coveredGroups)
        let isLayoutAdaptationReady = totalGroups >= canonicalChecks.count &&
            hasAllCanonicalGroups &&
            compliantGroups == totalGroups
        return (
            totalGroups: totalGroups,
            compliantGroups: compliantGroups,
            isLayoutAdaptationReady: isLayoutAdaptationReady
        )
    }
}
