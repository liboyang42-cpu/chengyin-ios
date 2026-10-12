import Foundation

public struct ClubTopicMerchantRow: Equatable, Identifiable {
    /// A station/node identity, not a merchant or member identity.
    public let id: Int
    public let merchantName: String?
    public let stationName: String?
    public let state: String?
    public var initial: String? { merchantName.map { String($0.prefix(1)) } }
}

/// P056 buildMerchantRows: exclude open recruitment slots and keep station order.
/// The existing read strips raw contact fields. Absence is not proof of acceptance.
public struct ClubTopicMerchantList: Equatable {
    public let scope: ClubGovernanceScope
    public let rows: [ClubTopicMerchantRow]
    public init(snapshot: ClubGovernanceSnapshot, context: ClubGovernanceReadContext) throws {
        try context.scope.validate()
        guard context.operation == .recruit, context.accepts(snapshot),
              (context.identity?.accountID ?? 0) > 0,
              let clubID = context.scope.clubID, clubID > 0,
              let topicID = context.scope.topicID, topicID > 0 else { throw ClubGovernanceFailure.targetChanged }
        guard snapshot.permissions?.allows(ClubGovernanceRead.recruit.permission, scope: context.scope) == true else { throw ClubGovernanceFailure.forbidden }
        let value = try ClubGovernanceValidation.validate(snapshot.value, operation: .recruit, scope: context.scope)
        try Self.checkScope(value, clubID: clubID, topicID: topicID)
        guard let nodes = value["nodes"].array else { throw ClubGovernanceFailure.malformed }
        var rows: [ClubTopicMerchantRow] = [], seen = Set<Int>()
        for node in nodes {
            try Self.checkScope(node, clubID: clubID, topicID: topicID)
            // Exact case-sensitive source condition. Unknown states remain visible.
            guard node["state"] != .string("OPEN") else { continue }
            guard let id = node["nodeId"].int, (1...9_007_199_254_740_991).contains(id), seen.insert(id).inserted else { throw ClubGovernanceFailure.malformed }
            rows.append(.init(id: id, merchantName: Self.text(node["merchantName"]), stationName: Self.text(node["name"]), state: Self.text(node["state"])))
        }
        scope = context.scope; self.rows = rows
    }
    private static func checkScope(_ value: ClubGovernanceValue, clubID: Int, topicID: Int) throws {
        guard (value["clubId"] == .null || value["clubId"].int == clubID),
              (value["topicId"] == .null || value["topicId"].int == topicID) else { throw ClubGovernanceFailure.targetChanged }
    }
    private static func text(_ value: ClubGovernanceValue) -> String? {
        guard let text = value.string else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
