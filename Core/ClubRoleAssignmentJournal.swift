import Foundation

/// Immutable original assign request identity, without credentials, roster, names or role assertions.
public struct ClubRoleAssignmentEntry: Codable, Equatable, Identifiable {
    public var id: String { requestID }
    public let formatVersion: Int, accountID: Int, clubID: Int, activityID: Int?, targetMemberID: Int
    public let namespace: String, realm: String, requestID: String, roleCode: String
    public private(set) var outcome: String
    public var scope: ClubGovernanceScope { .init(clubID: clubID, activityID: activityID) }
    init(review: ClubGovernanceReview, context: RuntimeDependencyContext) throws {
        let command = review.command
        guard command.operation == .assignRole, review.identity.accountID == context.session.accountID,
              review.identity.epoch == context.session.epoch, review.snapshot.operation == .roles,
              let club = command.scope.clubID, let target = command.fields["targetMemberId"]?.int,
              let id = command.fields["requestId"]?.string, let role = command.fields["roleCode"]?.string,
              command.fields["expiresAt"] == nil, command.fields["expiresAtEpochMs"] == nil,
              review.snapshot.value["roles"].array?.contains(where: { $0["roleCode"].string == role }) == true,
              review.supportingMembers?.value.array?.contains(where: { $0["memberId"].int == target && $0["isOwner"] == .bool(false) }) == true else { throw ClubRoleAssignmentFailure.invalid }
        formatVersion = 1; accountID = context.session.accountID; clubID = club; activityID = command.scope.activityID
        targetMemberID = target; requestID = id; roleCode = role
        namespace = context.session.namespace; realm = context.baseURL.absoluteString; outcome = "UNKNOWN"
        try validate(context)
    }
    var fields: [String: Any] {
        var result: [String: Any] = ["clubId": clubID, "targetMemberId": targetMemberID, "requestId": requestID, "roleCode": roleCode, "expiresAtEpochMs": NSNull()]
        if let activityID { result["activityId"] = activityID }; return result
    }
    func validate(_ context: RuntimeDependencyContext) throws {
        guard formatVersion == 1, accountID == context.session.accountID, namespace == context.session.namespace, realm == context.baseURL.absoluteString,
              clubID > 0, activityID == nil || activityID! > 0, targetMemberID > 0, targetMemberID != accountID,
              ClubRoleRevocationRoute.requestID(requestID), ClubRoleRevocationRoute.roles(activityID).contains(roleCode),
              ["UNKNOWN", "APPLIED", "NOT_SENT"].contains(outcome) else { throw ClubRoleAssignmentFailure.persistence }
    }
    fileprivate mutating func settle(_ value: String) throws {
        guard ["APPLIED", "NOT_SENT"].contains(value), outcome == "UNKNOWN" || outcome == value else { throw ClubRoleAssignmentFailure.persistence }; outcome = value
    }
}
@MainActor public final class ClubRoleAssignmentJournal {
    private let directory: URL?
    public init(directory: URL?) { self.directory = directory }
    private func file(_ context: RuntimeDependencyContext, clubID: Int) throws -> URL {
        guard let directory else { throw ClubRoleAssignmentFailure.persistence }
        let key = [context.baseURL.absoluteString, context.session.namespace, String(context.session.accountID), String(clubID)].map { "\($0.utf8.count):\($0)" }.joined()
        return directory.appendingPathComponent(ClubRoleRevocationRoute.digest(key) + ".json")
    }
    public func read(_ context: RuntimeDependencyContext, clubID: Int) throws -> [ClubRoleAssignmentEntry] {
        let url = try file(context, clubID: clubID)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attrs[.type] as? FileAttributeType == .typeRegular, let size = attrs[.size] as? NSNumber, size.intValue > 0, size.intValue <= 4_194_304 else { throw ClubRoleAssignmentFailure.persistence }
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else { throw ClubRoleAssignmentFailure.persistence }; _ = try ContentDraftJSON.parse(text)
        let entries = try JSONDecoder().decode([ClubRoleAssignmentEntry].self, from: data)
        guard Set(entries.map(\.requestID)).count == entries.count, entries.allSatisfy({ $0.clubID == clubID }) else { throw ClubRoleAssignmentFailure.persistence }
        try entries.forEach { try $0.validate(context) }; return entries
    }
    func reserve(_ entry: ClubRoleAssignmentEntry, context: RuntimeDependencyContext) throws {
        try entry.validate(context); var entries = try read(context, clubID: entry.clubID)
        guard !entries.contains(where: { $0.requestID == entry.requestID || ($0.scope == entry.scope && $0.outcome == "UNKNOWN" && ($0.targetMemberID == entry.targetMemberID || ($0.roleCode == "EVENT_LEAD" && entry.roleCode == "EVENT_LEAD"))) }) else { throw ClubRoleAssignmentFailure.locked }
        entries.append(entry); try write(entries, context: context, clubID: entry.clubID)
    }
    func settle(_ entry: ClubRoleAssignmentEntry, outcome: String, context: RuntimeDependencyContext) throws {
        var entries = try read(context, clubID: entry.clubID)
        guard let index = entries.firstIndex(where: { $0.requestID == entry.requestID }),
              entries[index].targetMemberID == entry.targetMemberID, entries[index].activityID == entry.activityID,
              entries[index].roleCode == entry.roleCode else { throw ClubRoleAssignmentFailure.persistence }
        try entries[index].settle(outcome); try write(entries, context: context, clubID: entry.clubID)
    }
    private func write(_ entries: [ClubRoleAssignmentEntry], context: RuntimeDependencyContext, clubID: Int) throws {
        guard let directory else { throw ClubRoleAssignmentFailure.persistence }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var root = directory; var values = URLResourceValues(); values.isExcludedFromBackup = true; try root.setResourceValues(values)
        let data = try JSONEncoder().encode(entries), url = try file(context, clubID: clubID)
        guard data.count <= 4_194_304 else { throw ClubRoleAssignmentFailure.persistence }
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: url, options: .atomic)
        #endif
        guard try read(context, clubID: clubID) == entries else { throw ClubRoleAssignmentFailure.persistence }
    }
}
