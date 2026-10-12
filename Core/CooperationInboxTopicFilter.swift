import Foundation

/// Display-only selection. Never grants authority or changes a read/write request.
public struct CooperationInboxTopicFilter: Equatable {
    public struct Option: Identifiable, Equatable {
        public let id: Int
        public let name: String?
        public init(id: Int, name: String?) { self.id = id; self.name = name }
    }
    public let topicID: Int
    private let owner: ObjectIdentifier
    private let scope: UUID
    public init?(topicID: Int, inbox: CooperationInbox, owner: ObjectIdentifier, scope: UUID) {
        guard Self.options(in: inbox).contains(where: { $0.id == topicID }) else { return nil }
        self.topicID = topicID; self.owner = owner; self.scope = scope
    }
    public func selectedTopic(owner: ObjectIdentifier, scope: UUID) -> Int? {
        self.owner == owner && self.scope == scope ? topicID : nil
    }
    /// Choices come only from the successfully loaded source sections. Failures stay failures.
    public static func options(in inbox: CooperationInbox) -> [Option] {
        var names: [Int: String] = [:]
        var ids = Set<Int>()
        func append(_ id: Int?, _ name: String? = nil) {
            guard let id, id > 0 else { return }
            ids.insert(id)
            if names[id] == nil, let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { names[id] = name }
        }
        if case .content(let list) = inbox.invitations {
            for row in list.received + list.sent { append(row.topicId) }
        }
        if case .content(let rows) = inbox.applications {
            for row in rows { append(row.topicId, row.topicName) }
        }
        if let registrations = inbox.registrations, case .content(let page) = registrations {
            for row in page.rows { append(row.topicId, row.topicName) }
        }
        return ids.sorted().map { Option(id: $0, name: names[$0]) }
    }
    /// Retain source ordinals and duplicate rows; nil topic rows are excluded only when scoped.
    public static func visibleRows<Row>(_ rows: [Row], topicID: Int?, topic: (Row) -> Int?) -> [(offset: Int, element: Row)] {
        rows.enumerated().filter { topicID == nil || topic($0.element) == topicID }
    }
}
