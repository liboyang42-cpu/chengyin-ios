import Foundation

/// Session choice for a topic is derived only from the already-loaded
/// `TopicDetail.activities`. A ticket has no activity mapping in the current
/// contract, so a ticket identifier is never promoted to an activity identifier.
public enum TopicSessionSelectionResolution: Equatable {
    /// The topic response omitted `activityList`; this is not an empty shelf.
    case missingData
    /// The server explicitly returned an empty activity shelf.
    case empty
    /// Real activities exist, but the host did not inject an activity destination.
    case destinationUnavailable([TopicActivitySummary])
    case ready([TopicActivitySummary])

    public static func resolve(activities: [TopicActivitySummary]?, hasDestination: Bool) -> TopicSessionSelectionResolution {
        guard let activities else { return .missingData }
        guard !activities.isEmpty else { return .empty }
        return hasDestination ? .ready(activities) : .destinationUnavailable(activities)
    }

    public var activities: [TopicActivitySummary] {
        switch self {
        case .missingData, .empty: return []
        case .destinationUnavailable(let activities), .ready(let activities): return activities
        }
    }
}

/// Value-owned presentation state for one topic/session sheet.
///
/// The snapshot is captured when the sheet opens. A selection is accepted only
/// once, only while presented, and only for an identifier present in that
/// snapshot. Closing, backgrounding, or an account-scope change discards the
/// snapshot, so a stale response or an identifier from an earlier presentation
/// (including a ticket identifier that happens to be tapped later) cannot open
/// an activity.
public struct TopicSessionSelectionFlow: Equatable {
    public private(set) var isPresented = false
    public private(set) var presentation = 0
    public private(set) var selectedActivityID: Int?
    private var snapshotIDs: [Int] = []
    private var scope: UUID?

    public init() {}

    @discardableResult
    public mutating func open(scope: UUID, activityIDs: [Int]) -> Int {
        guard !isPresented else { return presentation }
        presentation += 1
        self.scope = scope
        snapshotIDs = activityIDs
        selectedActivityID = nil
        isPresented = true
        return presentation
    }

    /// Returns the accepted activity identifier, or nil for a duplicate tap,
    /// a missing destination, a closed/stale presentation, or an identifier
    /// outside the captured snapshot.
    @discardableResult
    public mutating func select(activityID: Int, hasDestination: Bool) -> Int? {
        guard isPresented, hasDestination, selectedActivityID == nil,
              snapshotIDs.contains(activityID) else { return nil }
        selectedActivityID = activityID
        return activityID
    }

    /// Returning from the pushed activity detail re-arms choice within the
    /// same presentation without reopening a previously selected activity.
    public mutating func returnedFromActivity() {
        guard isPresented else { return }
        selectedActivityID = nil
    }

    public mutating func close() {
        isPresented = false
        selectedActivityID = nil
        snapshotIDs = []
    }

    /// Backgrounding discards any pending selection; nothing is replayed on
    /// foregrounding.
    public mutating func backgrounded() { close() }

    /// An account/scope change invalidates the captured snapshot. Returns true
    /// when a presented sheet must be dismissed.
    @discardableResult
    public mutating func scopeChanged(to newScope: UUID) -> Bool {
        guard scope != newScope else { return false }
        let wasPresented = isPresented
        close()
        scope = newScope
        return wasPresented
    }
}
