import Foundation

/// Local composition state over the existing multiplayer roles and turnOrder wire fields.
public struct TemplateMultiplayerPlan {
    public struct Role: Identifiable {
        public let id: UUID
        fileprivate var value: [String: TemplateAuthoringJSON]
        public fileprivate(set) var minimumText: String
        public fileprivate(set) var maximumText: String
        public var wireID: String { value["id"]?.string ?? "" }
        public var label: String { value["label"]?.string ?? "" }
        fileprivate init(_ value: [String: TemplateAuthoringJSON]) {
            id = UUID(); self.value = value
            minimumText = Self.text(value["min"]); maximumText = Self.text(value["max"])
        }
        private static func text(_ value: TemplateAuthoringJSON?) -> String {
            if let text = value?.string { return text }
            guard let number = value?.number else { return "" }
            return number.rounded() == number ? String(format: "%.0f", number) : String(number)
        }
    }
    public struct Turn: Identifiable {
        public let id: Int
        public let roleID: String
        public let labels: [String]
        public var resolvesUniquely: Bool { labels.count == 1 }
    }
    public enum Field: Equatable { case identifier, label, minimum, maximum }
    public enum Edit { case add, text(UUID, Field, String), remove(UUID), move(UUID, Int), order(String) }
    public struct Update { public let draft: TemplateAdvancedDraft; public let plan: TemplateMultiplayerPlan }
    public private(set) var roles: [Role]
    public private(set) var orderText: String
    private var order: [String]
    public let isSupported: Bool
    public let canEdit: Bool
    public var canAdd: Bool { canEdit && roles.count < 20 }
    public var turns: [Turn] { order.enumerated().map { index, key in .init(id: index, roleID: key, labels: roles.filter { $0.wireID == key }.map(\.label)) } }
    private var fingerprint: Data?
    public init(_ draft: TemplateAdvancedDraft) {
        let fields = draft.value["multiplayer"]?.object, rows = fields?["roles"]?.array, rawOrder = fields?["turnOrder"]?.array, encoded = Self.snapshot(draft)
        let supported = rows != nil && rawOrder != nil && (rows?.count ?? 0) <= 20 && encoded != nil && (rawOrder ?? []).allSatisfy { $0.string != nil } && (rows ?? []).allSatisfy { raw in
            guard let row = raw.object else { return false }
            for key in ["id", "label"] where row[key] != nil && row[key]?.string == nil { return false }
            for key in ["min", "max"] {
                if let value = row[key], value.string == nil && value.number == nil { return false }
            }
            return true
        }
        fingerprint = encoded; isSupported = supported; canEdit = supported && draft.enabled("multiplayer")
        roles = supported ? (rows ?? []).map { Role($0.object!) } : []
        let parsed = supported ? (rawOrder ?? []).compactMap(\.string) : []
        order = parsed; orderText = parsed.joined(separator: ", ")
    }
    /// Matches the actual Mini /[,，\s]+/ delimiter set, including BOM but not NEL.
    public static func parseOrder(_ text: String) -> [String] {
        let separators = CharacterSet(charactersIn: ",，\t\n\u{000B}\u{000C}\r \u{00A0}\u{1680}\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}\u{2006}\u{2007}\u{2008}\u{2009}\u{200A}\u{2028}\u{2029}\u{202F}\u{205F}\u{3000}\u{FEFF}")
        return text.components(separatedBy: separators).filter { !$0.isEmpty }
    }
    public func isCurrent(_ draft: TemplateAdvancedDraft) -> Bool { fingerprint != nil && fingerprint == Self.snapshot(draft) }
    public func applying(_ edit: Edit, to draft: TemplateAdvancedDraft) -> Update? {
        guard canEdit, isCurrent(draft) else { return nil }
        var plan = self, next = draft
        switch edit {
        case .order(let text):
            plan.orderText = text; plan.order = Self.parseOrder(text)
            next.set("multiplayer", "turnOrder", .array(plan.order.map { .string($0) }))
        case .add:
            guard canAdd else { return nil }
            let used = Set(roles.map(\.wireID)); var key: String
            repeat { key = "role_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased() } while used.contains(key)
            plan.roles.append(Role(["id": .string(key), "label": .string(""), "min": .number(0), "max": .number(1)]))
        case .text(let id, let field, let text):
            guard let index = plan.roles.firstIndex(where: { $0.id == id }) else { return nil }
            switch field {
            case .identifier: plan.roles[index].value["id"] = .string(text)
            case .label: plan.roles[index].value["label"] = .string(text)
            case .minimum, .maximum:
                let parsed = Double(text.trimmingCharacters(in: .whitespacesAndNewlines))
                let value: TemplateAuthoringJSON
                if let parsed, parsed.isFinite { value = .number(parsed) } else { value = .string(text) }
                plan.roles[index].value[field == .minimum ? "min" : "max"] = value
                if field == .minimum { plan.roles[index].minimumText = text } else { plan.roles[index].maximumText = text }
            }
        case .remove(let id):
            guard let index = plan.roles.firstIndex(where: { $0.id == id }) else { return nil }; plan.roles.remove(at: index)
        case .move(let id, let offset):
            guard offset == -1 || offset == 1, let index = plan.roles.firstIndex(where: { $0.id == id }), plan.roles.indices.contains(index + offset) else { return nil }
            let row = plan.roles.remove(at: index); plan.roles.insert(row, at: index + offset)
        }
        if case .order = edit {} else { next.set("multiplayer", "roles", .array(plan.roles.map { .object($0.value) })) }
        plan.fingerprint = Self.snapshot(next); return .init(draft: next, plan: plan)
    }
    private static func snapshot(_ draft: TemplateAdvancedDraft) -> Data? {
        guard let value = draft.value["multiplayer"] else { return nil }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]; return try? encoder.encode(value)
    }
}
