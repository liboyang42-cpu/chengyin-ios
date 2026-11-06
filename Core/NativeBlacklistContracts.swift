import Foundation
import CryptoKit

public enum NativeBlacklistFailure: Error, Equatable { case invalid, unavailable, notSent, unknown, unauthorized }

public struct NativeBlacklistItem: Codable, Equatable, Identifiable, Sendable {
    public let blockID: Int64
    public let peerID: Int64
    public let nickname: String
    public var id: Int64 { blockID }
    public init(blockID: Int64, peerID: Int64, nickname: String) { self.blockID = blockID; self.peerID = peerID; self.nickname = nickname }
    enum CodingKeys: String, CodingKey { case blockID = "block_id", peerID = "peer_id", nickname }
}
public struct NativeBlacklistPage: Codable, Equatable, Sendable {
    public let viewerID: Int64
    public let items: [NativeBlacklistItem]
    public let hasMore: Bool
    public let nextCursor: Int64?
    public let writeEnabled: Bool
    public init(viewerID: Int64, items: [NativeBlacklistItem], hasMore: Bool = false, nextCursor: Int64? = nil, writeEnabled: Bool = false) {
        self.viewerID = viewerID; self.items = items; self.hasMore = hasMore; self.nextCursor = nextCursor; self.writeEnabled = writeEnabled
    }
    enum CodingKeys: String, CodingKey { case viewerID = "viewer_id", items, hasMore = "has_more", nextCursor = "next_cursor", writeEnabled = "write_enabled" }
    public func valid(viewer: Int64, cursor: Int64) -> Bool {
        guard viewerID == viewer, cursor >= 0, items.count <= 50, Set(items.map(\.peerID)).count == items.count,
              Set(items.map(\.blockID)).count == items.count, hasMore == (nextCursor != nil),
              !hasMore || (items.count == 50 && nextCursor == items.last?.blockID) else { return false }
        var prior = cursor == 0 ? Int64.max : cursor
        for item in items {
            guard item.blockID > 0, item.blockID < prior, item.peerID > 0, item.peerID != viewer,
                  item.nickname.utf8.count <= 4096 else { return false }
            prior = item.blockID
        }
        return true
    }
}
public struct NativeBlacklistCurrent: Codable, Equatable, Sendable {
    public let viewerID: Int64
    public let peerID: Int64
    public let blocked: Bool
    public let blockID: Int64?
    public init(viewerID: Int64, peerID: Int64, blocked: Bool, blockID: Int64?) {
        self.viewerID = viewerID; self.peerID = peerID; self.blocked = blocked; self.blockID = blockID
    }
    enum CodingKeys: String, CodingKey { case viewerID = "viewer_id", peerID = "peer_id", blocked, blockID = "block_id" }
    public func valid(viewer: Int64, peer: Int64) -> Bool {
        viewerID == viewer && peerID == peer && peer > 0 && peer != viewer && blocked == (blockID != nil) && (blockID.map { $0 > 0 } ?? true)
    }
}
/// Exact original operation. blockID is the actual auto-increment im_block row incarnation, not peer ID.
public struct NativeBlacklistCommand: Codable, Equatable, Sendable {
    public let requestID: UUID
    public let peerID: Int64
    public let expectedBlockID: Int64
    public init(requestID: UUID = UUID(), peerID: Int64, expectedBlockID: Int64) {
        self.requestID = requestID; self.peerID = peerID; self.expectedBlockID = expectedBlockID
    }
    public var fingerprint: String {
        SHA256.hash(data: Data("native-blacklist-v1\n\(peerID)\n\(expectedBlockID)".utf8)).map { String(format: "%02x", $0) }.joined()
    }
    public func body() throws -> Data {
        try JSONSerialization.data(withJSONObject: ["peer_id": peerID, "expected_block_id": expectedBlockID, "request_id": requestID.uuidString.lowercased()], options: [.sortedKeys])
    }
}
public struct NativeBlacklistReceipt: Codable, Equatable, Sendable {
    public let viewerID: Int64
    public let peerID: Int64
    public let expectedBlockID: Int64
    public let requestID: String
    public let action: String
    public let payloadHash: String
    public let outcome: String
    public let reason: String?
    public init(viewerID: Int64, command: NativeBlacklistCommand, outcome: String, reason: String? = nil) {
        self.viewerID = viewerID; peerID = command.peerID; expectedBlockID = command.expectedBlockID
        requestID = command.requestID.uuidString.lowercased(); action = "UNBLOCK"; payloadHash = command.fingerprint
        self.outcome = outcome; self.reason = reason
    }
    enum CodingKeys: String, CodingKey {
        case viewerID = "viewer_id", peerID = "peer_id", expectedBlockID = "expected_block_id", requestID = "request_id"
        case action, payloadHash = "payload_hash", outcome, reason
    }
    public func matches(_ command: NativeBlacklistCommand, viewer: Int64) -> Bool {
        guard command.peerID > 0, command.peerID != viewer, command.expectedBlockID > 0, viewerID == viewer,
              peerID == command.peerID, expectedBlockID == command.expectedBlockID, UUID(uuidString: requestID) == command.requestID,
              action == "UNBLOCK", payloadHash == command.fingerprint else { return false }
        switch outcome {
        case "APPLIED": return reason == "UNBLOCKED"
        case "REJECTED": return ["BLOCK_ABSENT", "BLOCK_CHANGED", "FINALIZED_WITHOUT_CHANGE"].contains(reason ?? "")
        case "UNKNOWN": return reason == nil
        default: return false
        }
    }
}
@MainActor public protocol NativeBlacklistServing: AnyObject {
    var viewerID: Int64 { get }
    var isCurrent: Bool { get }
    var canWrite: Bool { get }
    var canSettle: Bool { get }
    func page(cursor: Int64) async throws -> NativeBlacklistPage
    func current(peerID: Int64) async throws -> NativeBlacklistCurrent
    func unblock(_ command: NativeBlacklistCommand) async throws -> NativeBlacklistReceipt
    func receipt(_ command: NativeBlacklistCommand) async throws -> NativeBlacklistReceipt
    func settle(_ command: NativeBlacklistCommand) async throws -> NativeBlacklistReceipt
}
