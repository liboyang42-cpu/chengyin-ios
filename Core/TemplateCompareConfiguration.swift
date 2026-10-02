import Foundation

extension TemplateAdvancedDraft {
    /// Matches the server's public configuration allowlist. This is a question
    /// preview, not a runtime receipt; answer, XP and effects never cross it.
    public func comparePublicConfiguration() throws -> TemplateAuthoringJSON {
        guard enabled("compare") else { return .object(["enabled": .bool(false)]) }
        guard creatorIssues(.compare).isEmpty else { throw TemplateAuthoringError.invalidDraft }
        let fields = value["compare"]?.object ?? [:]
        func side(_ name: String) -> TemplateAuthoringJSON {
            let raw = fields[name]?.object ?? [:]
            let rows = (raw["items"]?.array ?? []).map { item -> TemplateAuthoringJSON in
                let row = item.object ?? [:]
                return .object(["id": row["id"] ?? .null, "time": row["time"] ?? .null, "text": row["text"] ?? .null])
            }
            return .object(["label": raw["label"] ?? .null, "items": .array(rows)])
        }
        return .object(["enabled": .bool(true), "prompt": fields["prompt"] ?? .null,
            "maxAttempts": .number(fields["maxAttempts"]?.number ?? 0), "left": side("left"), "right": side("right")])
    }
}
