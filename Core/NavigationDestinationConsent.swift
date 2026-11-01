import Foundation

/// In-app navigation destination purpose is a different consent from location-share.
/// Granting one never implies the other. Destination identity is not a share payload.
public enum LocationPurposeConsent: String, Equatable, Sendable {
    case inAppNavigationDestination
    case locationShare
}

public enum NavigationConsentFailure: Error, Equatable {
    case navigationDestinationConsentRequired
    case locationShareConsentRequired
    case destinationIsNotSharePayload
    case purposeMismatch
}

public struct InAppNavigationDestination: Equatable, Sendable {
    public let reference: WalkingTargetReference
    public init(reference: WalkingTargetReference) {
        self.reference = reference
    }
}

public struct NavigationDestinationConsent: Equatable, Sendable {
    private var granted: Set<LocationPurposeConsent>
    public init() { granted = [] }
    public var allowsNavigationDestination: Bool { granted.contains(.inAppNavigationDestination) }
    public var allowsLocationShare: Bool { granted.contains(.locationShare) }
    public mutating func grant(_ purpose: LocationPurposeConsent) {
        granted.insert(purpose)
    }
    public mutating func revoke(_ purpose: LocationPurposeConsent) {
        granted.remove(purpose)
    }
    public func allows(_ purpose: LocationPurposeConsent) -> Bool { granted.contains(purpose) }
    /// Navigation purpose does not copy into location-share, and share does not copy into navigation.
    public func impliesOtherPurpose(_ purpose: LocationPurposeConsent) -> Bool {
        switch purpose {
        case .inAppNavigationDestination: return allowsLocationShare && !allowsNavigationDestination
        case .locationShare: return allowsNavigationDestination && !allowsLocationShare
        }
    }
    public func startInAppNavigation(_ destination: InAppNavigationDestination) throws {
        _ = destination
        guard allowsNavigationDestination else { throw NavigationConsentFailure.navigationDestinationConsentRequired }
    }
    public func publishLocationShare(_ destination: InAppNavigationDestination) throws {
        _ = destination
        guard allowsLocationShare else { throw NavigationConsentFailure.locationShareConsentRequired }
    }
    /// Destination identity cannot be treated as a location-share payload.
    public func sharePayload(from destination: InAppNavigationDestination) throws -> Never {
        _ = destination
        throw NavigationConsentFailure.destinationIsNotSharePayload
    }
    public static func split(_ navigation: NavigationDestinationConsent,
                             share: NavigationDestinationConsent) throws {
        guard navigation.allowsNavigationDestination, !navigation.allowsLocationShare else {
            throw NavigationConsentFailure.purposeMismatch
        }
        guard share.allowsLocationShare, !share.allowsNavigationDestination else {
            throw NavigationConsentFailure.purposeMismatch
        }
    }
}
