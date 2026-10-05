import Foundation

/// Binds a read and its navigation to the same viewer, authority revision and target.
public struct ClubGovernanceReadContext: Hashable {
    public let operation: ClubGovernanceRead
    public let scope: ClubGovernanceScope
    public let identity: ClubReadIdentity?
    public let viewerRevision: UInt64
    public let authorizationGeneration: UUID?
    public init(operation: ClubGovernanceRead, scope: ClubGovernanceScope, identity: ClubReadIdentity?, viewerRevision: UInt64, authorizationGeneration: UUID?) {
        self.operation = operation; self.scope = scope; self.identity = identity
        self.viewerRevision = viewerRevision; self.authorizationGeneration = authorizationGeneration
    }
    public func accepts(_ snapshot: ClubGovernanceSnapshot) -> Bool {
        snapshot.operation == operation && snapshot.scope == scope
    }
}

/// The mini customer-history route uses records[].topicId, never a record/member/activity ID.
/// This selection is ephemeral and grants no authority to the topic reader.
public struct ClubCustomerHistoryTopicRoute: Hashable, Identifiable {
    public let id = UUID()
    public let topicID: Int
    public let context: ClubGovernanceReadContext
    public let snapshotGeneration: UInt64
    private let recordKey: String

    public init?(record: ClubGovernanceValue, snapshot: ClubGovernanceSnapshot, context: ClubGovernanceReadContext, snapshotGeneration: UInt64) {
        guard Self.validSnapshot(snapshot, context: context),
              let key = record["key"].string, !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let topicID = Self.positiveID(record["topicId"]),
              Self.matchesRecordScope(record, scope: context.scope),
              let records = snapshot.value["records"].array,
              records.contains(record), records.filter({ $0["key"].string == key }).count == 1 else { return nil }
        self.topicID = topicID; self.recordKey = key; self.context = context; self.snapshotGeneration = snapshotGeneration
    }
    public func isCurrent(snapshot: ClubGovernanceSnapshot?, context: ClubGovernanceReadContext, snapshotGeneration: UInt64) -> Bool {
        guard self.context == context, self.snapshotGeneration == snapshotGeneration,
              let snapshot, Self.validSnapshot(snapshot, context: context),
              let records = snapshot.value["records"].array else { return false }
        let matches = records.filter { $0["key"].string == recordKey }
        return matches.count == 1 && Self.positiveID(matches[0]["topicId"]) == topicID && Self.matchesRecordScope(matches[0], scope: context.scope)
    }
    private static func validSnapshot(_ snapshot: ClubGovernanceSnapshot, context: ClubGovernanceReadContext) -> Bool {
        context.operation == .customer && context.accepts(snapshot) && (context.identity?.accountID ?? 0) > 0 &&
        (context.scope.clubID ?? 0) > 0 && (context.scope.memberID ?? 0) > 0 &&
        snapshot.value["summary"]["memberId"].int == context.scope.memberID &&
        snapshot.permissions?.allows(ClubGovernanceRead.customer.permission, scope: context.scope) == true
    }
    private static func matchesRecordScope(_ record: ClubGovernanceValue, scope: ClubGovernanceScope) -> Bool {
        // The current source omits these optional fields. Reject contradictory projections if present.
        (record["clubId"] == .null || positiveID(record["clubId"]) == scope.clubID) &&
        (record["memberId"] == .null || positiveID(record["memberId"]) == scope.memberID)
    }
    static func positiveID(_ value: ClubGovernanceValue) -> Int? {
        // Match the mini's positive safe-integer domain, without coercing booleans/objects.
        let maximum = 9_007_199_254_740_991
        let id: Int
        switch value {
        case .integer(let number): id = number
        case .string(let text):
            guard let number = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }; id = number
        case .decimal(let number):
            guard number.isFinite, number > 0, number <= Double(maximum), number.rounded(.towardZero) == number else { return nil }; id = Int(number)
        default: return nil
        }
        return (1...maximum).contains(id) ? id : nil
    }
}
