import Foundation

public struct RoamEnrolledChaptersOwner: Hashable {
    public let roamReaderID: ObjectIdentifier
    public let scopeKey: String?
    public let epoch: UInt64?
    public let ticketOwner: TicketWalletReadOwner
    @MainActor public init(roam: any RoamExperienceReading, tickets: any TicketWalletReading) {
        roamReaderID = ObjectIdentifier(roam); scopeKey = roam.identity?.scope.storageKey; epoch = roam.identity?.epoch
        ticketOwner = .init(reader: tickets)
    }
    public var canRead: Bool { scopeKey != nil && ticketOwner.canRead }
}
public enum RoamEnrolledChaptersFailure: Error { case route(TicketWalletIssue) }
public enum RoamEnrolledChaptersProjection {
    /// The existing wallet reads both lanes. Activity failure does not invalidate the successfully
    /// read route lane, while route failure must never become an empty list of enrolled topics.
    public static func topics(_ snapshot: TicketWalletSnapshot) throws -> [TicketWalletTicket] {
        if let partial = snapshot.partialFailure, partial.lane == .route { throw RoamEnrolledChaptersFailure.route(partial.issue) }
        guard Set(snapshot.tickets.map(\.id)).count == snapshot.tickets.count else { throw APIError.malformedResponse }
        var result: [TicketWalletTicket] = []
        for ticket in snapshot.tickets {
            guard ticket.id > 0, ticket.ownerType == 1 || ticket.ownerType == 2 else { throw APIError.malformedResponse }
            guard ticket.ownerType == 1 else { continue }
            guard let ownerID = ticket.ownerID, ownerID > 0, ticket.activityID == nil,
                  ticket.topicID == nil || ticket.topicID == ownerID else { throw APIError.malformedResponse }
            result.append(ticket)
        }
        return result
    }
}
public struct RoamEnrolledChaptersSnapshot {
    public let id = UUID()
    public let topics: [TicketWalletTicket]
}
public struct RoamEnrolledChapterTarget: Hashable {
    public let id = UUID()
    public let registrationID: Int
    public let owner: RoamEnrolledChaptersOwner
    public let snapshotID: UUID
}
/// The native registration detail remains the authority for current status and play scope.
/// This list never invokes play, payment, verification, team or order mutation operations.
@MainActor public final class RoamEnrolledChaptersModel {
    private let roam: any RoamExperienceReading
    private let tickets: any TicketWalletReading
    private var loadedOwner: RoamEnrolledChaptersOwner?
    private var stored: RoamEnrolledChaptersSnapshot?
    private var storedIssue: TicketWalletIssue?
    private var generation = UUID()
    private var visible = false
    public private(set) var isLoading = false
    public var onChange: (() -> Void)?
    public init(roam: any RoamExperienceReading, tickets: any TicketWalletReading) { self.roam = roam; self.tickets = tickets }
    public var owner: RoamEnrolledChaptersOwner { .init(roam: roam, tickets: tickets) }
    public var snapshot: RoamEnrolledChaptersSnapshot? { loadedOwner == owner ? stored : nil }
    public var issue: TicketWalletIssue? { loadedOwner == owner ? storedIssue : nil }
    public func appear() { visible = true }
    public func cancelPending() { visible = false; generation = UUID(); isLoading = false; onChange?() }
    public func invalidate() { cancelPending(); loadedOwner = nil; stored = nil; storedIssue = nil; onChange?() }
    public func load() async {
        guard visible, !Task.isCancelled else { return }
        generation = UUID(); let request = generation, captured = owner
        loadedOwner = captured; stored = nil; storedIssue = nil; isLoading = false
        guard captured.canRead else {
            storedIssue = captured.scopeKey == nil || !captured.ticketOwner.authenticated ? .login : .notConfigured
            onChange?(); return
        }
        isLoading = true; onChange?()
        defer { if generation == request { isLoading = false; onChange?() } }
        do {
            let value = try await tickets.ticketWallet()
            guard accepts(request, captured) else { return }
            stored = .init(topics: try RoamEnrolledChaptersProjection.topics(value))
        } catch {
            guard accepts(request, captured), !(error is CancellationError) else { return }
            if case RoamEnrolledChaptersFailure.route(let issue) = error { storedIssue = issue }
            else { storedIssue = .init(error) }
        }
    }
    public func select(registrationID: Int, snapshotID: UUID) -> RoamEnrolledChapterTarget? {
        guard visible, !isLoading, owner.canRead, let snapshot, snapshot.id == snapshotID,
              let row = snapshot.topics.first(where: { $0.id == registrationID }), row.action == .detail else { return nil }
        return .init(registrationID: registrationID, owner: owner, snapshotID: snapshot.id)
    }
    public func mayRemainOpen(_ target: RoamEnrolledChapterTarget) -> Bool {
        target.owner == owner && owner.canRead && target.snapshotID == snapshot?.id &&
            snapshot?.topics.contains(where: { $0.id == target.registrationID && $0.action == .detail }) == true
    }
    private func accepts(_ request: UUID, _ captured: RoamEnrolledChaptersOwner) -> Bool {
        !Task.isCancelled && visible && request == generation && captured == owner && loadedOwner == captured
    }
}
