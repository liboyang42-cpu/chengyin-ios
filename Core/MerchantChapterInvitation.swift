import Foundation

/// C7: a chapter invitation addressed to the signed-in merchant (`source == 1`, the source's
/// INVITE leg of `chapter-application/mine`). Only the merchant owner holding
/// `merchant:coop:manage` may respond; `merchant:project:manage` is never a substitute.
/// The respond endpoint carries no requestId/version, so a lost response is never resent:
/// a minimal original-intent lock is kept locally and only an exact `mine` readback by
/// applicationId + chapter + topic + owner merchant can describe the current fact. A
/// readback that reaches the intended terminal state proves the current fact only; it
/// never proves this submission caused it, and the server reason is shown verbatim.
public struct MerchantChapterInvitation: Equatable, Identifiable {
    public enum Status: Equatable {
        case pending, approved, rejected, unknown(Int)
        public init(code: Int) {
            switch code { case 0: self = .pending; case 1: self = .approved; case 2: self = .rejected; default: self = .unknown(code) }
        }
        public var code: Int {
            switch self { case .pending: return 0; case .approved: return 1; case .rejected: return 2; case .unknown(let v): return v }
        }
    }
    public let applicationID: Int
    public let chapterID: Int
    public let topicID: Int
    public let chapterName: String?
    public let topicName: String?
    /// Wire field `merchantId` on mine/owner-list/owner-mine. That value is the member id
    /// (`m.member_id = a.merchant_id`), not the merchant archive id.
    public let ownerMemberID: Int?
    public let status: Status
    public let isInvite: Bool
    public let serverReason: String?
    public let raw: MerchantContentValue
    public var id: Int { applicationID }
    public var canRespond: Bool { isInvite && status == .pending }

    public init(row: MerchantContentValue) throws {
        guard row.object != nil, let id = row["id"].integer, id > 0,
              let chapter = row["chapterId"].integer, chapter > 0,
              let topic = row["topicId"].integer, topic > 0,
              let statusCode = row["status"].integer else { throw MerchantContentFailure.malformed }
        applicationID = id; chapterID = chapter; topicID = topic
        chapterName = row["chapterName"].text.flatMap { $0.isEmpty ? nil : $0 }
        topicName = row["topicName"].text.flatMap { $0.isEmpty ? nil : $0 }
        ownerMemberID = row["merchantId"].integer.flatMap { $0 > 0 ? $0 : nil }
        status = Status(code: statusCode)
        isInvite = row["source"].integer == 1 || row["source"].text == "INVITE" || row["source"].text == "1"
        serverReason = [row["auditRemark"].text, row["auditReason"].text, row["reason"].text, row["message"].text]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }
        raw = row
    }
    public static func list(_ value: MerchantContentValue) throws -> [MerchantChapterInvitation] {
        guard let rows = value.array ?? value["rows"].array else { throw MerchantContentFailure.malformed }
        return try rows.map { try MerchantChapterInvitation(row: $0) }
    }
    /// Fresh `access/me` gate for this group only: active owner + COOP_MANAGE + a merchant.
    public static func accessAllows(_ access: MerchantAccess) -> Bool {
        access.active && access.isOwner && access.merchantID != nil && access.allows(.coopManage)
    }
    /// Confirmation-page impact keys, stated before any submit. Acceptance is rechecked by
    /// the server for recruitment state, eligibility, remaining capacity and backfill; it
    /// changes the node-review state and pre-occupies one acceptance slot when it succeeds.
    public static func impactKeys(accepted: Bool) -> [String] {
        accepted
            ? ["merchantChapterInvitation.impact.acceptRecheck", "merchantChapterInvitation.impact.acceptNodeReview",
               "merchantChapterInvitation.impact.acceptSlot", "merchantChapterInvitation.impact.acceptNoRefund"]
            : ["merchantChapterInvitation.impact.rejectTerminal", "merchantChapterInvitation.impact.rejectNoSlot"]
    }
}

