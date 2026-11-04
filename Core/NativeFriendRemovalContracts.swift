import Foundation
import CryptoKit

/// One explicit gesture, scoped to an exact existing relationship version. Never a toggle.
public struct NativeFriendRemovalCommand: Codable, Equatable, Sendable {
    public let requestID: UUID
    public let peerID: Int64
    public let expectedVersion: Int64
    public init(requestID: UUID = UUID(), peerID: Int64, expectedVersion: Int64) {
        self.requestID = requestID; self.peerID = peerID; self.expectedVersion = expectedVersion
    }
    public var fingerprint: String {
        SHA256.hash(data: Data("friend-removal-v1\n\(peerID)\n\(expectedVersion)".utf8)).map { String(format: "%02x", $0) }.joined()
    }
    public func body() throws -> Data { try JSONSerialization.data(withJSONObject: ["peer_id": peerID, "expected_version": expectedVersion, "request_id": requestID.uuidString], options: [.sortedKeys]) }
}

/// Historical terminal outcome is separate from today's relationship (which may have been re-added).
public struct NativeFriendRemovalReceipt: Codable, Equatable, Sendable {
    public let viewerID: Int64
    public let peerID: Int64
    public let expectedVersion: Int64
    public let requestID: String
    public let action: String
    public let payloadHash: String
    public let outcome: String
    public let reason: String?
    public let removedVersion: Int64?
    public let currentRelationship: NativeFriendRelationship?
    public init(viewerID: Int64, command: NativeFriendRemovalCommand, outcome: String, reason: String? = nil,
                removedVersion: Int64? = nil, currentRelationship: NativeFriendRelationship? = nil) {
        self.viewerID = viewerID; self.peerID = command.peerID; self.expectedVersion = command.expectedVersion
        self.requestID = command.requestID.uuidString; self.action = "remove"; self.payloadHash = command.fingerprint
        self.outcome = outcome; self.reason = reason; self.removedVersion = removedVersion; self.currentRelationship = currentRelationship
    }
    enum CodingKeys: String, CodingKey {
        case viewerID = "viewer_id", peerID = "peer_id", expectedVersion = "expected_version", requestID = "request_id"
        case action, payloadHash = "payload_hash", outcome, reason, removedVersion = "removed_version", currentRelationship = "current_relationship"
    }
    public func matches(_ command: NativeFriendRemovalCommand, viewerID: Int64) -> Bool {
        guard command.peerID > 0, command.peerID != viewerID, command.expectedVersion > 0, command.expectedVersion < Int64.max,
              self.viewerID == viewerID, peerID == command.peerID, expectedVersion == command.expectedVersion,
              UUID(uuidString: requestID) == command.requestID, action == "remove", payloadHash == command.fingerprint,
              ["APPLIED", "REJECTED", "UNKNOWN"].contains(outcome) else { return false }
        if outcome == "APPLIED" && (removedVersion != expectedVersion + 1 || reason != "REMOVED") { return false }
        if outcome != "APPLIED" && removedVersion != nil { return false }
        if let current = currentRelationship {
            guard current.viewerID == viewerID, current.peerID == peerID, current.version >= 0,
                  current.conversationID.map({ $0 > 0 }) ?? true else { return false }
        }
        return true
    }
}

@MainActor public protocol NativeFriendRemovalServing: AnyObject {
    var viewerID: Int64 { get }
    var isCurrent: Bool { get }
    var canWrite: Bool { get }
    var canSettle: Bool { get }
    func relationship(peerID: Int64) async throws -> NativeFriendRelationship
    func remove(_ command: NativeFriendRemovalCommand) async throws -> NativeFriendRemovalReceipt
    func receipt(_ command: NativeFriendRemovalCommand) async throws -> NativeFriendRemovalReceipt
    func settle(_ command: NativeFriendRemovalCommand) async throws -> NativeFriendRemovalReceipt
}
