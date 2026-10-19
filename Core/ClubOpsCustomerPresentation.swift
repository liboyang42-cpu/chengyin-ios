import Foundation

/// Mini-program pages/club/customers view-model parity. Phone numbers are only the server-rendered phoneText.
public enum ClubOpsCustomerText {
    public static func trimmed(_ value: ClubGovernanceValue) -> String? {
        guard let text = value.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }
    /// Leading yyyy-MM-dd of the server string; no time zone conversion, matching the mini-program.
    public static func dateParts(_ value: ClubGovernanceValue) -> (year: Int, month: Int, day: Int)? {
        guard let raw = value.string else { return nil }
        let chars = Array(raw.replacingOccurrences(of: "T", with: " "))
        guard chars.count >= 10, chars[4] == "-", chars[7] == "-" else { return nil }
        func digits(_ range: Range<Int>) -> Int? {
            let slice = chars[range]
            guard slice.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
            return Int(String(slice))
        }
        guard let year = digits(0..<4), let month = digits(5..<7), let day = digits(8..<10) else { return nil }
        return (year, month, day)
    }
    public static func monthDay(_ value: ClubGovernanceValue) -> String? {
        guard let parts = dateParts(value) else { return nil }
        return String(format: "%02d-%02d", parts.month, parts.day)
    }
    public static func count(_ value: ClubGovernanceValue) -> Int? {
        guard case .integer(let number) = value, number >= 0 else { return nil }
        return number
    }
}

public enum ClubOpsCustomerMeta: Equatable {
    case pending(count: Int, topic: String?)
    case verified(count: Int, monthDay: String?)
}

public struct ClubOpsCustomerRow: Identifiable, Equatable {
    public let id: Int
    public let displayName: String?
    public let hasRemark: Bool
    public let meta: ClubOpsCustomerMeta
    /// Remark first; otherwise the server-rendered phone line.
    public let subText: String?
}

public struct ClubOpsCustomerListPresentation: Equatable {
    public let total: Int
    public let monthNew: Int
    public let rows: [ClubOpsCustomerRow]
    public init(value: ClubGovernanceValue) throws {
        guard let total = ClubOpsCustomerText.count(value["total"]), let monthNew = ClubOpsCustomerText.count(value["monthNew"]),
              let items = value["items"].array else { throw ClubGovernanceFailure.malformed }
        var rows: [ClubOpsCustomerRow] = [], seen = Set<Int>()
        for item in items {
            guard item.object != nil, let id = ClubCustomerHistoryTopicRoute.positiveID(item["memberId"]), seen.insert(id).inserted,
                  let verified = ClubOpsCustomerText.count(item["verifiedCount"]), let pending = ClubOpsCustomerText.count(item["pendingCount"]) else { throw ClubGovernanceFailure.malformed }
            let remark = ClubOpsCustomerText.trimmed(item["remark"])
            rows.append(.init(id: id, displayName: ClubOpsCustomerText.trimmed(item["displayName"]), hasRemark: remark != nil,
                              meta: pending > 0 ? .pending(count: pending, topic: ClubOpsCustomerText.trimmed(item["lastTopicName"]))
                                               : .verified(count: verified, monthDay: ClubOpsCustomerText.monthDay(item["lastVisitDate"])),
                              subText: remark ?? ClubOpsCustomerText.trimmed(item["phoneText"])))
        }
        self.total = total; self.monthNew = monthNew; self.rows = rows
    }
}

public enum ClubOpsCustomerRecordStatus: String, CaseIterable, Equatable {
    case verified = "VERIFIED", pending = "PENDING", contacted = "CONTACTED", refunded = "REFUNDED", cancelled = "CANCELLED", registered = "REGISTERED"
    public var localizationKey: String { "clubOps.customer.status." + rawValue }
}

public struct ClubOpsCustomerRecord: Identifiable, Equatable {
    public let id: String
    public let topicID: Int?
    public let title: String?
    public let day: Int?
    public let month: Int?
    public let status: ClubOpsCustomerRecordStatus
    /// The exact returned row; topic navigation re-validates it through ClubCustomerHistoryTopicRoute.
    public let source: ClubGovernanceValue
}

