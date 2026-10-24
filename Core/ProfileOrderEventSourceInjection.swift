import Foundation

/// Passes a signed-in user's already loaded original order events into the existing lookup.
/// The caller supplies the rows. This type does not invent events, does not read a session,
/// and does not call an admin audit log. A nil source stays quiet.
public struct ProfileOrderEventSourceInjection {
    public private(set) var events: [OriginalAuditEvent]?
    public private(set) var lookups = 0
    public let sends = 0

    public init(events: [OriginalAuditEvent]?) {
        self.events = events
    }

    /// Nil when no original-event read was passed. The page keeps its quiet path.
    public func entry() -> SupportLookupEntry? {
        guard let events else { return nil }
        return SupportLookupEntry(locator: SupportEventLocator(originalEvents: PassedOriginalOrderEvents(rows: events)))
    }

    /// Page call. Nil events do not look up. The request's first ORDER id must equal
    /// the opened order. A different id is original-missing.
    public mutating func lookupOpenedOrder(
        _ openedID: Int,
        currentProjection: SupportCurrentProjection? = nil,
        withdrawal: WithdrawalSupportSnapshot? = nil,
        orderRead: OwnedOrderReadRoute? = nil
    ) throws -> Int64? {
        guard events != nil else { return nil }
        lookups += 1
        guard var lookup = entry() else { return nil }
        let requested = Int64(openedID)
        let composition = try lookup.lookupByOrderId(
            openedID > 0 ? requested : nil,
            currentProjection: currentProjection,
            withdrawal: withdrawal,
            orderRead: orderRead ?? (openedID > 0 ? .detail(openedID) : nil))
        guard let composition else { return nil }
        guard composition.located.orderId == requested,
              Self.firstOrderID(composition.located.originalEvents) == requested else {
            throw SupportLocateFailure.originalMissing(requestId: "ORDER:\(requested)")
        }
        return requested
    }

    /// Same passed rows. A nil source stays quiet and does not occupy a new id.
    public func recoverOriginal(
        requestID: String?,
        currentProjection: SupportCurrentProjection?
    ) throws -> LocatedEvent? {
        guard let events else { return nil }
        return try SupportEventLocator(originalEvents: PassedOriginalOrderEvents(rows: events))
            .recoverOriginal(originalRequestID: requestID, currentProjection: currentProjection)
    }

    private static func firstOrderID(_ events: [OriginalAuditEvent]) -> Int64? {
        for event in events {
            guard event.targetType == "ORDER" else { continue }
            return event.targetId
        }
        return nil
    }
}

/// Index of caller-supplied rows for the existing locator. Not a second audit store.
struct PassedOriginalOrderEvents: SupportEventLocator.OriginalEventSource {
    private let byRequest: [String: [OriginalAuditEvent]]
    private let byTarget: [String: OriginalAuditEvent]

    init(rows: [OriginalAuditEvent]) {
        var requests: [String: [OriginalAuditEvent]] = [:]
        var targets: [String: OriginalAuditEvent] = [:]
        for event in rows {
            guard let id = event.requestId else { continue }
            requests[id, default: []].append(event)
            if let type = event.targetType, let targetId = event.targetId {
                targets["\(type):\(targetId)"] = event
            }
        }
        byRequest = requests
        byTarget = targets
    }

    func findByRequestId(_ requestId: String) -> [OriginalAuditEvent] {
        byRequest[requestId] ?? []
    }

    func findByTarget(targetType: String, targetId: Int64) -> OriginalAuditEvent? {
        byTarget["\(targetType):\(targetId)"]
    }
}
