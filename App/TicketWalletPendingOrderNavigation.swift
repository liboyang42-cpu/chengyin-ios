import SwiftUI

private struct TicketWalletPendingOrderProviderKey: EnvironmentKey {
    static let defaultValue: TicketWalletPendingOrderProvider? = nil
}
extension EnvironmentValues {
    var ticketWalletPendingOrderProvider: TicketWalletPendingOrderProvider? {
        get { self[TicketWalletPendingOrderProviderKey.self] }
        set { self[TicketWalletPendingOrderProviderKey.self] = newValue }
    }
}

struct TicketWalletPendingOrderOwner: Hashable {
    let wallet: TicketWalletReadOwner
    let coordinatorID: ObjectIdentifier
    let orderScope: UUID
    let accountID: Int?
    let revision: UInt64
    @MainActor init(reader: any TicketWalletReading, coordinator: OrderLifecycleCoordinator, revision: UInt64) {
        wallet = TicketWalletReadOwner(reader: reader)
        coordinatorID = ObjectIdentifier(coordinator)
        orderScope = coordinator.scope; accountID = coordinator.accountID; self.revision = revision
    }
}

/// A navigation seam, never a payment grant. Account supplies its existing retained coordinator.
/// Constructing this provider or a target performs no reads, reviews, or writes.
struct TicketWalletPendingOrderProvider {
    let owner: TicketWalletPendingOrderOwner
    let coordinator: OrderLifecycleCoordinator
    private let currentRevision: @MainActor () -> UInt64
    @MainActor init(reader: any TicketWalletReading, coordinator: OrderLifecycleCoordinator,
                    revision: UInt64, currentRevision: @escaping @MainActor () -> UInt64) {
        owner = TicketWalletPendingOrderOwner(reader: reader, coordinator: coordinator, revision: revision)
        self.coordinator = coordinator; self.currentRevision = currentRevision
    }
    @MainActor func matches(reader: any TicketWalletReading) -> Bool {
        owner.wallet.canRead && (owner.accountID.map { $0 > 0 } ?? false)
            && owner == TicketWalletPendingOrderOwner(reader: reader, coordinator: coordinator, revision: currentRevision())
    }
    @MainActor func destination(target: TicketWalletPendingOrderEntry.Target, reader: any TicketWalletReading) -> OrderLifecycleView? {
        guard target.owner == owner, target.ticket.id > 0, target.ticket.registrationStatus == 1,
              matches(reader: reader) else { return nil }
        // The existing view fetches this exact registration's authoritative order detail.
        // Its existing dispatch gates and retained replay locks remain authoritative.
        return OrderLifecycleView(id: target.ticket.id, coordinator: coordinator)
    }
}

@MainActor struct TicketWalletPendingOrderEntry {
    struct Target: Hashable {
        let id = UUID()
        let rowIndex: Int
        let ticket: TicketWalletTicket
        let owner: TicketWalletPendingOrderOwner
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }
    private var visible = false
    private(set) var presentationID = UUID()
    var target: Target?

    static func isPending(_ ticket: TicketWalletTicket) -> Bool {
        // Mini _openTicket uses registrationStatus, independently of verification display.
        ticket.id > 0 && ticket.registrationStatus == 1
    }
    mutating func appear() { visible = true; presentationID = UUID() }
    mutating func disappear() {
        // Pushing hides the wallet. Keep the destination until native Back, but retire old taps.
        visible = false; presentationID = UUID()
    }
    mutating func retire() { target = nil; presentationID = UUID() }
    func canOpen(ticket: TicketWalletTicket, reader: any TicketWalletReading, provider: TicketWalletPendingOrderProvider) -> Bool {
        visible && target == nil && Self.isPending(ticket) && provider.matches(reader: reader)
    }
    mutating func activate(ticket: TicketWalletTicket, rowIndex: Int, snapshot: TicketWalletSnapshot,
                           reader: any TicketWalletReading, provider: TicketWalletPendingOrderProvider,
                           presentationID: UUID) {
        guard self.presentationID == presentationID,
              canOpen(ticket: ticket, reader: reader, provider: provider),
              snapshot.tickets.indices.contains(rowIndex), snapshot.tickets[rowIndex] == ticket else { return }
        target = Target(rowIndex: rowIndex, ticket: ticket, owner: provider.owner)
    }
    func matches(_ target: Target, snapshot: TicketWalletSnapshot, reader: any TicketWalletReading,
                 provider: TicketWalletPendingOrderProvider) -> Bool {
        self.target == target && target.owner == provider.owner && provider.matches(reader: reader)
            && Self.isPending(target.ticket) && snapshot.tickets.indices.contains(target.rowIndex)
            && snapshot.tickets[target.rowIndex] == target.ticket
    }
}
