import Foundation

/// Read-only facts from the existing merchant aftercare detail. A merchant opinion
/// never changes the platform outcome. Source civil timestamps are parsed into instants.
public struct MerchantAftercareProgress: Equatable {
    public enum Processing: String, CaseIterable {
        case waiting = "WAITING_PLATFORM_REVIEW", rejected = "PLATFORM_REJECTED"
        case refunding = "REFUND_PROCESSING", manualPending = "MANUAL_REFUND_PENDING"
        case manualReview = "MANUAL_REFUND_REVIEW", refunded = "REFUNDED", unknown = "UNKNOWN"
    }
    public enum Opinion: String, CaseIterable { case pending = "PENDING", agree = "AGREE", reject = "REJECT" }
    public enum Funds: String { case confirmed, unconfirmed }
    public enum Decision: String { case agree = "AGREE", reject = "REJECT", evidence = "EVIDENCE" }
    public enum Evidence: String { case none, recorded, unavailable, notProvided }
    public struct Response: Equatable, Identifiable {
        public let id: Int
        public let decision: Decision
        public let actorKey: String
        public let content: String?
        public let occurredAt: Date?
        public let evidence: Evidence
    }
    public struct Event: Equatable, Identifiable {
        public enum Kind: Equatable { case requested, response(Response), platformTakeover }
        public let id: String
        public let kind: Kind
        public let occurredAt: Date?
    }
    public let refundID: Int
    public let refundNumber, activityTitle, customerNickname, reason, sourceType: String?
    public let sourceID: Int?
    public let amount: MerchantBusinessMoney
    public let processing: Processing
    public let opinion: Opinion
    public let createdAt, platformTakeoverAt, refundDeadline: Date?
    public let policyCode: String?
    public let policyVersion: Int?
    public let responses: [Response]
    public var funds: Funds { processing == .refunded ? .confirmed : .unconfirmed }

    /// No inferred dates, countdown, ETA or future milestones. Response order is
    /// preserved; the separately recorded takeover is inserted by known timestamps.
    public var events: [Event] {
        var result = [Event(id: "request", kind: .requested, occurredAt: createdAt)]
        var takeoverPlaced = platformTakeoverAt == nil
        for response in responses {
            if !takeoverPlaced, let takeover = platformTakeoverAt, let time = response.occurredAt, time > takeover {
                result.append(Event(id: "takeover", kind: .platformTakeover, occurredAt: takeover))
                takeoverPlaced = true
            }
            result.append(Event(id: "response:\(response.id)", kind: .response(response), occurredAt: response.occurredAt))
        }
        if !takeoverPlaced {
            result.append(Event(id: "takeover", kind: .platformTakeover, occurredAt: platformTakeoverAt))
        }
        return result
    }