/// Minimal persisted original intent for a respond whose outcome may be lost. It stores no
/// token, contact or content; scope/account/merchant bind it to the exact signed-in owner.
public struct MerchantChapterInvitationIntent: Codable, Equatable {
    public let storageScope: String, accountID: Int, merchantID: Int
    public let applicationID: Int, chapterID: Int, topicID: Int, accepted: Bool
    public init(storageScope: String, accountID: Int, merchantID: Int, applicationID: Int, chapterID: Int, topicID: Int, accepted: Bool) throws {
        guard !storageScope.isEmpty, accountID > 0, merchantID > 0, applicationID > 0, chapterID > 0, topicID > 0 else { throw MerchantContentFailure.invalid }
        self.storageScope = storageScope; self.accountID = accountID; self.merchantID = merchantID
        self.applicationID = applicationID; self.chapterID = chapterID; self.topicID = topicID; self.accepted = accepted
    }
    /// Member-domain identity of the signed-in owner. The archive id stays in `merchantID`.
    public var ownerMemberID: Int { accountID }
    public var intendedStatus: MerchantChapterInvitation.Status { accepted ? .approved : .rejected }
    public var oppositeStatus: MerchantChapterInvitation.Status { accepted ? .rejected : .approved }
    /// Shared journal encoding (`MerchantContentPendingRecord.target/action`); no new store.
    public var target: String { "chapter-invitation:\(applicationID):\(chapterID):\(topicID):\(accepted ? 1 : 0)" }
    public static var action: String { "respondChapterInvitation" }
    public init?(record: MerchantContentPendingRecord) {
        guard record.action == Self.action else { return nil }
        let parts = record.target.split(separator: ":")
        guard parts.count == 5, parts[0] == "chapter-invitation",
              let app = Int(parts[1]), let chapter = Int(parts[2]), let topic = Int(parts[3]),
              parts[4] == "0" || parts[4] == "1",
              let value = try? MerchantChapterInvitationIntent(storageScope: record.storageScope, accountID: record.accountID,
                  merchantID: record.merchantID, applicationID: app, chapterID: chapter, topicID: topic, accepted: parts[4] == "1")
        else { return nil }
        self = value
    }
    public func matches(_ record: MerchantContentPendingRecord) -> Bool {
        record.storageScope == storageScope && record.accountID == accountID && record.merchantID == merchantID
            && record.target == target && record.action == Self.action
    }
}

public enum MerchantChapterInvitationReadback: Equatable {
    /// Exact row reached the intended terminal state. Proves the current fact only.
    case confirmedCurrentFact(reason: String?, row: MerchantContentValue)
    /// Exact row reached the opposite terminal state; the server fact wins, never resent.
    case oppositeTerminal(reason: String?, row: MerchantContentValue)
    case stillPending(row: MerchantContentValue)
    case missing, conflict

    public static func evaluate(intent: MerchantChapterInvitationIntent, row: MerchantContentValue?, currentOwnerMemberID: Int?) -> MerchantChapterInvitationReadback {
        guard currentOwnerMemberID == intent.ownerMemberID else { return .conflict }
        guard let row else { return .missing }
        guard let invitation = try? MerchantChapterInvitation(row: row),
              invitation.applicationID == intent.applicationID, invitation.chapterID == intent.chapterID,
              invitation.topicID == intent.topicID, invitation.isInvite,
              invitation.ownerMemberID == intent.ownerMemberID else { return .conflict }
        switch invitation.status {
        case intent.intendedStatus: return .confirmedCurrentFact(reason: invitation.serverReason, row: row)
        case intent.oppositeStatus: return .oppositeTerminal(reason: invitation.serverReason, row: row)
        case .pending: return .stillPending(row: row)
        default: return .conflict
        }
    }
    public var clearsIntentLock: Bool {
        switch self { case .confirmedCurrentFact, .oppositeTerminal: return true; case .stillPending, .missing, .conflict: return false }
    }
}
