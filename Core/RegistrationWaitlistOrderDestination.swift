import Foundation

/// A server-bound destination, never an order-creation or payment authorization.
public struct RegistrationWaitlistOrderDestination: Hashable, Identifiable {
    public let identity: ProfileReadIdentity
    public let scope: RegistrationWaitlistScope
    public let registrationID: Int
    public var id: Self { self }

    public init?(status: RegistrationWaitlistStatus, scope: RegistrationWaitlistScope, identity: ProfileReadIdentity) {
        guard [.claimed, .converted].contains(status.state),
              status.matches(scope, accountID: identity.accountID),
              let registrationID = status.registrationID, registrationID > 0 else { return nil }
        self.identity = identity; self.scope = scope; self.registrationID = registrationID
    }
}

/// Captured once at the user's tap, including the independent read lease revision.
/// Reconstructing the sheet can never bind an old destination to a replacement grant.
public struct RegistrationWaitlistOrderPresentation: Hashable, Identifiable {
    public let destination: RegistrationWaitlistOrderDestination
    public let readIdentity: ProfileReadIdentity
    public var id: Self { self }
    public init?(destination: RegistrationWaitlistOrderDestination, readIdentity: ProfileReadIdentity?) {
        guard let readIdentity, readIdentity.accountID == destination.identity.accountID,
              readIdentity.epoch == destination.identity.epoch else { return nil }
        self.destination = destination; self.readIdentity = readIdentity
    }
}

@MainActor public extension RegistrationUIFlow {
    /// Read-only navigation does not clear retained/unknown creation or payment state.
    var waitlistOrderDestination: RegistrationWaitlistOrderDestination? {
        guard hasCurrentSession, !isReadingWaitlist, !isMutatingWaitlist, !waitlistOutcomeUnknown,
              let identity, let selectedTicketID, let waitlistStatus,
              let scope = try? RegistrationWaitlistScope(activityID: activity.summary.id, ticketID: selectedTicketID) else { return nil }
        return .init(status: waitlistStatus, scope: scope, identity: identity)
    }
}

/// Restricts the existing detail screen to one immutable owned activity order. A new
/// login (even the same account) cannot reuse the old route. Other reads fail closed.
@MainActor public final class RegistrationWaitlistOrderReader: ProfileReading {
    public let destination: RegistrationWaitlistOrderDestination
    private let base: any ProfileReading
    private let readIdentity: ProfileReadIdentity?
    private let isCurrent: () -> Bool
    public init(presentation: RegistrationWaitlistOrderPresentation, base: any ProfileReading, isCurrent: @escaping () -> Bool) {
        self.destination = presentation.destination; self.base = base
        self.readIdentity = presentation.readIdentity; self.isCurrent = isCurrent
    }
    public var identity: ProfileReadIdentity? {
        guard isCurrent(), let readIdentity, base.identity == readIdentity,
              readIdentity.accountID == destination.identity.accountID,
              readIdentity.epoch == destination.identity.epoch else { return nil }
        return readIdentity
    }
    public var isConfigured: Bool { identity != nil && base.isConfigured }
    public func profileOrder(id: Int) async throws -> ProfileOrder {
        try Task.checkCancellation()
        guard identity != nil else { throw APIError.unauthorized }
        guard isConfigured else { throw APIError.notConfigured }
        guard id == destination.registrationID else { throw APIError.invalidRequest }
        do {
            let order = try await base.profileOrder(id: id)
            try Task.checkCancellation()
            guard identity != nil else { throw CancellationError() }
            guard order.id == destination.registrationID,
                  order.memberID == destination.identity.accountID,
                  order.ownerType == 2, order.ownerID == destination.scope.activityID,
                  order.ticketID == destination.scope.ticketID else { throw APIError.malformedResponse }
            return order
        } catch {
            guard !Task.isCancelled, identity != nil else { throw CancellationError() }
            throw error
        }
    }
    public func profileOrders() async throws -> [ProfileOrder] { throw APIError.invalidRequest }
    public func profileParticipants() async throws -> [ProfileParticipant] { throw APIError.invalidRequest }
    public func profileParticipant(id: Int) async throws -> ProfileParticipant { throw APIError.invalidRequest }
    public func profileBadges() async throws -> ProfileBadgeWall { throw APIError.invalidRequest }
}
