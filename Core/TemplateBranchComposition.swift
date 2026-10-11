import Foundation

/// Coupled branch authoring actions from P036. Graph validation remains unchanged.
public struct TemplateBranchComposition {
    public struct Step: Identifiable, Equatable {
        public let id: String
        public let terminal: Bool
        public let optionCount: Int
    }
    public enum Edit { case addStep(String), terminal(String, Bool), addOption(stepID: String, optionID: String) }
    public static let defaultOutcomeLabel = "完成节点"
    public let steps: [Step]
    public let isSupported: Bool
    public let canEdit: Bool
    public var canAddStep: Bool { canEdit && steps.count < 50 }
    private let fingerprint: Data?

    public init(_ draft: TemplateAdvancedDraft) {
        let values = draft.value["branch"]?.object?["steps"]?.array
        let encoded = Self.snapshot(draft); fingerprint = encoded
        var ids = Set<String>()
        let supported = values != nil && values!.count <= 50 && encoded != nil && values!.allSatisfy { raw in
            guard let row = raw.object, let id = row["id"]?.string, Self.validID(id), ids.insert(id).inserted,
                  case .bool(_)? = row["terminal"],
                  ["title", "body", "outcomeCode", "outcomeLabel"].allSatisfy({ row[$0] == nil || row[$0]?.string != nil }),
                  row["options"] == nil || row["options"]?.array != nil else { return false }
            let options = row["options"]?.array ?? []; var used = Set<String>()
            return options.count <= 12 && options.allSatisfy { raw in
                guard let option = raw.object, let id = option["id"]?.string else { return false }
                return Self.validID(id) && used.insert(id).inserted
            }
        }
        isSupported = supported; canEdit = supported && draft.enabled("branch")
        steps = supported ? values!.map { raw in
            let row = raw.object!
            return .init(id: row["id"]!.string!, terminal: row["terminal"]!.bool, optionCount: row["options"]?.array?.count ?? 0)
        } : []
    }
    public func canAddOption(_ stepID: String) -> Bool { canEdit && steps.contains { $0.id == stepID && $0.optionCount < 12 } }
    public func isCurrent(_ draft: TemplateAdvancedDraft) -> Bool { fingerprint != nil && fingerprint == Self.snapshot(draft) }
    public func applying(_ edit: Edit, to draft: TemplateAdvancedDraft) -> TemplateAdvancedDraft? {
        guard canEdit, isCurrent(draft) else { return nil }
        var rows = draft.rows("branch", "steps")
        switch edit {
        case .addStep(let id):
            guard canAddStep, Self.validID(id), !steps.contains(where: { $0.id == id }) else { return nil }
            rows.append(.object(["id": .string(id), "title": .string(""), "body": .string(""), "terminal": .bool(true),
                "outcomeCode": .string("COMPLETED"), "outcomeLabel": .string(Self.defaultOutcomeLabel), "options": .array([])]))
        case .terminal(let id, let terminal):
            guard let index = steps.firstIndex(where: { $0.id == id }) else { return nil }
            var row = rows[index].object!; row["terminal"] = .bool(terminal)
            if terminal {
                row["options"] = .array([])
                if (row["outcomeCode"]?.string ?? "").isEmpty { row["outcomeCode"] = .string("COMPLETED") }
                if (row["outcomeLabel"]?.string ?? "").isEmpty {
                    let title = row["title"]?.string ?? ""
                    row["outcomeLabel"] = .string(title.isEmpty ? Self.defaultOutcomeLabel : title)
                }
            }
            rows[index] = .object(row)
        case .addOption(let stepID, let optionID):
            guard canAddOption(stepID), Self.validID(optionID), let index = steps.firstIndex(where: { $0.id == stepID }) else { return nil }
            var row = rows[index].object!, options = row["options"]?.array ?? []
            guard !options.contains(where: { $0.object?["id"]?.string == optionID }) else { return nil }
            options.append(.object(["id": .string(optionID), "label": .string(""), "nextStepId": .string(""), "score": .number(0)]))
            row["options"] = .array(options); row["terminal"] = .bool(false); rows[index] = .object(row)
        }
        var next = draft; next.set("branch", "steps", .array(rows)); return next
    }
    private static func validID(_ text: String) -> Bool { text.range(of: TemplateCreatorSchema.keyPattern, options: .regularExpression) != nil }
    private static func snapshot(_ draft: TemplateAdvancedDraft) -> Data? {
        guard let value = draft.value["branch"] else { return nil }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]; return try? encoder.encode(value)
    }
}
