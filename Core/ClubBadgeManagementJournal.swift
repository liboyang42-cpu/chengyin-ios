import Foundation

/// Request identity only. Never persist a token, member name, badge draft or copied badge list.
/// UNKNOWN is written BEFORE the transport can dispatch, and survives account/page/process exit.
public struct ClubBadgeManagementEntry: Codable, Equatable, Identifiable {
    public var id: String { requestID }
    public let formatVersion: Int, accountID: Int, clubID: Int
    public let realm: String, namespace: String, requestID: String, operation: String, sourceSHA256: String
    public let memberID: Int?, badgeCode: String?
    public private(set) var outcome: String
    public private(set) var receipt: ClubBadgeOriginalReceipt?
    init(context: RuntimeDependencyContext, clubID: Int, operation: String, fields: [String: Any]) throws {
        formatVersion = 1; accountID = context.session.accountID; self.clubID = clubID
        realm = context.baseURL.absoluteString; namespace = context.session.namespace
        requestID = UUID().uuidString.lowercased(); self.operation = operation
        sourceSHA256 = try ClubBadgeManagementRoute.sourceHash(operation: operation, fields: fields)
        memberID = operation == "GRANT" ? ClubBadgeManagementRoute.positive(fields["memberId"]) : nil
        badgeCode = operation == "GRANT" ? fields["badgeCode"] as? String : nil
        outcome = "UNKNOWN"; receipt = nil
        guard ClubBadgeManagementRoute.positive(fields["clubId"]) == clubID else { throw ClubBadgeManagementFailure.invalid }
        try validate(context, clubID: clubID)
    }
    var receiptFields: [String: Any] { ["clubId": clubID, "requestId": requestID, "operation": operation, "sourceSHA256": sourceSHA256] }
    func validate(_ context: RuntimeDependencyContext, clubID: Int) throws {
        guard formatVersion == 1, self.clubID == clubID, clubID > 0,
              accountID == context.session.accountID, realm == context.baseURL.absoluteString, namespace == context.session.namespace,
              ClubBadgeManagementRoute.requestID(requestID), ClubBadgeManagementRoute.hash(sourceSHA256),
              ["CREATE", "GRANT"].contains(operation), ["UNKNOWN", "CONFIRMED", "REJECTED", "NOT_SENT"].contains(outcome) else { throw ClubBadgeManagementFailure.persistence }
        if operation == "CREATE" {
            guard memberID == nil, badgeCode == nil else { throw ClubBadgeManagementFailure.persistence }
        } else {
            guard (memberID ?? 0) > 0, let code = badgeCode, ClubBadgeManagementRoute.validCode(code) else { throw ClubBadgeManagementFailure.persistence }
        }
        if let receipt {
            guard outcome == "CONFIRMED", receipt.isTerminal else { throw ClubBadgeManagementFailure.persistence }
            try receipt.validate(self)
        } else if outcome == "CONFIRMED" { throw ClubBadgeManagementFailure.persistence }
    }
    fileprivate mutating func settle(outcome: String, receipt: ClubBadgeOriginalReceipt?) throws {
        guard self.outcome == "UNKNOWN" || (self.outcome == outcome && self.receipt == receipt),
              ["CONFIRMED", "REJECTED", "NOT_SENT"].contains(outcome) else { throw ClubBadgeManagementFailure.persistence }
        if outcome == "CONFIRMED" {
            guard let receipt, receipt.isTerminal else { throw ClubBadgeManagementFailure.persistence }
            try receipt.validate(self)
        } else if receipt != nil { throw ClubBadgeManagementFailure.persistence }
        self.outcome = outcome; self.receipt = receipt
    }
}

@MainActor public final class ClubBadgeManagementJournal {
    private let directory: URL?
    public init(directory: URL?) { self.directory = directory }
    private func file(_ context: RuntimeDependencyContext, clubID: Int) throws -> URL {
        guard let directory, clubID > 0 else { throw ClubBadgeManagementFailure.persistence }
        let key = [context.baseURL.absoluteString, context.session.namespace, String(context.session.accountID), String(clubID)]
            .map { "\($0.utf8.count):\($0)" }.joined()
        return directory.appendingPathComponent(ClubBadgeManagementRoute.digest(key) + ".json")
    }
    public func read(_ context: RuntimeDependencyContext, clubID: Int) throws -> [ClubBadgeManagementEntry] {
        let url = try file(context, clubID: clubID)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular, let size = attributes[.size] as? NSNumber,
              size.intValue > 0, size.intValue <= 4_194_304 else { throw ClubBadgeManagementFailure.persistence }
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8), (try? ContentDraftJSON.parse(text)) != nil else { throw ClubBadgeManagementFailure.persistence }
        let entries = try JSONDecoder().decode([ClubBadgeManagementEntry].self, from: data)
        guard Set(entries.map(\.requestID)).count == entries.count else { throw ClubBadgeManagementFailure.persistence }
        try entries.forEach { try $0.validate(context, clubID: clubID) }; return entries
    }
    func reserve(_ entry: ClubBadgeManagementEntry, context: RuntimeDependencyContext) throws {
        try entry.validate(context, clubID: entry.clubID)
        var entries = try read(context, clubID: entry.clubID)
        // One outstanding original request per account/realm/club, including across two views.
        guard !entries.contains(where: { $0.outcome == "UNKNOWN" || $0.requestID == entry.requestID }) else { throw ClubBadgeManagementFailure.pending }
        entries.append(entry); try write(entries, context: context, clubID: entry.clubID)
    }
    func settle(_ entry: ClubBadgeManagementEntry, outcome: String, receipt: ClubBadgeOriginalReceipt? = nil, context: RuntimeDependencyContext) throws {
        var entries = try read(context, clubID: entry.clubID)
        guard let index = entries.firstIndex(where: { $0.requestID == entry.requestID }),
              entries[index].sourceSHA256 == entry.sourceSHA256, entries[index].operation == entry.operation,
              entries[index].memberID == entry.memberID, entries[index].badgeCode == entry.badgeCode else { throw ClubBadgeManagementFailure.persistence }
        try entries[index].settle(outcome: outcome, receipt: receipt)
        try write(entries, context: context, clubID: entry.clubID)
    }
    private func write(_ entries: [ClubBadgeManagementEntry], context: RuntimeDependencyContext, clubID: Int) throws {
        guard let directory else { throw ClubBadgeManagementFailure.persistence }
        try entries.forEach { try $0.validate(context, clubID: clubID) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var root = directory; var values = URLResourceValues(); values.isExcludedFromBackup = true; try root.setResourceValues(values)
        let data = try JSONEncoder().encode(entries), url = try file(context, clubID: clubID)
        guard data.count <= 4_194_304 else { throw ClubBadgeManagementFailure.persistence }
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: url, options: .atomic)
        #endif
        guard try read(context, clubID: clubID) == entries else { throw ClubBadgeManagementFailure.persistence }
    }
}
