import Foundation

/// P045 reports a concrete activity, never the topic ID or an inferred session.
public struct ClubActivityReportSource: Hashable, Identifiable {
    public let id = UUID()
    public let topicID: Int
    public let authorID: Int
    public let context: ClubGovernanceReadContext
    public let generation: UInt64
    public init?(topicID: Int, club: ClubRecord, snapshot: ClubGovernanceSnapshot,
                 context: ClubGovernanceReadContext, generation: UInt64) {
        guard context.operation == .topics, context.scope == .init(clubID: club.id),
              club.canSeeMembers, let viewer = context.identity?.accountID, viewer > 0,
              context.accepts(snapshot), snapshot.permissions?.allows(nil, scope: context.scope) == true,
              (try? ClubEventCalendarSnapshot(snapshot: snapshot, context: context)) != nil,
              let rows = snapshot.value.array, let row = rows.first(where: { $0["id"].int == topicID }),
              let author = ClubCustomerHistoryTopicRoute.positiveID(row["memberId"]), author != viewer else { return nil }
        self.topicID = topicID; authorID = author; self.context = context; self.generation = generation
    }
    public var scope: ClubGovernanceScope { .init(clubID: context.scope.clubID, topicID: topicID) }
    public func matches(club: ClubRecord, snapshot: ClubGovernanceSnapshot) -> Bool {
        guard let fresh = Self(topicID: topicID, club: club, snapshot: snapshot, context: context, generation: generation) else { return false }
        return fresh.authorID == authorID
    }
    public func activities(_ snapshot: ClubGovernanceSnapshot) throws -> [ClubActivityReportChoice] {
        guard snapshot.operation == .topicOverview, snapshot.scope == scope,
              snapshot.permissions?.allows(nil, scope: scope) == true else { throw ClubGovernanceFailure.targetChanged }
        let value = try ClubGovernanceValidation.validate(snapshot.value, operation: .topicOverview, scope: scope)
        guard value["memberId"] == .null || value["memberId"].int == authorID,
              value["clubId"] == .null || value["clubId"].int == scope.clubID else { throw ClubGovernanceFailure.targetChanged }
        if value["activityList"] == .null { return [] }
        guard let rows = value["activityList"].array else { throw ClubGovernanceFailure.malformed }
        var ids = Set<Int>(), result: [ClubActivityReportChoice] = []
        for row in rows {
            guard let id = ClubCustomerHistoryTopicRoute.positiveID(row["id"]), ids.insert(id).inserted,
                  row["topicId"] == .null || row["topicId"].int == topicID,
                  row["clubId"] == .null || row["clubId"].int == scope.clubID else { throw ClubGovernanceFailure.targetChanged }
            result.append(.init(id: id, name: Self.label(row["name"].string), startDate: Self.label(row["startDate"].string), startTime: Self.label(row["startTime"].string)))
        }
        return result
    }
    private static func label(_ text: String?) -> String? {
        let value = text?.split(whereSeparator: \.isWhitespace).joined(separator: " ") ?? ""
        return value.isEmpty ? nil : String(value.prefix(80))
    }
}
public struct ClubActivityReportChoice: Identifiable, Equatable {
    public let id: Int
    public let name: String?
    public let startDate: String?
    public let startTime: String?
}
public struct ClubActivityReportTarget: Identifiable, Equatable {
    public let id = UUID()
    public let source: ClubActivityReportSource
    public let choice: ClubActivityReportChoice
    public init?(source: ClubActivityReportSource, choice: ClubActivityReportChoice, choices: [ClubActivityReportChoice]) {
        guard choices.filter({ $0.id == choice.id }).count == 1, choices.contains(choice) else { return nil }
        self.source = source; self.choice = choice
    }
    public var scope: ClubGovernanceScope { .init(clubID: source.context.scope.clubID) }
    public var seed: [String: ClubGovernanceValue] { ["targetType": .string("ACTIVITY"), "targetId": .integer(choice.id)] }
}
