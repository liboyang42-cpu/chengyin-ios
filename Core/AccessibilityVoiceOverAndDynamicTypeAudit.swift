import Foundation

/// Audited UI surfaces for App Store & I10 accessibility readiness.
public enum AccessibilityAuditSurface: String, CaseIterable, Equatable, Sendable {
    case primaryTabs = "primary_tabs"
    case playRouteMapView = "play_route_map_view"
    case reformPlanV9Sections = "reform_plan_v9_sections"
}

/// VoiceOver specification for an audited interactive or summary element.
public struct VoiceOverElementSpec: Equatable, Sendable {
    public let surface: AccessibilityAuditSurface
    public let identifier: String
    public let combinedLabel: String
    public let hasCombinedChildrenSemantics: Bool

    public init(
        surface: AccessibilityAuditSurface,
        identifier: String,
        combinedLabel: String,
        hasCombinedChildrenSemantics: Bool = true
    ) {
        self.surface = surface
        self.identifier = identifier
        self.combinedLabel = combinedLabel
        self.hasCombinedChildrenSemantics = hasCombinedChildrenSemantics
    }

    public var isValid: Bool {
        !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !combinedLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && hasCombinedChildrenSemantics
    }
}

/// Deterministic Reduce Motion evaluation (`UIAccessibility.isReduceMotionEnabled` parity).
public struct ReduceMotionTransitionDecision: Equatable, Sendable {
    public enum CameraTransitionStyle: String, Equatable, Sendable {
        case instantJump = "instant_jump"
        case animatedFly = "animated_fly"
    }

    public let isReduceMotionEnabled: Bool
    public let usesAnimatedTransition: Bool
    public let durationSeconds: Double
    public let cameraTransitionStyle: CameraTransitionStyle

    public init(isReduceMotionEnabled: Bool, proposedDurationSeconds: Double = 0.35) {
        self.isReduceMotionEnabled = isReduceMotionEnabled
        if isReduceMotionEnabled {
            self.usesAnimatedTransition = false
            self.durationSeconds = 0.0
            self.cameraTransitionStyle = .instantJump
        } else {
            let clamped = max(0.0, proposedDurationSeconds)
            self.usesAnimatedTransition = clamped > 0.0
            self.durationSeconds = clamped
            self.cameraTransitionStyle = clamped > 0.0 ? .animatedFly : .instantJump
        }
    }
}

/// WCAG 2.1 contrast audit for day/night map palettes and status badges (4.5:1 threshold).
public struct ContrastPairAudit: Equatable, Sendable {
    public enum AppearanceMode: String, CaseIterable, Equatable, Sendable {
        case day = "day"
        case night = "night"
    }

    public static let wcagAAMinimumRatio: Double = 4.5

    public let roleName: String
    public let appearance: AppearanceMode
    public let foregroundLuminance: Double
    public let backgroundLuminance: Double
    public let contrastRatio: Double
    public let minimumRequiredRatio: Double

    public var passesWCAGAA: Bool {
        contrastRatio >= minimumRequiredRatio
    }

    public init(
        roleName: String,
        appearance: AppearanceMode,
        foregroundLuminance: Double,
        backgroundLuminance: Double,
        minimumRequiredRatio: Double = Self.wcagAAMinimumRatio
    ) {
        self.roleName = roleName
        self.appearance = appearance
        let fg = min(max(foregroundLuminance, 0.0), 1.0)
        let bg = min(max(backgroundLuminance, 0.0), 1.0)
        self.foregroundLuminance = fg
        self.backgroundLuminance = bg
        self.contrastRatio = Self.computeContrastRatio(luminanceA: fg, luminanceB: bg)
        self.minimumRequiredRatio = minimumRequiredRatio
    }

    public static func computeContrastRatio(luminanceA: Double, luminanceB: Double) -> Double {
        let lighter = max(luminanceA, luminanceB)
        let darker = min(luminanceA, luminanceB)
        return (lighter + 0.05) / (darker + 0.05)
    }
}

/// Dynamic Type scaling and touch-target audit for core action buttons.
public struct DynamicTypeButtonAudit: Equatable, Sendable {
    public static let minimumTouchTargetPoints: Double = 44.0

    public let identifier: String
    public let allowsMultilineWrap: Bool
    public let truncatesAtAccessibilitySizes: Bool
    public let minTouchTargetPoints: Double

    public var passes: Bool {
        !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && allowsMultilineWrap
            && !truncatesAtAccessibilitySizes
            && minTouchTargetPoints >= Self.minimumTouchTargetPoints
    }

