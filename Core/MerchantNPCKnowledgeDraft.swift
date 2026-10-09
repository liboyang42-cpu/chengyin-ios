import Foundation

/// Local, unapproved form state. It is deliberately not Codable: UUIDs and incomplete
/// fields cannot become a server payload through synthesized encoding or decoding.
/// No legacy free-text knowledge, profile, owner identity or runtime grants are imported.
public struct MerchantNPCKnowledgeDraft: Equatable {
    public struct Product: Equatable, Identifiable {
        public let id = UUID()
        public var name = ""
        public var priceMinor = ""
        public var currency = ""
        public init(name: String = "", priceMinor: String = "", currency: String = "") {
            self.name = name; self.priceMinor = priceMinor; self.currency = currency
        }
    }
    public struct Hours: Equatable, Identifiable {
        public let id = UUID()
        public var day = 1
        public var opens = ""
        public var closes = ""
        public var timeZone = ""
        public init(day: Int = 1, opens: String = "", closes: String = "", timeZone: String = "") {
            self.day = day; self.opens = opens; self.closes = closes; self.timeZone = timeZone
        }
    }
    public struct Promotion: Equatable, Identifiable {
        public let id = UUID()
        public var title = ""
        public var startsAt = ""
        public var endsAt = ""
        public init(title: String = "", startsAt: String = "", endsAt: String = "") {
            self.title = title; self.startsAt = startsAt; self.endsAt = endsAt
        }
    }
    public struct FAQ: Equatable, Identifiable {
        public let id = UUID()
        public var question = ""
        public var answer = ""
        public init(question: String = "", answer: String = "") { self.question = question; self.answer = answer }
    }
    public struct NeverSay: Equatable, Identifiable {
        public let id = UUID()
        public var text = ""
        public init(text: String = "") { self.text = text }
    }
    public var products: [Product] = []
    public var hours: [Hours] = []
    public var promotions: [Promotion] = []
    public var faq: [FAQ] = []
    public var neverSay: [NeverSay] = []
    public init() {}
    public var isEmpty: Bool { products.isEmpty && hours.isEmpty && promotions.isEmpty && faq.isEmpty && neverSay.isEmpty }

    /// Exact structural whitelist, used only to check a local draft's size and shape.
    /// This is not a request, a canonical server hash, a privacy check or an approval.
    /// There is no raw-JSON import route and therefore no ignored/duplicate input keys.
    public func validatedPublicFactsJSON() throws -> Data {
        let issues = fieldIssues
        guard issues.isEmpty else { throw MerchantNPCKnowledgeValidationError(issues: issues) }
        let value: [String: Any] = [
            "schemaVersion": 1,
            "products": products.map { ["name": $0.name, "priceMinor": Int64($0.priceMinor)!, "currency": $0.currency] as [String: Any] },
            "hours": hours.map { ["day": $0.day, "opens": $0.opens, "closes": $0.closes, "timeZone": $0.timeZone] as [String: Any] },
            "promotions": promotions.map { ["title": $0.title, "startsAt": $0.startsAt, "endsAt": $0.endsAt] },
            "faq": faq.map { ["question": $0.question, "answer": $0.answer] },
            "neverSay": neverSay.map(\.text)
        ]
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
        guard data.count <= 16_000 else { throw MerchantNPCKnowledgeValidationError(issues: [.init(section: .draft, kind: .byteLimit)]) }
        return data
    }
    public var validationIssues: [MerchantNPCKnowledgeIssue] {
        do { _ = try validatedPublicFactsJSON(); return [] }
        catch let error as MerchantNPCKnowledgeValidationError { return error.issues }
        catch { return [.init(section: .draft, kind: .encoding)] }
    }
}

public struct MerchantNPCKnowledgeIssue: Equatable {
    public enum Section: String { case draft, products, hours, promotions, faq, neverSay }
    public enum Kind: String { case count, text, price, currency, day, duplicateDay, clock, timeZone, instant, order, byteLimit, encoding }
    public let section: Section
    /// Zero-based row; no untrusted field content is included in an error or log.
    public let row: Int?
    public let field: String?
    public let kind: Kind
    public var messageKey: String { "merchantKnowledge.error." + kind.rawValue }
    public init(section: Section, row: Int? = nil, field: String? = nil, kind: Kind) {
        self.section = section; self.row = row; self.field = field; self.kind = kind
    }
}
public struct MerchantNPCKnowledgeValidationError: Error, Equatable {
    public let issues: [MerchantNPCKnowledgeIssue]
    public init(issues: [MerchantNPCKnowledgeIssue]) { self.issues = issues }
}
