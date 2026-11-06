import Foundation
import CryptoKit

public struct ClubOrdinaryAdmissionPending: Codable, Equatable {
    public let accountID: Int
    public let clubID: Int
    public let requestID: UUID
    public let action: ClubAction
    public let payloadSHA256: String
    public let hasOriginalReceipt: Bool
    public init(accountID: Int, clubID: Int, requestID: UUID, action: ClubAction, hasOriginalReceipt: Bool, message: String) {
        self.accountID = accountID; self.clubID = clubID; self.requestID = requestID
        self.action = action; self.hasOriginalReceipt = hasOriginalReceipt
        payloadSHA256 = SHA256.hash(data: Data((action.rawValue + "\n" + message).utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// Safety fence only, not a membership source. No credentials, message, roster,
/// phone number or business result is persisted. Logout never clears this journal.
@MainActor public protocol ClubOrdinaryAdmissionJournaling {
    func pending(accountID: Int, clubID: Int) throws -> ClubOrdinaryAdmissionPending?
    func reserve(_ value: ClubOrdinaryAdmissionPending) throws
    func retire(_ value: ClubOrdinaryAdmissionPending) throws
}

/// An exact immutable audit projection, never a current-membership observation.
public struct ClubOrdinaryAdmissionOriginalReceipt: Decodable, Equatable {
    public let actorMemberId: Int
    public let clubId: Int
    public let requestId: String
    public let action: ClubAction
    public let state: String
    public let membershipState: String?
    public let payloadSHA256: String
    public func matches(_ pending: ClubOrdinaryAdmissionPending) -> Bool {
        actorMemberId == pending.accountID && clubId == pending.clubID &&
        requestId == pending.requestID.uuidString.lowercased() && action == pending.action && payloadSHA256 == pending.payloadSHA256 &&
        ["APPLIED", "UNKNOWN"].contains(state) &&
        (state == "UNKNOWN" || membershipState == (action == .leave ? "left" : action == .apply ? "pending" : "joined"))
    }
}
