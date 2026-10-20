import Foundation

/// Pure self-contained value types auditing all 5 deterministic UI test flow readiness anchors:
/// 1. `projectEditor` (including `revealProjectEditorNameInForm` off-screen form scroll/reveal contract)
/// 2. `profileSelfEdit`
/// 3. `roamFinishedHistory`
/// 4. `couponRuntimeJourney`
/// 5. `mapCoreEntry` (`--uitesting-map-core-entry`)
public enum UITestFlowSurfaceID: String, CaseIterable, Sendable, Equatable {
    case projectEditor
    case profileSelfEdit
    case roamFinishedHistory
    case couponRuntimeJourney
    case mapCoreEntry
}

public struct UITestFlowReadinessAnchorRecord: Identifiable, Equatable, Sendable {
    public let surface: UITestFlowSurfaceID
    public let readinessAnchorIdentifier: String
    public let launchArgument: String
    public let offScreenRevealHelper: String?
    public let requiresFormRevealBeforeTyping: Bool
    public let isDeterministicOffline: Bool

    public var id: String { surface.rawValue }

    public init(
        surface: UITestFlowSurfaceID,
        readinessAnchorIdentifier: String,
        launchArgument: String,
        offScreenRevealHelper: String? = nil,
        requiresFormRevealBeforeTyping: Bool = false,
        isDeterministicOffline: Bool = true
    ) {
        self.surface = surface
        self.readinessAnchorIdentifier = readinessAnchorIdentifier
        self.launchArgument = launchArgument
        self.offScreenRevealHelper = offScreenRevealHelper
        self.requiresFormRevealBeforeTyping = requiresFormRevealBeforeTyping
        self.isDeterministicOffline = isDeterministicOffline
    }

    public var isAnchorValid: Bool {
        let anchorTrimmed = readinessAnchorIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let launchTrimmed = launchArgument.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !anchorTrimmed.isEmpty, !launchTrimmed.isEmpty, isDeterministicOffline else {
            return false
        }
        if surface == .projectEditor || requiresFormRevealBeforeTyping {
            guard let helper = offScreenRevealHelper?.trimmingCharacters(in: .whitespacesAndNewlines),
                  helper == "revealProjectEditorNameInForm" else {
                return false
            }
        }
        return true
    }
}

public struct UITestFlowReadinessAnchorAudit: Equatable, Sendable {
    public static let projectEditorRevealHelperName = "revealProjectEditorNameInForm"
    public static let mapCoreEntryLaunchFlag = "--uitesting-map-core-entry"

    public static let defaultAnchors: [UITestFlowReadinessAnchorRecord] = [
        UITestFlowReadinessAnchorRecord(
            surface: .projectEditor,
            readinessAnchorIdentifier: "projectEdit.form.name",
            launchArgument: "--uitesting-project-editor",
            offScreenRevealHelper: projectEditorRevealHelperName,
            requiresFormRevealBeforeTyping: true
        ),
        UITestFlowReadinessAnchorRecord(
            surface: .profileSelfEdit,
            readinessAnchorIdentifier: "profile.selfEdit.nickname",
            launchArgument: "--uitesting-profile-self-edit"
        ),
        UITestFlowReadinessAnchorRecord(
            surface: .roamFinishedHistory,
            readinessAnchorIdentifier: "roam.finishedHistory.list",
            launchArgument: "--uitesting-roam-finished-history"
        ),
        UITestFlowReadinessAnchorRecord(
            surface: .couponRuntimeJourney,
            readinessAnchorIdentifier: "accountCollection.coupons.list",
            launchArgument: "--uitesting-coupon-runtime-journey"
        ),
        UITestFlowReadinessAnchorRecord(
            surface: .mapCoreEntry,
            readinessAnchorIdentifier: "mapCore.entry.cityOrienteering",
            launchArgument: mapCoreEntryLaunchFlag
        )
    ]

    public let anchors: [UITestFlowReadinessAnchorRecord]

    public init(anchors: [UITestFlowReadinessAnchorRecord] = UITestFlowReadinessAnchorAudit.defaultAnchors) {
        self.anchors = anchors
    }

    public func anchor(for surface: UITestFlowSurfaceID) -> UITestFlowReadinessAnchorRecord? {
        anchors.first { $0.surface == surface }
    }

    public var missingSurfaces: [UITestFlowSurfaceID] {
        let present = Set(anchors.map(\.surface))
        return UITestFlowSurfaceID.allCases.filter { !present.contains($0) }
    }

    public var invalidSurfaces: [UITestFlowSurfaceID] {
        anchors.filter { !$0.isAnchorValid }.map(\.surface)
    }

    public var isAllReady: Bool {
        anchors.count == UITestFlowSurfaceID.allCases.count
            && missingSurfaces.isEmpty
            && invalidSurfaces.isEmpty
    }
}
