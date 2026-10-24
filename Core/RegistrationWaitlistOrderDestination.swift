import Foundation

/// Recovery reads a known durable registration before offering navigation. The pending
/// journal is not a create receipt and supplies no request ID or payment conclusion.
public struct RegistrationRecoveredOrderDestination: Hashable {
    public let identity: ProfileReadIdentity
    public let visitID: UUID
    public let activityID: Int
    public let ticketID: Int
    public let registrationID: Int
    @MainActor fileprivate init?(flow: RegistrationUIFlow) {
        guard flow.hasCurrentSession, !flow.hasRetainedIntent, !flow.isReadingStatus,
              let identity = flow.identity, let ticketID = flow.selectedTicketID, ticketID > 0,
              case .pending(let knownID) = flow.durableCreation, let knownID, knownID > 0,
              let snapshot = flow.durableStatus, snapshot.registrationID == knownID else { return nil }
        self.identity = identity; visitID = flow.resultOrderVisitID
        activityID = flow.activity.summary.id; self.ticketID = ticketID; registrationID = knownID
    }
}
@MainActor public extension RegistrationUIFlow {
    var recoveredOrderDestination: RegistrationRecoveredOrderDestination? { .init(flow: self) }
}
public struct RegistrationRecoveredOrderPresentation: Hashable, Identifiable {
    public let id = UUID()
    public let destination: RegistrationRecoveredOrderDestination
    public let readIdentity: ProfileReadIdentity
    public init?(destination: RegistrationRecoveredOrderDestination, readIdentity: ProfileReadIdentity?) {
        guard let readIdentity, readIdentity.accountID == destination.identity.accountID,
              readIdentity.epoch == destination.identity.epoch else { return nil }
        self.destination = destination; self.readIdentity = readIdentity
    }
}
@MainActor public final class RegistrationRecoveredOrderReader: ProfileReading {
    public let presentation: RegistrationRecoveredOrderPresentation
    private let base: any ProfileReading
    private let isCurrent: () -> Bool
    public init(presentation: RegistrationRecoveredOrderPresentation, base: any ProfileReading, isCurrent: @escaping () -> Bool) {
        self.presentation = presentation; self.base = base; self.isCurrent = isCurrent
    }
    public var identity: ProfileReadIdentity? {
        isCurrent() && base.identity == presentation.readIdentity ? presentation.readIdentity : nil
    }
    public var isConfigured: Bool { identity != nil && base.isConfigured }
    public func profileOrder(id: Int) async throws -> ProfileOrder {
        try Task.checkCancellation()
        guard identity != nil else { throw APIError.unauthorized }
        guard isConfigured else { throw APIError.notConfigured }
        let target = presentation.destination
        guard id == target.registrationID else { throw APIError.invalidRequest }
        do {
            let row = try await base.profileOrder(id: id)
            try Task.checkCancellation()
            guard identity != nil, base.isConfigured else { throw CancellationError() }
            guard row.id == target.registrationID, row.memberID == target.identity.accountID,
                  row.ownerType == 2, row.ownerID == target.activityID,
                  row.ticketID == target.ticketID else { throw APIError.malformedResponse }
            return row
        } catch {
            guard !Task.isCancelled, identity != nil, base.isConfigured else { throw CancellationError() }
            throw error
        }
    }
    public func profileOrders() async throws -> [ProfileOrder] { throw APIError.invalidRequest }
    public func profileParticipants() async throws -> [ProfileParticipant] { throw APIError.invalidRequest }
    public func profileParticipant(id: Int) async throws -> ProfileParticipant { throw APIError.invalidRequest }
    public func profileBadges() async throws -> ProfileBadgeWall { throw APIError.invalidRequest }
}

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

/// Known create receipt only. This is distinct from a waitlist claim and grants no
/// writes or payment authority. Request identity is local correlation, not a new wire field.
public struct RegistrationResultOrderDestination: Hashable, Identifiable {
    public let identity: ProfileReadIdentity
    public let visitID: UUID
    public let requestID: String
    public let activityID: Int
    public let ticketID: Int
    public let registrationID: Int
    public var id: Self { self }
    @MainActor fileprivate init?(flow: RegistrationUIFlow) {
        guard flow.hasCurrentSession, !flow.isSubmitting, let identity = flow.identity,
              let intent = flow.coordinator.retainedIntent,
              intent.selection.ownerID == flow.activity.summary.id,
              let ticketID = intent.selection.ticketID, ticketID > 0,
              case .responseReceived(let requestID, let result) = flow.creationState,
              requestID == intent.requestID, !requestID.isEmpty, result.registrationID > 0 else { return nil }
        self.identity = identity; visitID = flow.resultOrderVisitID; self.requestID = requestID
        activityID = intent.selection.ownerID; self.ticketID = ticketID; registrationID = result.registrationID
    }
}

@MainActor public extension RegistrationUIFlow {
    var resultOrderDestination: RegistrationResultOrderDestination? { .init(flow: self) }
}

public struct RegistrationResultOrderPresentation: Hashable, Identifiable {
    public let id = UUID()
    public let destination: RegistrationResultOrderDestination
    public let readIdentity: ProfileReadIdentity
    public init?(destination: RegistrationResultOrderDestination, readIdentity: ProfileReadIdentity?) {
        guard let readIdentity, readIdentity.accountID == destination.identity.accountID,
              readIdentity.epoch == destination.identity.epoch else { return nil }
        self.destination = destination; self.readIdentity = readIdentity
    }
}

/// Only the independent owned-order reader may supply this exact receipt's detail.
/// No cast to AppSession, mutation service or adjacent read capability is exposed.
@MainActor public final class RegistrationResultOrderReader: ProfileReading {
    public let presentation: RegistrationResultOrderPresentation
    private let base: any ProfileReading
    private let isCurrent: () -> Bool
    public init(presentation: RegistrationResultOrderPresentation, base: any ProfileReading, isCurrent: @escaping () -> Bool) {
        self.presentation = presentation; self.base = base; self.isCurrent = isCurrent
    }
    public var identity: ProfileReadIdentity? {
        guard isCurrent(), base.identity == presentation.readIdentity else { return nil }
        return presentation.readIdentity
    }
    public var isConfigured: Bool { identity != nil && base.isConfigured }
    public func profileOrder(id: Int) async throws -> ProfileOrder {
        try Task.checkCancellation()
        guard identity != nil else { throw APIError.unauthorized }
        guard isConfigured else { throw APIError.notConfigured }
        let destination = presentation.destination
        guard id == destination.registrationID else { throw APIError.invalidRequest }
        do {
            let order = try await base.profileOrder(id: id)
            try Task.checkCancellation()
            guard identity != nil, base.isConfigured else { throw CancellationError() }
            guard order.id == destination.registrationID, order.memberID == destination.identity.accountID,
                  order.ownerType == 2, order.ownerID == destination.activityID,
                  order.ticketID == destination.ticketID else { throw APIError.malformedResponse }
            return order
        } catch {
            guard !Task.isCancelled, identity != nil, base.isConfigured else { throw CancellationError() }
            throw error
        }
    }
    public func profileOrders() async throws -> [ProfileOrder] { throw APIError.invalidRequest }
    public func profileParticipants() async throws -> [ProfileParticipant] { throw APIError.invalidRequest }
    public func profileParticipant(id: Int) async throws -> ProfileParticipant { throw APIError.invalidRequest }
    public func profileBadges() async throws -> ProfileBadgeWall { throw APIError.invalidRequest }
}

