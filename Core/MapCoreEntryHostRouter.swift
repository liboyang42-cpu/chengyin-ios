import Foundation

/// Host navigation destination resolved from `MapCoreEntryHubView` selection (reform plan v9 §20, w2-21).
/// Existing entries route to reviewed native surfaces; pending W20/fog/side-quest/sharing entries remain blocked
/// with explicit reason copy and never trigger unreviewed network or location side effects.
public enum MapCoreEntryHostDestination: Equatable, Sendable {
    case searchMap
    case roam
    case walkingNavigation
    case blockedWithReason(String)

    public var isBlocked: Bool {
        if case .blockedWithReason = self { return true }
        return false
    }

    public var blockedReason: String? {
        if case let .blockedWithReason(reason) = self { return reason }
        return nil
    }
}

/// Pure Core router bridging `MapCoreEntry` selection from `MapCoreEntryHubView` to host navigation destinations.
public struct MapCoreEntryHostRouter: Equatable {
    public private(set) var lastSelectedEntry: MapCoreEntry?
    public private(set) var activeDestination: MapCoreEntryHostDestination?

    public init() {}

    /// Maps a `MapCoreEntry` to its host navigation destination while keeping pending entries disabled with explicit reason copy.
    public static func resolve(_ entry: MapCoreEntry) -> MapCoreEntryHostDestination {
        switch entry {
        case .placeInfo:
            return .searchMap
        case .freeExploration:
            return .roam
        case .cityOrienteering:
            return .walkingNavigation
        case .merchantSideQuests:
            return .blockedWithReason(
                "Not available yet: waiting for reviewed merchant side-quest spawn and accept backend services (W14)."
            )
        case .personalFog:
            return .blockedWithReason(
                "Not available yet: waiting for reviewed personal fog grid version and reveal sync backend service (W14.6 / §12.5)."
            )
        case .sharedLocation:
            return .blockedWithReason(
                "Not available yet: waiting for product privacy decision and reviewed location share grant service (W13.5–W13.7)."
            )
        case .cityOperation:
            return .blockedWithReason(
                "Not available yet: waiting for product decision and reviewed W20 CITY business game endpoints (w2-21 / §29–35)."
            )
        }
    }

    /// Returns whether the entry can open an active host screen today.
    public static func isEnabled(_ entry: MapCoreEntry) -> Bool {
        entry.availability == .existing && !resolve(entry).isBlocked
    }

    /// Explicit reason copy when an entry is blocked, or `nil` when the entry routes to an existing host screen.
    public static func blockedReason(for entry: MapCoreEntry) -> String? {
        resolve(entry).blockedReason
    }

    /// Records the selection from `MapCoreEntryHubView` and returns the resolved host destination.
    @discardableResult
    public mutating func select(_ entry: MapCoreEntry) -> MapCoreEntryHostDestination {
        let destination = Self.resolve(entry)
        lastSelectedEntry = entry
        activeDestination = destination
        return destination
    }

    /// Clears the current host destination selection.
    public mutating func reset() {
        lastSelectedEntry = nil
        activeDestination = nil
    }
}