    public init(refundID: Int, fields: MerchantBusinessObject) throws {
        guard refundID > 0, try fields.mbInt("refundId", minimum: 1) == refundID,
              let processing = Processing(rawValue: try fields.mbRequiredText("processing")),
              let opinion = Opinion(rawValue: try fields.mbRequiredText("merchantOpinion")) else { throw MerchantBusinessFailure.malformed }
        self.refundID = refundID; self.processing = processing; self.opinion = opinion
        // DetailVO does not currently contain refunded. If a future response includes
        // that advisory bit, it must be typed and agree with the server processing state.
        if let value = fields["refunded"], value != .null {
            guard let bit = value.bool, bit == (processing == .refunded) else { throw MerchantBusinessFailure.malformed }
        }
        refundNumber = try Self.text(fields, "refundNo")
        activityTitle = try Self.text(fields, "activityTitle")
        customerNickname = try Self.text(fields, "customerNickname")
        reason = try Self.text(fields, "reason")
        sourceType = try Self.text(fields, "sourceType")
        if let value = fields["sourceId"], value != .null {
            sourceID = try fields.mbInt("sourceId", minimum: 1)
        } else { sourceID = nil }
        amount = try MerchantBusinessMoney(fields["refundAmount"])
        if let raw = amount.raw {
            guard let number = Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX")), number >= 0 else { throw MerchantBusinessFailure.malformed }
        }
        createdAt = try Self.timestamp(fields, "createTime")
        platformTakeoverAt = try Self.timestamp(fields, "platformTakeoverAt")
        refundDeadline = try Self.timestamp(fields, "refundDeadline")
        policyCode = try Self.text(fields, "refundPolicyCode")
        if let value = fields["refundPolicyVersion"], value != .null {
            policyVersion = try fields.mbInt("refundPolicyVersion", minimum: 1)
        } else { policyVersion = nil }
        var seen = Set<Int>()
        responses = try fields.mbObjects("responses").map { row in
            let id = try row.mbInt("id", minimum: 1)
            guard seen.insert(id).inserted, try row.mbInt("refundId", minimum: 1) == refundID,
                  let decision = Decision(rawValue: try row.mbRequiredText("decision")) else { throw MerchantBusinessFailure.malformed }
            let actor = try Self.text(row, "actorRoleCode")
            let known = ["MERCHANT_OWNER", "MERCHANT_MANAGER", "MERCHANT_CHECKIN", "MERCHANT_MARKETING", "MERCHANT_FINANCE"]
            let actorKey = "merchant.aftercareProgress.actor." + (actor.flatMap { known.contains($0) ? $0 : nil } ?? "unknown")
            let evidence: Evidence
            switch try Self.text(row, "evidenceStatus") {
            case nil: evidence = .notProvided
            case "NONE": evidence = .none
            case "AVAILABLE": evidence = .recorded
            default: evidence = .unavailable
            }
            // Signed URLs, member IDs and request IDs are deliberately not copied.
            return Response(id: id, decision: decision, actorKey: actorKey, content: try Self.text(row, "content"),
                            occurredAt: try Self.timestamp(row, "createTime"), evidence: evidence)
        }
    }
    private static func text(_ fields: MerchantBusinessObject, _ key: String) throws -> String? {
        guard let value = fields[key], value != .null else { return nil }
        guard let text = value.string else { throw MerchantBusinessFailure.malformed }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
    private static func timestamp(_ fields: MerchantBusinessObject, _ key: String) throws -> Date? {
        guard let text = try text(fields, key) else { return nil }
        return try MerchantAftercareTime.parse(text)
    }
}

/// ApplicationConfig pins Jackson to Asia/Shanghai; DetailVO uses this exact bare
/// timestamp format. Ordinary records follow the phone zone, deadlines stay Beijing.
public enum MerchantAftercareTime {
    public static var beijing: TimeZone { TimeZone(identifier: "Asia/Shanghai")! }
    public static func parse(_ raw: String) throws -> Date {
        guard raw.range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$"#, options: .regularExpression) != nil else { throw MerchantBusinessFailure.malformed }
        let formatter = formatter(timeZone: beijing, includeOffset: false)
        guard let date = formatter.date(from: raw), formatter.string(from: date) == raw else { throw MerchantBusinessFailure.malformed }
        return date
    }
    public static func event(_ date: Date, phoneTimeZone: TimeZone) -> String {
        formatter(timeZone: phoneTimeZone, includeOffset: true).string(from: date)
    }
    public static func deadline(_ date: Date) -> String {
        formatter(timeZone: beijing, includeOffset: false).string(from: date)
    }
    private static func formatter(timeZone: TimeZone, includeOffset: Bool) -> DateFormatter {
        let value = DateFormatter()
        value.locale = Locale(identifier: "en_US_POSIX")
        value.calendar = Calendar(identifier: .gregorian)
        value.timeZone = timeZone
        value.dateFormat = includeOffset ? "yyyy-MM-dd HH:mm:ss XXX" : "yyyy-MM-dd HH:mm:ss"
        value.isLenient = false
        return value
    }
}
