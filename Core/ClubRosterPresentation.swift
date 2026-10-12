import Foundation

public enum ClubRosterBucket: String, CaseIterable, Hashable {
    case registered, waitlist, arrived, noShow
    public var localizationKey: String { "club.gov." + rawValue }
}
public struct ClubRosterMember: Equatable, Identifiable {
    public let id: Int
    public let nickname: String?
    public let waitlistState: String?
    public let correctionVersion: Int?
}

/// A projection of one authorized roster response. Missing arrays never become empty success.
public struct ClubRosterPresentation: Equatable {
    public let scope: ClubGovernanceScope
    public let groups: [ClubRosterBucket: [ClubRosterMember]]
    public let correctionOperable: Bool?
    public let correctionStart: String?
    public let correctionEnd: String?
    private let source: ClubGovernanceSnapshot
    private let sourceContext: ClubGovernanceReadContext
    public init(snapshot: ClubGovernanceSnapshot, context: ClubGovernanceReadContext) throws {
        try context.scope.validate()
        guard context.operation == .roster, context.accepts(snapshot),
              let club = context.scope.clubID, club > 0, let activity = context.scope.activityID, activity > 0,
              (context.identity?.accountID ?? 0) > 0 else { throw ClubGovernanceFailure.targetChanged }
        guard snapshot.permissions?.allows(ClubGovernanceRead.roster.permission, scope: context.scope) == true else { throw ClubGovernanceFailure.forbidden }
        guard snapshot.value["phoneIncluded"] == .bool(false) else { throw ClubGovernanceFailure.malformed }
        var groups: [ClubRosterBucket: [ClubRosterMember]] = [:]
        for bucket in ClubRosterBucket.allCases {
            guard let rows = snapshot.value[bucket.rawValue].array else { throw ClubGovernanceFailure.malformed }
            var members: [ClubRosterMember] = [], ids = Set<Int>()
            for row in rows {
                guard row.object != nil, let id = ClubCustomerHistoryTopicRoute.positiveID(row["memberId"]), ids.insert(id).inserted,
                      row["clubId"] == .null || ClubCustomerHistoryTopicRoute.positiveID(row["clubId"]) == club,
                      row["activityId"] == .null || ClubCustomerHistoryTopicRoute.positiveID(row["activityId"]) == activity else { throw ClubGovernanceFailure.malformed }
                let version = row["correctionVersion"].int
                guard row["correctionVersion"] == .null || (version != nil && version! >= 0) else { throw ClubGovernanceFailure.malformed }
                members.append(.init(id: id, nickname: Self.nonempty(row["nickname"]),
                                     waitlistState: bucket == .waitlist ? Self.nonempty(row["state"]) : nil, correctionVersion: version))
            }
            groups[bucket] = members
        }
        let window = snapshot.value["correctionWindow"]
        correctionOperable = window["operable"].bool
        // Preserve returned clock strings. Do not assume a timezone or manufacture a missing bound.
        correctionStart = correctionOperable == nil ? nil : Self.nonempty(window["startAt"])
        correctionEnd = correctionOperable == nil ? nil : Self.nonempty(window["endAt"])
        scope = context.scope; self.groups = groups; source = snapshot; sourceContext = context
    }
    private static func nonempty(_ value: ClubGovernanceValue) -> String? {
        guard let raw = value.string else { return nil }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines); return text.isEmpty ? nil : text
    }
    public func members(in bucket: ClubRosterBucket) -> [ClubRosterMember] { groups[bucket] ?? [] }
    public func count(in bucket: ClubRosterBucket) -> Int { members(in: bucket).count }
    public var rosterTotal: Int { count(in: .registered) + count(in: .arrived) + count(in: .noShow) }
    public func correctionRoute(memberID: Int, bucket: ClubRosterBucket, context: ClubGovernanceReadContext,
                                snapshotGeneration: UInt64, namespace: String) -> ClubRosterCorrectionRoute? {
        guard context == sourceContext, context.accepts(source), bucket != .waitlist, correctionOperable != false,
              let member = members(in: bucket).first(where: { $0.id == memberID }), let version = member.correctionVersion else { return nil }
        return .init(scope: .init(clubID: scope.clubID, activityID: scope.activityID, memberID: memberID),
                     version: version, source: source, context: context, generation: snapshotGeneration, namespace: namespace)
    }
}

/// Read-bound entry to the existing correction form. It cannot authorize a correction itself.
public struct ClubRosterCorrectionRoute: Equatable {
    public let scope: ClubGovernanceScope
    public let version: Int
    public let namespace: String
    private let source: ClubGovernanceSnapshot
    private let context: ClubGovernanceReadContext
    private let generation: UInt64
    fileprivate init(scope: ClubGovernanceScope, version: Int, source: ClubGovernanceSnapshot, context: ClubGovernanceReadContext, generation: UInt64, namespace: String) {
        self.scope = scope; self.version = version; self.source = source; self.context = context; self.generation = generation; self.namespace = namespace
    }
    public func isCurrent(snapshot: ClubGovernanceSnapshot?, context: ClubGovernanceReadContext, snapshotGeneration: UInt64, namespace: String) -> Bool {
        self.context == context && self.generation == snapshotGeneration && self.namespace == namespace && source == snapshot
    }
}