public struct ClubOpsCustomerDetailPresentation: Equatable {
    public let memberID: Int
    public let displayName: String?
    public let phoneText: String?
    public let lastInteraction: (month: Int, day: Int)?
    public let remark: String?
    /// nil means the server withheld the amount for this role; never rendered as zero.
    public let paidAmountText: String?
    public let arrivedCount: Int
    public let pendingCount: Int
    public let refundedCount: Int
    public let records: [ClubOpsCustomerRecord]
    public let tags: [String]
    public let canEdit: Bool
    public init(value: ClubGovernanceValue, memberID expected: Int?) throws {
        let summary = value["summary"]
        guard summary.object != nil, let expected, let memberID = ClubCustomerHistoryTopicRoute.positiveID(summary["memberId"]), memberID == expected,
              let arrived = ClubOpsCustomerText.count(summary["arrivedCount"]), let pending = ClubOpsCustomerText.count(summary["pendingCount"]),
              let refunded = ClubOpsCustomerText.count(summary["refundedCount"]),
              let rows = value["records"].array, let rawTags = value["tags"].array else { throw ClubGovernanceFailure.malformed }
        let paid = summary["paidAmount"]
        if paid == .null || paid == .string("") { paidAmountText = nil }
        else {
            guard let amount = paid.number, amount.isFinite, amount >= 0 else { throw ClubGovernanceFailure.malformed }
            paidAmountText = Self.money(amount)
        }
        records = try rows.map { row in
            guard row.object != nil, let key = ClubOpsCustomerText.trimmed(row["key"]),
                  let status = ClubOpsCustomerRecordStatus(rawValue: row["statusCode"].string ?? "") else { throw ClubGovernanceFailure.malformed }
            let parts = ClubOpsCustomerText.dateParts(row["occurredAt"])
            return .init(id: key, topicID: ClubCustomerHistoryTopicRoute.positiveID(row["topicId"]), title: ClubOpsCustomerText.trimmed(row["title"]),
                         day: parts?.day, month: parts?.month, status: status, source: row)
        }
        // Record keys are list identities; a repeated key is a malformed receipt, not two rows.
        guard Set(records.map(\.id)).count == records.count else { throw ClubGovernanceFailure.malformed }
        tags = try rawTags.map { tag in
            guard let name = ClubOpsCustomerText.trimmed(tag) ?? ClubOpsCustomerText.trimmed(tag["name"]) else { throw ClubGovernanceFailure.malformed }
            return name
        }
        self.memberID = memberID
        displayName = ClubOpsCustomerText.trimmed(summary["displayName"])
        phoneText = ClubOpsCustomerText.trimmed(summary["phoneText"])
        lastInteraction = ClubOpsCustomerText.dateParts(summary["lastInteractionTime"]).map { (month: $0.month, day: $0.day) }
        remark = ClubOpsCustomerText.trimmed(value["remark"])
        arrivedCount = arrived; pendingCount = pending; refundedCount = refunded
        canEdit = value["canEdit"] == .bool(true)
    }
    /// Mini-program trimMoney: whole yuan without decimals, otherwise two decimals.
    public static func money(_ amount: Double) -> String {
        if amount.rounded() == amount, amount < 1e15 { return "¥" + String(Int(amount)) }
        return "¥" + String(format: "%.2f", amount)
    }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.memberID == rhs.memberID && lhs.displayName == rhs.displayName && lhs.phoneText == rhs.phoneText &&
        lhs.lastInteraction?.month == rhs.lastInteraction?.month && lhs.lastInteraction?.day == rhs.lastInteraction?.day &&
        lhs.remark == rhs.remark && lhs.paidAmountText == rhs.paidAmountText && lhs.arrivedCount == rhs.arrivedCount &&
        lhs.pendingCount == rhs.pendingCount && lhs.refundedCount == rhs.refundedCount && lhs.records == rhs.records &&
        lhs.tags == rhs.tags && lhs.canEdit == rhs.canEdit
    }
}

/// Inline tag/remark editor over the existing comma-joined draft field (same command fields, same request ID rules).
public struct ClubOpsCustomerTagRemarkDraft: Equatable {
    public enum Issue: String, Equatable {
        case remarkTooLong, tagTooLong, tooManyTags
        public var localizationKey: String { "clubOps.customer.issue." + rawValue }
    }
    public static let maxTags = 8, maxTagLength = 12, maxRemarkLength = 200
    public private(set) var tags: [String]
    public init(tagsText: String) { tags = Self.split(tagsText) }
    public var tagsText: String { tags.joined(separator: ",") }
    static func split(_ text: String) -> [String] {
        var seen = Set<String>()
        return text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty && seen.insert($0).inserted }
    }
    /// Adds a typed tag (commas split it, matching the draft's wire parsing). Rejects without mutating.
    public mutating func add(_ input: String) -> Issue? {
        let added = Self.split(input)
        guard !added.isEmpty else { return nil }
        var next = tags
        for name in added where !next.contains(name) { next.append(name) }
        if let issue = Self.issue(tags: next, remark: "") { return issue }
        tags = next; return nil
    }
    public mutating func remove(at index: Int) {
        guard tags.indices.contains(index) else { return }
        tags.remove(at: index)
    }
    public static func issue(tags: [String], remark: String) -> Issue? {
        if remark.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count > maxRemarkLength { return .remarkTooLong }
        var seen = Set<String>()
        for name in tags.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }) where !name.isEmpty {
            if name.utf16.count > maxTagLength { return .tagTooLong }
            seen.insert(name)
        }
        return seen.count > maxTags ? .tooManyTags : nil
    }
    public static func issue(tagsText: String, remark: String) -> Issue? { issue(tags: split(tagsText), remark: remark) }
}

/// Page-specific failure copy for customers, customer detail and settlement; other reads keep generic copy.
public struct ClubOpsFailureCopy: Equatable {
    public let titleKey: String
    public let detailKey: String?
    public let retryKey: String?
    public init?(operation: ClubGovernanceRead, failure: ClubGovernanceFailure) {
        let forbidden = failure == .forbidden
        switch operation {
        case .customers, .customer:
            if forbidden { titleKey = "clubOps.customers.forbidden"; detailKey = "clubOps.customers.forbiddenDetail"; retryKey = nil }
            else if failure == .signedOut { return nil }
            else {
                titleKey = operation == .customers ? "clubOps.customers.failed" : "clubOps.customer.failed"
                detailKey = nil; retryKey = "clubOps.customers.retry"
            }
        case .settlement:
            guard !forbidden, failure != .signedOut else { return nil }
            titleKey = "clubOps.settlement.failed"; detailKey = nil; retryKey = "clubOps.settlement.retry"
        default: return nil
        }
    }
}
