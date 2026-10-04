import Foundation

/// A bounded read-only projection. It never serializes or replaces the original configuration.
public struct TemplatePreferencePreview: Equatable {
    public struct Result: Equatable, Identifiable {
        public let id: String
        public let title: String
        public let body: String
        public let nextStep: String
        public let nextStepDays: Int
    }
    public let dimensions: [String]
    public let results: [Result]
    public let recipientLabel: String?
    public let purpose: String?
    /// Questions, tie-breaking, scoring and extensions remain in the original source only.
    public let isPartial = true
    public init(raw: String) throws {
        guard raw.utf8.count <= 1_048_576, Self.hasBoundedNesting(raw),
              let config = try JSONDecoder().decode(TemplateAuthoringJSON.self, from: Data(raw.utf8)).object,
              let steps = config["steps"]?.array, !steps.isEmpty,
              let dimensions = config["dimensions"]?.array, !dimensions.isEmpty,
              dimensions.allSatisfy({ $0.string != nil }),
              dimensions.count == 1 || (config["tiebreak"] != nil && config["tiebreak"] != .null),
              let results = config["results"]?.object, !results.isEmpty else { throw TemplateAuthoringError.invalidContract }
        self.dimensions = dimensions.compactMap(\.string)
        self.results = try results.keys.sorted().map { code in
            guard let row = results[code]?.object,
                  let title = row["title"]?.string, !title.isEmpty,
                  let body = row["body"]?.string, !body.isEmpty,
                  let nextStep = row["nextStep"]?.string, !nextStep.isEmpty,
                  let days = row["nextStepDays"]?.integer, [7, 30].contains(days) else { throw TemplateAuthoringError.invalidContract }
            return Result(id: code, title: title, body: body, nextStep: nextStep, nextStepDays: days)
        }
        if let output = config["tagOutput"], output != .null {
            guard let object = output.object,
                  let recipient = object["recipientLabel"]?.string, !recipient.isEmpty,
                  let purpose = object["purpose"]?.string, !purpose.isEmpty,
                  object["revocable"] == .bool(true) else { throw TemplateAuthoringError.invalidContract }
            recipientLabel = recipient; self.purpose = purpose
        } else { recipientLabel = nil; purpose = nil }
    }
    private static func hasBoundedNesting(_ raw: String) -> Bool {
        var depth = 0, quoted = false, escaped = false
        for byte in raw.utf8 {
            if quoted {
                if escaped { escaped = false }
                else if byte == 92 { escaped = true }
                else if byte == 34 { quoted = false }
            } else if byte == 34 { quoted = true }
            else if byte == 123 || byte == 91 { depth += 1; if depth > 64 { return false } }
            else if byte == 125 || byte == 93 { depth -= 1; if depth < 0 { return false } }
        }
        return depth == 0 && !quoted
    }

}