    public init(
        identifier: String,
        allowsMultilineWrap: Bool,
        truncatesAtAccessibilitySizes: Bool,
        minTouchTargetPoints: Double
    ) {
        self.identifier = identifier
        self.allowsMultilineWrap = allowsMultilineWrap
        self.truncatesAtAccessibilitySizes = truncatesAtAccessibilitySizes
        self.minTouchTargetPoints = minTouchTargetPoints
    }
}

/// Aggregate accessibility audit report across VoiceOver, Reduce Motion, WCAG 4.5:1 contrast, and Dynamic Type.
public struct AccessibilityAuditReport: Equatable, Sendable {
    public let isReadyForRelease: Bool
    public let missingVoiceOverIdentifiers: [String]
    public let invalidVoiceOverElements: [String]
    public let failingContrastRoles: [String]
    public let failingDynamicTypeButtons: [String]
    public let reduceMotionCompliant: Bool

    public init(
        isReadyForRelease: Bool,
        missingVoiceOverIdentifiers: [String],
        invalidVoiceOverElements: [String],
        failingContrastRoles: [String],
        failingDynamicTypeButtons: [String],
        reduceMotionCompliant: Bool
    ) {
        self.isReadyForRelease = isReadyForRelease
        self.missingVoiceOverIdentifiers = missingVoiceOverIdentifiers
        self.invalidVoiceOverElements = invalidVoiceOverElements
        self.failingContrastRoles = failingContrastRoles
        self.failingDynamicTypeButtons = failingDynamicTypeButtons
        self.reduceMotionCompliant = reduceMotionCompliant
    }
}

/// App Store & I10 accessibility evaluator for VoiceOver, Reduce Motion, WCAG 4.5:1 contrast, and Dynamic Type.
public enum AccessibilityVoiceOverAndDynamicTypeAudit {
    public static let requiredIdentifiersBySurface: [AccessibilityAuditSurface: Set<String>] = [
        .primaryTabs: [
            "tab.explore",
            "tab.roam",
            "tab.play",
            "tab.account"
        ],
        .playRouteMapView: [
            "playRoute.mapCanvas",
            "playRoute.activeMarker",
            "playRoute.cameraFocusButton"
        ],
        .reformPlanV9Sections: [
            "merchantAICommerce.root",
            "merchantInStoreGame.statusHeadline",
            "commerceOrderLifecycle.orderHeader"
        ]
    ]

    public static var allRequiredVoiceOverIdentifiers: Set<String> {
        requiredIdentifiersBySurface.values.reduce(into: Set<String>()) { $0.formUnion($1) }
    }

    public static func evaluateReduceMotion(
        isReduceMotionEnabled: Bool,
        proposedDurationSeconds: Double = 0.35
    ) -> ReduceMotionTransitionDecision {
        ReduceMotionTransitionDecision(
            isReduceMotionEnabled: isReduceMotionEnabled,
            proposedDurationSeconds: proposedDurationSeconds
        )
    }

    public static func evaluate(
        voiceOverElements: [VoiceOverElementSpec],
        contrastPairs: [ContrastPairAudit],
        dynamicTypeButtons: [DynamicTypeButtonAudit],
        reduceMotionDecision: ReduceMotionTransitionDecision
    ) -> AccessibilityAuditReport {
        let providedIDs = Set(voiceOverElements.map(\.identifier))
        let missingIDs = allRequiredVoiceOverIdentifiers.subtracting(providedIDs).sorted()
        let invalidElements = voiceOverElements.filter { !$0.isValid }.map(\.identifier).sorted()
        let failingContrasts = contrastPairs
            .filter { !$0.passesWCAGAA }
            .map { "\($0.roleName).\($0.appearance.rawValue)" }
            .sorted()
        let failingButtons = dynamicTypeButtons
            .filter { !$0.passes }
            .map(\.identifier)
            .sorted()

        let motionOK = !reduceMotionDecision.isReduceMotionEnabled
            || (!reduceMotionDecision.usesAnimatedTransition
                && reduceMotionDecision.durationSeconds == 0.0
                && reduceMotionDecision.cameraTransitionStyle == .instantJump)

        let ready = missingIDs.isEmpty
            && invalidElements.isEmpty
            && !contrastPairs.isEmpty
            && failingContrasts.isEmpty
            && !dynamicTypeButtons.isEmpty
            && failingButtons.isEmpty
            && motionOK

        return AccessibilityAuditReport(
            isReadyForRelease: ready,
            missingVoiceOverIdentifiers: missingIDs,
            invalidVoiceOverElements: invalidElements,
            failingContrastRoles: failingContrasts,
            failingDynamicTypeButtons: failingButtons,
            reduceMotionCompliant: motionOK
        )
    }
}
