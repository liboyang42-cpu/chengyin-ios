import Foundation

/// Read-only evidence for an unknown create outcome. Owned-order rows carry no request ID,
/// so a match is never proof that this submission created it, and it never unlocks a retry.
public enum RegistrationUncertainOutcomeEvidence: Equatable {
    /// No unknown outcome, session or matching reader: nothing was read.
    case notApplicable
    /// The owned list currently has no order for this activity/ticket. It may lag the server.
    case noMatchingOrder
    /// Owned order IDs for the retained activity/ticket, newest (highest ID) first.
    case matchingOrders([Int])

    public static func match(orders: [ProfileOrder], intent: RegistrationCreateIntent, accountID: Int) -> Self {
        let ids = orders.filter { order in
            order.id > 0 && order.memberID == accountID && order.ownerType == intent.ownerType &&
                order.ownerID == intent.selection.ownerID &&
                (intent.selection.ticketID.map { order.ticketID == $0 } ?? true)
        }.map(\.id)
        let unique = Array(Set(ids)).sorted(by: >)
        return unique.isEmpty ? .noMatchingOrder : .matchingOrders(unique)
    }
}

/// Discover → detail → quote → registration → order-status slice helpers. These add no
/// write path: creation still requires the flow's explicit review and its creation policy
/// (disabled by default; only offline DEBUG fixtures or a scoped production grant permit it).
@MainActor public extension RegistrationUIFlow {
    /// Explicit confirmation, then exactly one authoritative status read for the ID returned
    /// by THIS confirmation's create response. No polling, payment, or replay is started.
    /// A blocked confirmation, unknown outcome, or earlier retained intent reads nothing.
    func confirmAndReadBack() async {
        let previousRequestID = coordinator.retainedIntent?.requestID
        await confirm()
        guard let intent = coordinator.retainedIntent, intent.requestID != previousRequestID,
              case .responseReceived(let requestID, _) = creationState, requestID == intent.requestID,
              canReadStatus, !Task.isCancelled else { return }
        await readKnownStatus()
    }

    /// Read-only reconciliation for an unknown create outcome without a registration ID:
    /// one read of the caller's owned orders, bound to the opened account and retained intent.
    /// The retained intent stays locked whatever this returns.
    func uncertainOutcomeEvidence(orders reader: any ProfileReading) async throws -> RegistrationUncertainOutcomeEvidence {
        guard hasCurrentSession, let identity, reader.identity == identity, reader.isConfigured,
              let intent = coordinator.retainedIntent,
              case .outcomeUnknown(let requestID, _) = creationState, requestID == intent.requestID else {
            return .notApplicable
        }
        let rows = try await reader.profileOrders()
        try Task.checkCancellation()
        guard hasCurrentSession, self.identity == identity, reader.identity == identity,
              coordinator.retainedIntent == intent,
              case .outcomeUnknown(let current, _) = creationState, current == requestID else {
            throw CancellationError()
        }
        return .match(orders: rows, intent: intent, accountID: identity.accountID)
    }
}
