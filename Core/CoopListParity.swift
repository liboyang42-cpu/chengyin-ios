import Foundation

/// Source `utils/merchant-official-channel.js` row shaping for `GET api/official/merchant-invites` on `pages/coop/list`.
public struct CoopOfficialInvite: Equatable, Identifiable {
    public enum Reward: Equatable { case share(rate: String), fixed(fee: String), resources, unconfirmed }
    public enum Stage: String, Equatable { case declined, expired, awaitingYou, won, notWon, awaitingReview, unknown }
    public enum Deadline: Equatable { case unconfirmed, monthDay(month: Int, day: Int), verbatim(String) }
    public let id: Int
    public let title: String
    public let coverURL: String?
    public let topicID: Int?
    public let status: Int?
    public let reward: Reward
    public let stage: Stage
    public let deadline: Deadline
    public var actionable: Bool { status == 0 }

    /// Rows lacking a positive invite ID or a non-blank title are dropped, as the source filters them.
    public static func rows(_ value: CoopFlowJSON) -> [CoopOfficialInvite] { (value.rows ?? []).compactMap(CoopOfficialInvite.init) }

    public init?(_ row: CoopFlowJSON) {
        guard let id = row["inviteId"].integer, id > 0,
              let title = row["title"].text?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { return nil }
        self.id = id; self.title = title
        coverURL = row["cover"].text.flatMap { $0.isEmpty ? nil : $0 }
        topicID = row["topicId"].integer
        status = row["status"].integer
        switch row["shareMode"].integer {
        case 1?: reward = row["shareRate"].text.map { .share(rate: $0) } ?? .unconfirmed
        case 2?: reward = row["fixedFee"].text.map { .fixed(fee: $0) } ?? .unconfirmed
        case 0?: reward = .resources
        default: reward = .unconfirmed
        }
        switch (status, row["auditStatus"].integer) {
        case (2?, _): stage = .declined
        case (5?, _): stage = .expired
        case (0?, _): stage = .awaitingYou
        case (1?, 1?): stage = .won
        case (1?, 2?): stage = .notWon
        case (1?, _): stage = .awaitingReview
        default: stage = .unknown
        }
        deadline = Self.deadline(row["expireTime"].text)
    }
    static func deadline(_ text: String?) -> Deadline {
        guard let text = text?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return .unconfirmed }
        let parts = text.prefix(10).split(separator: "-")
        if parts.count == 3, parts[0].count == 4, let month = Int(parts[1]), let day = Int(parts[2]), (1...12).contains(month), (1...31).contains(day) {
            return .monthDay(month: month, day: day)
        }
        return .verbatim(text)
    }
}

/// Source `pages/coop/list` chapter-application legs (`owner-mine` for topic owners, `mine` for merchants).
public struct CoopChapterApplication: Equatable, Identifiable {
    public enum Leg: String, Equatable { case owner, mine }
    public enum Status: String, Equatable { case offerWithdrawn, pendingReview, rejected, offerActive, offerPendingReview, approvedAwaitingSupply }
    public enum Action: String, Equatable { case viewWithdrawal, viewOwned, viewAndSupply }
    public let leg: Leg
    public let applicationID: Int
    public let topicID: Int?
    public let topicName: String?
    public let chapterName: String?
    public let merchantName: String?
    public let status: Status
    /// `source == 1` marks an owner-initiated invitation rather than a merchant application.
    public let invited: Bool
    public var id: String { leg.rawValue + ":" + String(applicationID) }
    public var direction: CooperationDirection { (leg == .owner) != invited ? .received : .sent }
    public var action: Action { status == .offerWithdrawn ? .viewWithdrawal : leg == .owner ? .viewOwned : .viewAndSupply }

    /// The whole leg is rejected when the payload is not a list of objects (source `isRecordList`).
    public static func rows(_ value: CoopFlowJSON, leg: Leg) throws -> [CoopChapterApplication] {
        guard let rows = value.rows else { throw CoopFlowFailure.malformed }
        return try rows.map { row in
            guard case .object = row, let id = row["id"].integer, id > 0 else { throw CoopFlowFailure.malformed }
            return CoopChapterApplication(leg: leg, row: row, id: id)
        }
    }
    init(leg: Leg, row: CoopFlowJSON, id: Int) {
        self.leg = leg; applicationID = id
        topicID = row["topicId"].integer
        topicName = row["topicName"].text.flatMap { $0.isEmpty ? nil : $0 }
        chapterName = row["chapterName"].text.flatMap { $0.isEmpty ? nil : $0 }
        merchantName = row["merchantName"].text.flatMap { $0.isEmpty ? nil : $0 }
        invited = row["source"].integer == 1
        let offerState = row["offerState"].text
        if offerState == "WITHDRAWN" { status = .offerWithdrawn }
        else if row["status"].integer == 0 { status = .pendingReview }
        else if row["status"].integer == 2 { status = .rejected }
        else if row["offerActive"].flag == true { status = .offerActive }
        else if (row["replacementOfOfferId"].integer ?? 0) > 0, (row["offerId"].integer ?? 0) > 0, offerState == "INACTIVE" { status = .offerPendingReview }
        else { status = .approvedAwaitingSupply }
    }
}

public enum CoopListReadFailure {
    /// Source `failureKind`: sign-in / permission style failures. Used to treat the merchant-only `mine`
    /// leg as not applicable for non-merchant accounts instead of surfacing an error.
    public static func isPermission(_ error: Error) -> Bool {
        if error as? APIError == .unauthorized { return true }
        switch error as? CoopFlowFailure {
        case .permission?, .inactiveMerchant?: return true
        case .server(let code, let message)?:
            if code == 401 || code == 403 { return true }
            guard let message else { return false }
            return message.range(of: "请先登录|无权|仅.+可|资格|身份|主理人", options: .regularExpression) != nil
        default: return false
        }
    }
}

/// Deep-link `topicId` / `topicName` filter seed for `pages/coop/list` with clear-filter support.
public struct CoopTopicFilterSeed: Equatable, Sendable {
    public private(set) var topicID: Int?
    public private(set) var topicName: String?

    public init(topicID: Int? = nil, topicName: String? = nil) {
        if let id = topicID, id > 0 {
            self.topicID = id
            let trimmed = topicName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            self.topicName = trimmed.isEmpty ? nil : trimmed
        } else {
            self.topicID = nil
            self.topicName = nil
        }
    }

    public init(rawTopicID: String?, rawTopicName: String? = nil) {
        let parsedID = rawTopicID.flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        self.init(topicID: parsedID, topicName: rawTopicName)
    }

    public var isActive: Bool { topicID != nil }

    public var displayLabel: String? {
        guard let topicID else { return nil }
        if let topicName { return "\(topicName) (#\(topicID))" }
        return "#\(topicID)"
    }

    public mutating func clear() {
        topicID = nil
        topicName = nil
    }

    public func cleared() -> CoopTopicFilterSeed { .init() }

    public func matches(topicID candidate: Int?) -> Bool {
        guard let active = topicID else { return true }
        return candidate == active
    }

    public func filter<Row>(_ rows: [Row], topic: (Row) -> Int?) -> [Row] {
        guard isActive else { return rows }
        return rows.filter { matches(topicID: topic($0)) }
    }
}
