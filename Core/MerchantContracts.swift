import Foundation

public struct MerchantDashboard: Decodable, Equatable {
    public let revenue: String?
    public let pendingOrders: Int
    public let revenue7d: [MerchantRevenuePoint]
    enum CodingKeys: String, CodingKey { case revenue, pendingOrders, revenue7d }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        revenue = try c.decodeIfPresent(String.self, forKey: .revenue)
        pendingOrders = try c.decodeIfPresent(Int.self, forKey: .pendingOrders) ?? 0
        revenue7d = try c.decodeIfPresent([MerchantRevenuePoint].self, forKey: .revenue7d) ?? []
    }
}

public struct MerchantRevenuePoint: Decodable, Equatable {
    public let date: String
    public let amount: String?
}

public struct MerchantTodo: Decodable, Equatable {
    public let pendingVerify: Int
    public let verifiedCount: Int
    public let pendingScanConfirm: Int
    public let pendingOrders: Int
    public let refundCount: Int
    /// Prediction rounds still awaiting the merchant's answer (mini-program todo-summary).
    /// Expired rounds are no longer reported, so the reminder disappears with zero.
    public let pendingPredict: Int
    public let biddingTopics: Int
    /// nil when the server omits `byProject`: per-project chips are then unknown, not "no todo".
    public let byProject: [MerchantProjectTodo]?
    enum CodingKeys: String, CodingKey { case pendingVerify, verifiedCount, pendingScanConfirm, pendingOrders, refundCount, pendingPredict, biddingTopics, byProject }
    public init(aftercareRefundCount: Int) {
        pendingVerify = 0
        verifiedCount = 0
        pendingScanConfirm = 0
        pendingOrders = 0
        refundCount = max(0, aftercareRefundCount)
        pendingPredict = 0
        biddingTopics = 0
        byProject = nil
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pendingVerify = try c.decodeIfPresent(Int.self, forKey: .pendingVerify) ?? 0
        verifiedCount = try c.decodeIfPresent(Int.self, forKey: .verifiedCount) ?? 0
        pendingScanConfirm = try c.decodeIfPresent(Int.self, forKey: .pendingScanConfirm) ?? 0
        pendingOrders = try c.decodeIfPresent(Int.self, forKey: .pendingOrders) ?? 0
        refundCount = try c.decodeIfPresent(Int.self, forKey: .refundCount) ?? 0
        // Negative or non-integer counts never become a visible reminder.
        pendingPredict = max(0, (try? c.decodeIfPresent(Int.self, forKey: .pendingPredict)) ?? 0)
        biddingTopics = max(0, (try? c.decodeIfPresent(Int.self, forKey: .biddingTopics)) ?? 0)
        byProject = (try? c.decodeIfPresent([MerchantProjectTodo].self, forKey: .byProject)) ?? nil
    }
    /// Non-owner aftercare readers receive only the aftercare refund count; order, verification,
    /// prediction, bidding, and per-project fields stay owner-only.
    public func scoped(for access: MerchantAccess) -> MerchantTodo {
        access.isOwner ? self : Self(aftercareRefundCount: access.canReadAftercare ? refundCount : 0)
    }
    /// Completed verifications are not pending work.
    public var hasPendingWork: Bool { pendingVerify > 0 || pendingScanConfirm > 0 || pendingOrders > 0 || refundCount > 0 }
}

public struct MerchantProjectTodo: Decodable, Equatable {
    /// Source strings are preserved; "01" is not the canonical owner ID "1".
    public let ownerType: String
    public let ownerID: String
    public let pendingVerify: Int
    public let pendingScanConfirm: Int
    enum CodingKeys: String, CodingKey { case ownerType, ownerId, pendingVerify, pendingScanConfirm }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func scalar(_ key: CodingKeys) throws -> String {
            if let value = try? c.decode(String.self, forKey: key) { return value }
            if let value = try? c.decode(Int.self, forKey: key) { return String(value) }
            throw DecodingError.dataCorruptedError(forKey: key, in: c, debugDescription: "Missing project owner")
        }
        ownerType = try scalar(.ownerType); ownerID = try scalar(.ownerId)
        pendingVerify = max(0, (try? c.decodeIfPresent(Int.self, forKey: .pendingVerify)) ?? 0)
        pendingScanConfirm = max(0, (try? c.decodeIfPresent(Int.self, forKey: .pendingScanConfirm)) ?? 0)
    }
}

public struct MerchantEvent: Decodable, Equatable {
    public let content: String
    /// Already rendered by server as MM-dd HH:mm; never reinterpret as a Date.
    public let time: String
    /// Optional ownership metadata for the recent-project activity destination.
    /// Preserve source strings: "01" is not the canonical owner ID "1".
    public let projectOwnerType: String?
    public let projectOwnerID: String?
    public init(content: String, time: String, projectOwnerType: String? = nil, projectOwnerID: String? = nil) {
        self.content = content; self.time = time
        self.projectOwnerType = projectOwnerType; self.projectOwnerID = projectOwnerID
    }
    private enum CodingKeys: String, CodingKey { case content, time, ownerType, ownerId }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        content = try c.decode(String.self, forKey: .content)
        time = try c.decode(String.self, forKey: .time)
        func scalar(_ key: CodingKeys) -> String? {
            if let value = try? c.decode(String.self, forKey: key) { return value }
            if let value = try? c.decode(Int.self, forKey: key) { return String(value) }
            return nil
        }
        projectOwnerType = scalar(.ownerType); projectOwnerID = scalar(.ownerId)
    }
}

