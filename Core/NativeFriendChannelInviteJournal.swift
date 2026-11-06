import Foundation
import CryptoKit

/// One original pending gesture per account/realm, shared by channel, message and own-history entrances.
@MainActor public final class NativeFriendChannelInviteJournal {
    private struct Envelope: Codable { let schema: Int; let owner, proof: String; let command: NativeFriendChannelInviteCommand }
    private let storage: any ProjectEditDataStorage
    private let owner, key: String
    private static var leases: Set<String> = []
    public init(storage: any ProjectEditDataStorage, ownerKey: String) {
        self.storage = storage; owner = ownerKey
        key = "friend-channel-invite.intent.v1." + SHA256.hash(data: Data(ownerKey.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    public func acquire() -> Bool { Self.leases.insert(key).inserted }
    public func release() { Self.leases.remove(key) }
    public func restore() throws -> NativeFriendChannelInviteCommand? {
        guard let data = try storage.read(key) else { return nil }; guard data.count <= 32_768 else { throw NativeFriendFailure.invalid }
        let value = try JSONDecoder().decode(Envelope.self, from: data)
        guard value.schema == 1, value.owner == owner, value.proof == value.command.proof,
              (try JSONSerialization.jsonObject(with: data) as? NSDictionary) == (try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? NSDictionary) else { throw NativeFriendFailure.invalid }
        try value.command.validate(); return value.command
    }
    public func save(_ command: NativeFriendChannelInviteCommand) throws {
        try command.validate(); guard try restore() == nil else { throw NativeFriendFailure.unknown }
        try storage.write(try JSONEncoder().encode(Envelope(schema: 1, owner: owner, proof: command.proof, command: command)), key: key)
        guard try restore() == command else { throw NativeFriendFailure.unknown }
    }
    public func clear(_ command: NativeFriendChannelInviteCommand) throws {
        guard try restore() == command else { throw NativeFriendFailure.unknown }; try storage.remove(key)
        guard try restore() == nil else { throw NativeFriendFailure.unknown }
    }
}
