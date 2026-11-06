import Foundation
import CryptoKit

public extension NativeFriendCommand {
    var originalIntentProof: String {
        var fields = [source == nil ? "friend-command-v1" : (source?.type == 4 ? "friend-post-command-v1" : (source?.type == 3 ? "friend-team-command-v1" : (source?.type == 2 ? "friend-activity-command-v1" : "friend-channel-command-v1"))), String(peerID), action.rawValue, message,
                      expectedVersion.map(String.init) ?? "", reviewID.map(String.init) ?? ""]
        if let source { fields += [String(source.type), String(source.id)]; if source.type == 4 { fields.append(source.generation ?? "") } }
        return SHA256.hash(data: Data(fields.map { "\($0.utf8.count):\($0)" }.joined().utf8))
            .map { String(format: "%02x", $0) }.joined()
    }
    func validateOriginalIntent() throws {
        guard source == nil || (action == .request && source?.isValid == true),
              UUID(uuidString: requestID) != nil, peerID > 0,
              action == .request ? (expectedVersion == nil && reviewID == nil && !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && message.unicodeScalars.count <= 60)
                : (message.isEmpty && (expectedVersion ?? 0) > 0 && (reviewID == nil || (action == .cancel && (reviewID ?? 0) > 0))) else { throw NativeFriendFailure.invalid }
    }
}

/// Owner/realm protected full-intent companion to the existing receipt identity journal.
/// Old identity-only records remain recoverable, but can never manufacture a replay body.
@MainActor public final class NativeFriendIntentJournal {
    private struct Envelope: Codable { let schema: Int; let owner, proof: String; let command: NativeFriendCommand }
    private let storage: any ProjectEditDataStorage
    private let owner, key: String
    private static var leases: Set<String> = []
    public init(storage: any ProjectEditDataStorage, ownerKey: String) {
        self.storage = storage; owner = ownerKey
        key = "native-friend.intent.v1." + SHA256.hash(data: Data(ownerKey.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    public func acquire() -> Bool { Self.leases.insert(key).inserted }
    public func release() { Self.leases.remove(key) }
    public func restore() throws -> NativeFriendCommand? {
        guard let data = try storage.read(key) else { return nil }
        guard data.count < 8192 else { throw NativeFriendFailure.invalid }
        let value = try JSONDecoder().decode(Envelope.self, from: data)
        guard value.schema == 1, value.owner == owner, value.proof == value.command.originalIntentProof,
              (try JSONSerialization.jsonObject(with: data) as? NSDictionary) == (try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? NSDictionary) else { throw NativeFriendFailure.invalid }
        try value.command.validateOriginalIntent(); return value.command
    }
    public func save(_ command: NativeFriendCommand) throws {
        try command.validateOriginalIntent(); guard try restore() == nil else { throw NativeFriendFailure.unknown }
        try storage.write(JSONEncoder().encode(Envelope(schema: 1, owner: owner, proof: command.originalIntentProof, command: command)), key: key)
        guard try restore() == command else { throw NativeFriendFailure.invalid }
    }
    public func settle(_ command: NativeFriendCommand) throws {
        guard try restore() == command else { throw NativeFriendFailure.unknown }
        try storage.remove(key); guard try restore() == nil else { throw NativeFriendFailure.unknown }
    }
}
