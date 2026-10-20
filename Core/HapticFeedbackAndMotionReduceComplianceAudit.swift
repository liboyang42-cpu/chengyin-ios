import Foundation

public struct MotionAndHapticInteractionCheck: Sendable, Equatable, Identifiable {
    public let id: String
    public let interactionSurface: String
    public let respectsReduceMotionCrossfade: Bool
    public let minHapticIntervalMs: Int
    public let throttlesShadersInLowPowerMode: Bool

    public var isCompliant: Bool {
        respectsReduceMotionCrossfade &&
            minHapticIntervalMs >= 120 &&
            throttlesShadersInLowPowerMode
    }

    public init(
        id: String,
        interactionSurface: String,
        respectsReduceMotionCrossfade: Bool,
        minHapticIntervalMs: Int,
        throttlesShadersInLowPowerMode: Bool
    ) {
        self.id = id
        self.interactionSurface = interactionSurface
        self.respectsReduceMotionCrossfade = respectsReduceMotionCrossfade
        self.minHapticIntervalMs = minHapticIntervalMs
        self.throttlesShadersInLowPowerMode = throttlesShadersInLowPowerMode
    }
}

public struct HapticFeedbackAndMotionReduceComplianceAudit: Sendable, Equatable {
    public static let canonicalSurfaces: [MotionAndHapticInteractionCheck] = [
        MotionAndHapticInteractionCheck(
            id: "roam-stamp-unlock-celebration",
            interactionSurface: "roam-stamp-unlock-celebration",
            respectsReduceMotionCrossfade: true,
            minHapticIntervalMs: 180,
            throttlesShadersInLowPowerMode: true
        ),
        MotionAndHapticInteractionCheck(
            id: "map-fog-and-layer-transition",
            interactionSurface: "map-fog-and-layer-transition",
            respectsReduceMotionCrossfade: true,
            minHapticIntervalMs: 150,
            throttlesShadersInLowPowerMode: true
        ),
        MotionAndHapticInteractionCheck(
            id: "play-compass-and-proximity-pulse",
            interactionSurface: "play-compass-and-proximity-pulse",
            respectsReduceMotionCrossfade: true,
            minHapticIntervalMs: 200,
            throttlesShadersInLowPowerMode: true
        ),
        MotionAndHapticInteractionCheck(
            id: "story-walking-card-flip",
            interactionSurface: "story-walking-card-flip",
            respectsReduceMotionCrossfade: true,
            minHapticIntervalMs: 120,
            throttlesShadersInLowPowerMode: true
        )
    ]

    public init() {}

    public static func evaluate(
        surfaces: [MotionAndHapticInteractionCheck] = canonicalSurfaces
    ) -> (totalSurfaces: Int, compliantSurfaces: Int, isMotionHapticCompliant: Bool) {
        let totalSurfaces = surfaces.count
        let compliantSurfaces = surfaces.filter(\.isCompliant).count
        let isMotionHapticCompliant = totalSurfaces > 0 && compliantSurfaces == totalSurfaces
        return (
            totalSurfaces: totalSurfaces,
            compliantSurfaces: compliantSurfaces,
            isMotionHapticCompliant: isMotionHapticCompliant
        )
    }
}
