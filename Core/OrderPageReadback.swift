import Foundation

/// Read-back rule for an order page that already holds an order id.
/// The page performs the single lookup. This type does not look up again,
/// invent an id, or open a different ORDER id.
public enum OrderPageReadback {
    /// First ORDER target. A later id is not promoted.
    public static func firstOrderID(_ events: [OriginalAuditEvent]) -> Int64? {
        for event in events {
            guard event.targetType == "ORDER" else { continue }
            return event.targetId
        }
        return nil
    }

    /// The requested id when it is the first ORDER id. Any other id stays closed.
    public static func openedID(requested: Int64, events: [OriginalAuditEvent]) -> Int64? {
        guard requested > 0, firstOrderID(events) == requested else { return nil }
        return requested
    }
}