public enum MerchantOrderStatus: Int, CaseIterable {
    case awaitingPayment = 0, awaitingShipment, shipped, awaitingReview, completed, closed, invalid
    public var titleKey: String { "merchant.order.status.\(rawValue)" }
}
public enum MerchantAftersaleStatus: Int, CaseIterable {
    case none = 1, processing, refunding, refunded
    public var titleKey: String { "merchant.order.aftersale.\(rawValue)" }
}
public struct MerchantOrderFilter: Equatable {
    public var status: MerchantOrderStatus?
    public var aftersaleStatus: MerchantAftersaleStatus?
    public init(status: MerchantOrderStatus? = nil, aftersaleStatus: MerchantAftersaleStatus? = nil) {
        self.status = status; self.aftersaleStatus = aftersaleStatus
    }
}

public struct MerchantOrder: Decodable, Equatable {
    public let id: Int?
    public let orderSn: String?
    public let status: Int?
    public let aftersaleStatus: Int?
    public let createTime: String?
    public let payAmount: String?
    enum CodingKeys: String, CodingKey { case id, orderSn, status, aftersaleStatus, createTime, payAmount }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.merchantInteger(.id)
        orderSn = try c.decodeIfPresent(String.self, forKey: .orderSn)
        status = try c.decodeIfPresent(Int.self, forKey: .status)
        aftersaleStatus = try c.decodeIfPresent(Int.self, forKey: .aftersaleStatus)
        createTime = try c.decodeIfPresent(String.self, forKey: .createTime)
        if let text = try? c.decode(String.self, forKey: .payAmount) { payAmount = text }
        else if let number = try? c.decode(Decimal.self, forKey: .payAmount) { payAmount = NSDecimalNumber(decimal: number).stringValue }
        else { payAmount = nil }
    }
}

/// Snapshot from project/my, not an invented project detail response.
public struct MerchantProject: Decodable, Equatable, Identifiable {
    public var id: String { "\(bizType):\(projectID)" }
    public let projectID: Int
    public let bizType: String
    public let title: String
    public let state: String?
    public let ownerType: String?
    public let addressName: String?
    public let pendingVerifyCount: Int?
    public let projectTypeText: String?
    public let stateText: String?
    public let acceptStatusText: String?
    public let startTime: String?
    public let endTime: String?
    public let signupCount: Int
    public let viewCount: Int
    enum CodingKeys: String, CodingKey {
        case id, bizType, title, projectTypeText, stateText, acceptStatusText, startTime, endTime, signupCount, viewCount
        case state, ownerType, addressName, pendingVerifyCount
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = c.merchantInteger(.id), id > 0 else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: c, debugDescription: "Invalid project ID")
        }
        projectID = id
        bizType = try c.decode(String.self, forKey: .bizType)
        state = try c.decodeIfPresent(String.self, forKey: .state)
        ownerType = try c.decodeIfPresent(String.self, forKey: .ownerType)
        addressName = try c.decodeIfPresent(String.self, forKey: .addressName)
        pendingVerifyCount = try c.decodeIfPresent(Int.self, forKey: .pendingVerifyCount)
        if let pendingVerifyCount, pendingVerifyCount < 0 {
            throw DecodingError.dataCorruptedError(forKey: .pendingVerifyCount, in: c, debugDescription: "Invalid pending verification count")
        }
        title = try c.decodeIfPresent(String.self, forKey: .title)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        projectTypeText = try c.decodeIfPresent(String.self, forKey: .projectTypeText)
        stateText = try c.decodeIfPresent(String.self, forKey: .stateText)
        acceptStatusText = try c.decodeIfPresent(String.self, forKey: .acceptStatusText)
        startTime = try c.decodeIfPresent(String.self, forKey: .startTime)
        endTime = try c.decodeIfPresent(String.self, forKey: .endTime)
        signupCount = try c.decodeIfPresent(Int.self, forKey: .signupCount) ?? 0
        viewCount = try c.decodeIfPresent(Int.self, forKey: .viewCount) ?? 0
    }
}

public struct MerchantProjectPage: Decodable, Equatable {
    public let rows: [MerchantProject]
    public let total: Int
    enum CodingKeys: String, CodingKey { case rows, total }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rows = try c.decode([MerchantProject].self, forKey: .rows)
        let reported = c.merchantInteger(.total)
        total = reported.flatMap { $0 >= 0 ? $0 : nil } ?? rows.count
    }
    public var hasUnloadedRows: Bool { total > rows.count }
}

/// Flutter merchant_money.dart explicitly identifies this domain as CNY.
/// Decimal normalization avoids a binary floating-point roundtrip. Absence is not zero.
public enum MerchantMoney {
    public static func display(_ raw: String?) -> String {
        guard let raw else { return "—" }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.range(of: #"^[+-]?[0-9]+(?:\.[0-9]+)?$"#, options: .regularExpression) != nil,
              var amount = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")), !amount.isNaN else { return "—" }
        var rounded = Decimal()
        NSDecimalRound(&rounded, &amount, 2, .plain)
        var result = NSDecimalNumber(decimal: rounded).stringValue
        if !result.contains(".") { result += ".00" }
        else if result.split(separator: ".", omittingEmptySubsequences: false).last?.count == 1 { result += "0" }
        return "¥" + result
    }
}
