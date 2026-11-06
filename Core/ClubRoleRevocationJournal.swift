import Foundation
import CryptoKit

/// Minimal immutable intent identity only. No credentials, reason text, nickname or roster cache.
public struct ClubRoleRevocationEntry: Codable, Equatable, Identifiable {
    public var id: String { requestID }
    public let formatVersion: Int, accountID: Int, clubID: Int, activityID: Int?, assignmentID: Int, targetMemberID: Int, assignmentVersion: Int
    public let namespace: String, realm: String, requestID: String, roleCode: String, reasonSHA256: String
    public private(set) var outcome: String
    public var scope: ClubGovernanceScope { .init(clubID: clubID, activityID: activityID) }
    init(review: ClubGovernanceReview, context: RuntimeDependencyContext) throws {
        let command = review.command
        guard command.operation == .revokeRole, review.identity.accountID == context.session.accountID,
              review.identity.epoch == context.session.epoch, review.snapshot.operation == .roles,
              let club = command.scope.clubID, let assignment = command.fields["assignmentId"]?.int,
              let version = command.fields["version"]?.int, let id = command.fields["requestId"]?.string,
              command.fields["reason"]?.string == ClubGovernanceFormDraft.revokeRoleReason,
              let row = review.snapshot.value["assignments"].array?.first(where: { $0["id"].int == assignment && $0["version"].int == version }),
              let target = row["targetMemberId"].int, let role = row["roleCode"].string,
              row["scopeType"].string == (command.scope.activityID == nil ? "CLUB" : "EVENT"),
              row["scopeId"].int == (command.scope.activityID ?? club) else { throw ClubRoleRevocationFailure.invalid }
        formatVersion = 1; accountID = context.session.accountID; clubID = club; activityID = command.scope.activityID
        assignmentID = assignment; assignmentVersion = version; targetMemberID = target; requestID = id; roleCode = role
        namespace = context.session.namespace; realm = context.baseURL.absoluteString
        reasonSHA256 = ClubRoleRevocationRoute.digest(ClubGovernanceFormDraft.revokeRoleReason); outcome = "UNKNOWN"
        try validate(context)
    }
    var fields: [String: Any] {
        var result: [String: Any] = ["clubId": clubID, "assignmentId": assignmentID, "targetMemberId": targetMemberID, "version": assignmentVersion, "requestId": requestID, "roleCode": roleCode, "reasonSHA256": reasonSHA256]
        if let activityID { result["activityId"] = activityID }; return result
    }
    func validate(_ context: RuntimeDependencyContext) throws {
        guard formatVersion == 1, accountID == context.session.accountID, namespace == context.session.namespace, realm == context.baseURL.absoluteString,
              clubID > 0, activityID == nil || activityID! > 0, assignmentID > 0, targetMemberID > 0, assignmentVersion >= 0, assignmentVersion <= Int(Int32.max),
              ClubRoleRevocationRoute.requestID(requestID), ClubRoleRevocationRoute.roles(activityID).contains(roleCode),
              reasonSHA256 == ClubRoleRevocationRoute.digest(ClubGovernanceFormDraft.revokeRoleReason), ["UNKNOWN", "APPLIED", "NOT_SENT"].contains(outcome) else { throw ClubRoleRevocationFailure.persistence }
    }
    fileprivate mutating func settle(_ value: String) throws {
        guard ["APPLIED", "NOT_SENT"].contains(value), outcome == "UNKNOWN" || outcome == value else { throw ClubRoleRevocationFailure.persistence }; outcome = value
    }
}
@MainActor public final class ClubRoleRevocationJournal {
    private let directory: URL?
    public init(directory: URL?) { self.directory = directory }
    private func file(_ context: RuntimeDependencyContext, clubID: Int) throws -> URL {
        guard let directory else { throw ClubRoleRevocationFailure.persistence }
        let key = [context.baseURL.absoluteString, context.session.namespace, String(context.session.accountID), String(clubID)].map { "\($0.utf8.count):\($0)" }.joined()
        return directory.appendingPathComponent(ClubRoleRevocationRoute.digest(key) + ".json")
    }
    public func read(_ context: RuntimeDependencyContext, clubID: Int) throws -> [ClubRoleRevocationEntry] {
        let url = try file(context, clubID: clubID)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attrs[.type] as? FileAttributeType == .typeRegular, let size = attrs[.size] as? NSNumber, size.intValue > 0, size.intValue <= 4_194_304 else { throw ClubRoleRevocationFailure.persistence }
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else { throw ClubRoleRevocationFailure.persistence }; _ = try ContentDraftJSON.parse(text)
        let entries = try JSONDecoder().decode([ClubRoleRevocationEntry].self, from: data)
        guard Set(entries.map(\.requestID)).count == entries.count, entries.allSatisfy({ $0.clubID == clubID }) else { throw ClubRoleRevocationFailure.persistence }
        try entries.forEach { try $0.validate(context) }; return entries
    }
    func reserve(_ entry: ClubRoleRevocationEntry, context: RuntimeDependencyContext) throws {
        try entry.validate(context); var entries = try read(context, clubID: entry.clubID)
        guard !entries.contains(where: { $0.requestID == entry.requestID || ($0.assignmentID == entry.assignmentID && $0.outcome != "NOT_SENT") }) else { throw ClubRoleRevocationFailure.locked }
        entries.append(entry); try write(entries, context: context, clubID: entry.clubID)
    }
    func settle(_ entry: ClubRoleRevocationEntry, outcome: String, context: RuntimeDependencyContext) throws {
        var entries = try read(context, clubID: entry.clubID)
        guard let index = entries.firstIndex(where: { $0.requestID == entry.requestID }), entries[index].fields.keys.count == entry.fields.keys.count,
              entries[index].assignmentID == entry.assignmentID, entries[index].targetMemberID == entry.targetMemberID,
              entries[index].assignmentVersion == entry.assignmentVersion, entries[index].activityID == entry.activityID,
              entries[index].roleCode == entry.roleCode, entries[index].reasonSHA256 == entry.reasonSHA256 else { throw ClubRoleRevocationFailure.persistence }
        try entries[index].settle(outcome); try write(entries, context: context, clubID: entry.clubID)
    }
    private func write(_ entries: [ClubRoleRevocationEntry], context: RuntimeDependencyContext, clubID: Int) throws {
        guard let directory else { throw ClubRoleRevocationFailure.persistence }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var root = directory; var values = URLResourceValues(); values.isExcludedFromBackup = true; try root.setResourceValues(values)
        let data = try JSONEncoder().encode(entries), url = try file(context, clubID: clubID)
        guard data.count <= 4_194_304 else { throw ClubRoleRevocationFailure.persistence }
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: url, options: .atomic)
        #endif
        guard try read(context, clubID: clubID) == entries else { throw ClubRoleRevocationFailure.persistence }
    }
}
