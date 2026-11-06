import Foundation
import os

/// Instruments Points of Interest for before/after device measurement (I10).
/// Names are static. No account, route, coordinate, URL, media or content value
/// is ever attached, so a shared trace cannot leak business or personal data.
public enum NativePerformancePoint: String, CaseIterable, Sendable {
    case walkingRefreshTick = "walking.refreshTick"
    case walkingCameraFit = "walking.cameraFit"
    case playRouteMapProjection = "playRoute.mapProjection"
    case playRouteCameraFocus = "playRoute.cameraFocus"
    case artworkLoad = "image.artworkLoad"
    case audioStartToPlaying = "audio.startToPlaying"

    public enum Area: String, CaseIterable, Sendable { case map, longList, image, audio }

    public var area: Area {
        switch self {
        case .walkingRefreshTick, .walkingCameraFit, .playRouteCameraFocus: return .map
        case .playRouteMapProjection: return .longList
        case .artworkLoad: return .image
        case .audioStartToPlaying: return .audio
        }
    }

    /// OSSignposter requires a literal name. Each literal equals `rawValue`.
    var signpostName: StaticString {
        switch self {
        case .walkingRefreshTick: return "walking.refreshTick"
        case .walkingCameraFit: return "walking.cameraFit"
        case .playRouteMapProjection: return "playRoute.mapProjection"
        case .playRouteCameraFocus: return "playRoute.cameraFocus"
        case .artworkLoad: return "image.artworkLoad"
        case .audioStartToPlaying: return "audio.startToPlaying"
        }
    }
}

/// One open interval. Ending it twice is a no-op, so lifecycle exits
/// (stop, failure, disappear) may all end the same interval safely.
public final class NativePerformanceInterval {
    public let point: NativePerformancePoint
    private let signposter: OSSignposter
    private var state: OSSignpostIntervalState?
    fileprivate init(point: NativePerformancePoint, signposter: OSSignposter) {
        self.point = point; self.signposter = signposter
        state = signposter.beginInterval(point.signpostName, id: signposter.makeSignpostID())
    }
    public var isOpen: Bool { state != nil }
    public func end() {
        guard let state else { return }
        self.state = nil
        signposter.endInterval(point.signpostName, state)
    }
}

public struct NativePerformanceSignposts {
    public static let subsystem = "Questify.Performance"
    public static let shared = NativePerformanceSignposts()
    private let signposter: OSSignposter
    public init(enabled: Bool = true) {
        signposter = enabled ? OSSignposter(subsystem: Self.subsystem, category: .pointsOfInterest) : .disabled
    }
    public func begin(_ point: NativePerformancePoint) -> NativePerformanceInterval {
        NativePerformanceInterval(point: point, signposter: signposter)
    }
    public func measure<T>(_ point: NativePerformancePoint, _ body: () throws -> T) rethrows -> T {
        let interval = begin(point)
        defer { interval.end() }
        return try body()
    }
}
