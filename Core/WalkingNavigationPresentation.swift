import Foundation

/// Read-only presentation rules for the existing foreground coordinator. These rules
/// cannot authorize a target, start a provider, or declare a business completion.
extension WalkingNavigationCoordinator.Phase {
    public var statusKey: String {
        switch self {
        case .ready: return "walking.ready"
        case .authorizing: return "walking.authorizing"
        case .locating: return "walking.locating"
        case .routing: return "walking.routing"
        case .navigating: return "walking.navigating"
        case .nearDestination: return "walking.nearDestination"
        case .paused: return "walking.paused"
        case .cancelled: return "walking.cancelled"
        case .failed(let failure): return "walking.error." + failure.rawValue
        }
    }
    public var isPreparing: Bool {
        switch self { case .authorizing, .locating, .routing: return true; default: return false }
    }
    public var mayStart: Bool {
        switch self {
        case .ready, .paused, .cancelled: return true
        case .failed(let failure): return failure != .staleContext
        default: return false
        }
    }
    public var mayPause: Bool {
        switch self {
        case .authorizing, .locating, .routing, .navigating, .nearDestination: return true
        case .failed(.weakGPS): return true
        default: return false
        }
    }
}
