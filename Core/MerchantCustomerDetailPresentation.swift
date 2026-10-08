import Foundation

/// Read-only projection of the existing customer detail response. The document
/// retains its unmodified payload for exact write-review baselines.
public struct MerchantCustomerDetailPresentation: Equatable {
    public enum EventKind: String, CaseIterable {
        case registered = "REGISTERED", arrived = "ARRIVED", refunded = "REFUNDED"
        case note = "NOTE", correction = "NOTE_CORRECTION", campaign = "CAMPAIGN"
        public var isParticipation: Bool { [.registered, .arrived, .refunded].contains(self) }
        public var isNote: Bool { self == .note || self == .correction }
        public var titleKey: String { "merchant.customerDetail.event." + rawValue }
    }
    public struct Event: Equatable, Identifiable {
        public let id: Int
        public let record: MerchantBusinessRecord
        public let kind: EventKind
        public let occurredAt: Date?
        public var description: String? { record.fields.mbText("description") }
    }
    public struct Participation: Equatable, Identifiable {
        public let id: String
        public let events: [Event]
        /// Missing time or a tied latest instant prevents a latest-state claim.
        public var latest: Event? { MerchantCustomerDetailPresentation.unambiguousLatest(events) }
        public var title: String? {
            let raw = (latest ?? events.first)?.description?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard var text = raw, !text.isEmpty else { return nil }
            if text.hasPrefix("「") { text.removeFirst() }
            if text.hasSuffix("」") { text.removeLast() }
            return text.isEmpty ? nil : text
        }
    }
    public struct SystemTag: Equatable, Identifiable {
        public let id: String
        public let label: String
    }
    public let customer: MerchantBusinessRecord
    public let systemTags: [SystemTag]
    public let merchantTags: [MerchantBusinessRecord]
    public let participation: [Participation]
    public let history: [Event]
    public let lastInteractionAt: Date?
    public var latestNote: Event? { Self.unambiguousLatest(history.filter { $0.kind.isNote }) }
    public var hasNotes: Bool { history.contains { $0.kind.isNote } }

    public init(customerID: MerchantCustomerID, payload: MerchantBusinessValue) throws {
        guard let object = payload.object else { throw MerchantBusinessFailure.malformed }
        let summary = try object.mbObject("summary")
        guard try summary.mbInt("customerMemberId", minimum: 1) == customerID.rawValue else { throw MerchantBusinessFailure.malformed }
        customer = try .init(kind: .customer, fields: summary)
        guard customer.id == String(customerID.rawValue) else { throw MerchantBusinessFailure.malformed }
        lastInteractionAt = MerchantCustomerDetailTime.date(summary["lastInteractionTime"]?.string)
        systemTags = try object.mbObjects("systemTags").map { tag in
            let code = try tag.mbRequiredText("code")
            guard ["ARRIVED", "REPEAT", "PENDING", "REFUNDED"].contains(code) else { throw MerchantBusinessFailure.malformed }
            return SystemTag(id: code, label: try tag.mbRequiredText("label"))
        }
        guard Set(systemTags.map(\.id)).count == systemTags.count else { throw MerchantBusinessFailure.malformed }
        merchantTags = try object.mbObjects("merchantTags").map { try .init(kind: .tag, fields: $0) }
        _ = try MerchantBusinessSection("tags", rows: merchantTags)

        var groups: [String: [Event]] = [:], groupOrder: [String] = [], other: [Event] = []
        var historyKeys = Set<String>()
        for (index, fields) in try object.mbObjects("timeline").enumerated() {
            let record = try MerchantBusinessRecord(kind: .timeline, fields: fields)
            guard let kind = EventKind(rawValue: try fields.mbRequiredText("type")) else { throw MerchantBusinessFailure.malformed }
            let event = Event(id: index, record: record, kind: kind, occurredAt: MerchantCustomerDetailTime.date(fields["occurredAt"]?.string))
            if kind.isParticipation {
                // Only source registration keys may combine facts. An unrelated
                // key stays a separate occurrence, even when repeated.
                let isRegistration = record.id.range(of: #"^registration-[0-9]+$"#, options: .regularExpression) != nil
                let key = isRegistration ? "registration:" + record.id : "event:\(index)"
                if groups[key] == nil { groupOrder.append(key) }
                groups[key, default: []].append(event)
            } else {
                // Notes/corrections/campaign receipts never merge. Duplicate IDs
                // remain malformed rather than dropping or fabricating a receipt.
                guard historyKeys.insert(record.id).inserted else { throw MerchantBusinessFailure.malformed }
                other.append(event)
            }
        }
        participation = groupOrder.map { Participation(id: $0, events: Self.sorted(groups[$0] ?? [])) }
            .sorted { lhs, rhs in
                Self.precedes(lhs.events.first, rhs.events.first)
            }
        history = Self.sorted(other)
    }

    private static func sorted(_ events: [Event]) -> [Event] {
        events.sorted { precedes($0, $1) }
    }
    private static func precedes(_ lhs: Event?, _ rhs: Event?) -> Bool {
        guard let lhs, let rhs else { return lhs != nil }
        switch (lhs.occurredAt, rhs.occurredAt) {
        case let (a?, b?) where a != b: return a > b
        case (_?, nil): return true
        case (nil, _?): return false
        default: return lhs.id < rhs.id
        }
    }
    private static func unambiguousLatest(_ events: [Event]) -> Event? {
        guard !events.isEmpty, events.allSatisfy({ $0.occurredAt != nil }),
              let candidate = sorted(events).first, let instant = candidate.occurredAt,
              events.filter({ $0.occurredAt == instant }).count == 1 else { return nil }
        return candidate
    }
}

public enum MerchantCustomerDetailTime {
    /// The source DTO uses Date and the mini-program explicitly accepts offset
    /// ISO and Shanghai civil strings. Unsupported values stay unknown.
    public static func date(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let date = try? MerchantAftercareTime.parse(text) { return date }
        guard text.range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(?:\.[0-9]{1,3})?(?:Z|[+-](?:0[0-9]|1[0-3]):[0-5][0-9]|[+-]14:00)$"#, options: .regularExpression) != nil,
              (try? MerchantAftercareTime.parse(String(text.prefix(19)).replacingOccurrences(of: "T", with: " "))) != nil else { return nil }
        return OrderLifecycleTime.date(text)
    }
    public static func display(_ date: Date, phoneTimeZone: TimeZone) -> String {
        MerchantAftercareTime.event(date, phoneTimeZone: phoneTimeZone)
    }
}
