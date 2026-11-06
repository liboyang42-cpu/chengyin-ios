import Foundation
import CryptoKit

/// Protected payload sidecar for the EXISTING OperationPendingJournal create lock.
/// No token, epoch-as-authority, new operation key or second server ledger.
@MainActor public final class GroupPollCreateRecoveryJournal {
    private let storage: any ProjectEditDataStorage
    private let owner: String
    private let conversationID: Int
    private struct Record: Codable { let schema: Int, owner: String, draft: GroupPollDraft }
    private var key: String { "im-poll-create-payload.v1."+Data((owner+"|"+String(conversationID)).utf8).base64EncodedString() }
    public init(storage: any ProjectEditDataStorage,namespace: String,realm: URL,accountID: Int,conversationID: Int) throws {
        guard !namespace.isEmpty,accountID > 0,conversationID > 0 else { throw APIError.invalidRequest };_ = try APIConfiguration(baseURL:realm)
        self.storage=storage;self.conversationID=conversationID
        owner=[namespace,realm.absoluteString,String(accountID)].map { "\($0.utf8.count):\($0)" }.joined(separator:"|")
    }
    public func restore() throws -> GroupPollDraft? {
        guard let bytes=try storage.read(key) else { return nil };guard bytes.count <= 32768 else { throw APIError.malformedResponse }
        let row=try JSONDecoder().decode(Record.self,from:bytes),draft=row.draft
        let encoded=try JSONEncoder().encode(row)
        guard row.schema == 1,row.owner == owner,draft.conversationId == conversationID,
              let id=UUID(uuidString:draft.clientPollKey),id.uuidString.lowercased() == draft.clientPollKey,
              (1...200).contains(draft.question.utf16.count),(2...10).contains(draft.options.count),
              draft.options.allSatisfy({(1...100).contains($0.utf16.count) && $0.trimmingCharacters(in:.whitespacesAndNewlines) == $0}),
              draft.question.trimmingCharacters(in:.whitespacesAndNewlines) == draft.question,
              draft.deadlineAt.map({ $0 >= 0 && $0 < 253402300799000 }) ?? true,
              (try JSONSerialization.jsonObject(with:bytes) as? NSDictionary) == (try JSONSerialization.jsonObject(with:encoded) as? NSDictionary)
        else { throw APIError.malformedResponse }
        return draft // An expired original remains readable; never renew or replace it.
    }
    public func save(_ draft: GroupPollDraft) throws {
        if let existing=try restore() { guard existing == draft else { throw APIError.invalidRequest };return }
        try storage.write(JSONEncoder().encode(Record(schema:1,owner:owner,draft:draft)),key:key)
        guard try restore() == draft else { throw APIError.malformedResponse }
    }
    public func clear(_ draft: GroupPollDraft) throws {
        guard try restore() == draft else { throw APIError.invalidRequest }
        try storage.remove(key);guard try restore() == nil else { throw APIError.malformedResponse }
    }
    /// Exact original CanonicalDigest.join(question.trim, options joined U+001E, deadlineMillis-or-empty).
    public static func originalRequestHash(_ draft: GroupPollDraft) -> String {
        let canonical=[draft.question,draft.options.joined(separator:"\u{001e}"),draft.deadlineAt.map(String.init) ?? ""].joined(separator:"\u{001f}")
        return SHA256.hash(data:Data(canonical.utf8)).map { String(format:"%02x",$0) }.joined()
    }
}

public struct GroupPollOriginalCreateReceipt {
    public enum State: String { case notFound = "NOT_FOUND", unknown = "UNKNOWN", applied = "APPLIED" }
    public let state: State
    public let poll: GroupPoll?
    public let requestHash: String?
}
