import Foundation

/// Support lookup beside the existing withdrawal-support read and order read.
/// Not a support desk. Does not replace WithdrawalSupportLandingView.
/// Wraps SupportEventLocator. Does not create a second audit store and does not invent events.
/// Appearance does not send.
public struct SupportLookupEntry {
    public struct Composition: Equatable {
        public var located: LocatedEvent
        public var withdrawal: WithdrawalSupportSnapshot?
        public var orderRead: OwnedOrderReadRoute?
    }

    private let locator: SupportEventLocator
    public private(set) var appeared = false
    public private(set) var lookups = 0
    public let sends = 0

    public init(locator: SupportEventLocator) {
        self.locator = locator
    }

    /// Appearance does not send, look up, or invent events.
    public mutating func appear() {
        appeared = true
    }

    public mutating func lookupByRunId(
        _ runId: Int64?,
        currentProjection: SupportCurrentProjection?,
        withdrawal: WithdrawalSupportSnapshot?,
        orderRead: OwnedOrderReadRoute?
    ) throws -> Composition? {
        lookups += 1
        guard let located = try locator.locateByRunId(runId, currentProjection: currentProjection) else {
            return nil
        }
        guard let runId else { return nil }
        try accept(located, requested: runId, kind: "RUN")
        return compose(located, withdrawal: withdrawal, orderRead: orderRead)
    }

    public mutating func lookupByOrderId(
        _ orderId: Int64?,
        currentProjection: SupportCurrentProjection?,
        withdrawal: WithdrawalSupportSnapshot?,
        orderRead: OwnedOrderReadRoute?
    ) throws -> Composition? {
        lookups += 1
        guard let located = try locator.locateByOrderId(orderId, currentProjection: currentProjection) else {
            return nil
        }
        guard let orderId else { return nil }
        try accept(located, requested: orderId, kind: "ORDER")
        return compose(located, withdrawal: withdrawal, orderRead: orderRead)
    }

    private func accept(_ located: LocatedEvent, requested: Int64, kind: String) throws {
        let head = Self.firstRunOrOrderID(located.originalEvents)
        guard let head, head.type == kind, head.id == requested else {
            throw SupportLocateFailure.originalMissing(requestId: "\(kind):\(requested)")
        }
    }

    private func compose(
        _ located: LocatedEvent,
        withdrawal: WithdrawalSupportSnapshot?,
        orderRead: OwnedOrderReadRoute?
    ) -> Composition {
        Composition(
            located: located,
            withdrawal: withdrawal,
            orderRead: acceptedOrder(located, orderRead: orderRead))
    }

    /// A detail route is kept only when it already names the located order.
    /// A list, a different id, or a missing order is not rewritten into this lookup.
    private func acceptedOrder(
        _ located: LocatedEvent,
        orderRead: OwnedOrderReadRoute?
    ) -> OwnedOrderReadRoute? {
        guard let orderRead, let orderId = located.orderId, orderId > 0 else { return nil }
        guard case .detail(let id) = orderRead, id > 0, Int64(id) == orderId else { return nil }
        return orderRead
    }

    /// The request's first RUN or ORDER id. A later id is not promoted.
    private static func firstRunOrOrderID(_ events: [OriginalAuditEvent]) -> (type: String, id: Int64)? {
        for event in events {
            guard let type = event.targetType, type == "RUN" || type == "ORDER" else { continue }
            guard let id = event.targetId else { return nil }
            return (type, id)
        }
        return nil
    }
}
