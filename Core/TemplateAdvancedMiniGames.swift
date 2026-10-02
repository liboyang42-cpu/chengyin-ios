import Foundation

/// Creator-only source contracts. Secret answer keys stay in the authoring draft;
/// the preview projection deliberately removes them before rendering player controls.
extension TemplateAdvancedGame {
    public var isReasoning: Bool { [.sort, .match, .classify].contains(self) }
    public var isMiniProgramAddition: Bool { isReasoning || self == .compass || self == .shout }
    public var allowsInline: Bool { [.dice, .quiet, .sort, .match, .classify].contains(self) }
}

extension TemplateAdvancedDraft {
    public static let miniGameDefaults: [String: TemplateAuthoringJSON] = [
        "sort": .object(["enabled": .bool(false), "prompt": .string(""), "items": rows("item", count: 3), "answerOrder": .array([.string("item_1"), .string("item_2"), .string("item_3")])]),
        "match": .object(["enabled": .bool(false), "prompt": .string(""), "left": rows("left", count: 2), "right": rows("right", count: 2), "pairs": .array([.array([.string("left_1"), .string("right_1")]), .array([.string("left_2"), .string("right_2")])])]),
        "classify": .object(["enabled": .bool(false), "prompt": .string(""), "bins": rows("bin", count: 2), "items": rows("item", count: 2), "answer": .object(["item_1": .string("bin_1"), "item_2": .string("bin_2")])]),
        "compass": .object(["enabled": .bool(false), "kicker": .string(""), "bearing": .string(""), "tolerance": .number(15), "holdSeconds": .number(3), "hint": .string(""), "xp": .number(0)]),
        "shout": .object(["enabled": .bool(false), "kicker": .string(""), "seconds": .number(5), "xp": .number(10)])
    ]
    private static func rows(_ prefix: String, count: Int) -> TemplateAuthoringJSON {
        .array((1...count).map { .object(["id": .string("\(prefix)_\($0)"), "label": .string("")]) })
    }
    public var explicitPresentation: String { value["present"]?.string ?? "" }
    public mutating func setPresentation(_ value: String) {
        self.value["present"] = value.isEmpty ? nil : .string(value)
    }
    public func rows(_ section: String, _ field: String) -> [TemplateAuthoringJSON] { value[section]?.object?[field]?.array ?? [] }
    public mutating func setRow(_ section: String, _ field: String, index: Int, key: String, text: String) {
        var rows = rows(section, field); guard rows.indices.contains(index) else { return }
        var row = rows[index].object ?? [:]; row[key] = .string(text); rows[index] = .object(row); set(section, field, .array(rows))
    }
    public mutating func appendRow(_ section: String, _ field: String, prefix: String, maximum: Int) {
        var rows = rows(section, field); guard rows.count < maximum else { return }
        let ids = Set(rows.compactMap { $0.object?["id"]?.string }); var number = 1
        while ids.contains("\(prefix)_\(number)") { number += 1 }
        rows.append(.object(["id": .string("\(prefix)_\(number)"), "label": .string("")]))
        set(section, field, .array(rows))
    }
    public mutating func removeRow(_ section: String, _ field: String, index: Int) {
        var rows = rows(section, field); guard rows.indices.contains(index) else { return }
        let removedID = rows.remove(at: index).object?["id"]?.string; set(section, field, .array(rows))
        if section == "classify", let removedID {
            var answer = value[section]?.object?["answer"]?.object ?? [:]
            if field == "items" { answer.removeValue(forKey: removedID) }
            if field == "bins" { answer = answer.filter { $0.value.string != removedID } }
            set(section, "answer", .object(answer))
        }
    }
    public mutating func moveRow(_ section: String, _ field: String, from: Int, to: Int) {
        var rows = rows(section, field); guard rows.indices.contains(from), rows.indices.contains(to), from != to else { return }
        let row = rows.remove(at: from); rows.insert(row, at: to); set(section, field, .array(rows))
    }
    public mutating func setClassification(itemID: String, binID: String) {
        var answer = value["classify"]?.object?["answer"]?.object ?? [:]
        answer[itemID] = binID.isEmpty ? nil : .string(binID); set("classify", "answer", .object(answer))
    }
    public func miniGameIssues(_ game: TemplateAdvancedGame) -> [String] {
        guard game.isMiniProgramAddition, enabled(game.section) else { return [] }
        let section = game.section; var issues: [String] = []
        func fail(_ key: String) { issues.append("playkitAuthor.validation." + key) }
        func string(_ key: String) -> String { text(section, key).trimmingCharacters(in: .whitespacesAndNewlines) }
        func number(_ field: String, _ range: ClosedRange<Double>, integer: Bool = true, nonblank: Bool = false) {
            guard !nonblank || !string(field).isEmpty,
                  let n = value[section]?.object?[field]?.number, n.isFinite, range.contains(n), !integer || n.rounded() == n else { fail(section + "." + field); return }
        }
        func validateRows(_ field: String, count: ClosedRange<Int>) -> Set<String> {
            let rows = rows(section, field)
            if !count.contains(rows.count) { fail(section + "." + field + ".count") }
            var ids = Set<String>()
            for raw in rows {
                guard let row = raw.object else { fail("row"); continue }
                let id = (row["id"]?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if id.range(of: "^[A-Za-z0-9_-]{1,32}$", options: .regularExpression) == nil || !ids.insert(id).inserted { fail("id") }
                let label = (row["label"]?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if label.isEmpty || label.utf16.count > 40 { fail("label") }
                if let img = row["img"]?.string, !img.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   !PlayExperienceService.validHTTPS(img.trimmingCharacters(in: .whitespacesAndNewlines)) { fail("image") }
            }
            return ids
        }
        if game.isReasoning {
            if string("prompt").isEmpty || string("prompt").utf16.count > 200 { fail("prompt") }
            switch game {
            case .sort: _ = validateRows("items", count: 2...8)
            case .match:
                _ = validateRows("left", count: 2...6); _ = validateRows("right", count: 2...6)
                if rows(section, "left").count != rows(section, "right").count { fail("match.sameCount") }
            case .classify:
                let bins = validateRows("bins", count: 2...4), items = validateRows("items", count: 2...10)
                let answer = value[section]?.object?["answer"]?.object ?? [:]
                if Set(answer.keys) != items || answer.values.contains(where: { !bins.contains($0.string ?? "") }) { fail("classify.answer") }
            default: break
            }
        } else {
            if string("kicker").utf16.count > 32 { fail("kicker") }
            number("xp", 0...1000)
            if game == .compass {
                number("bearing", 0...359, nonblank: true); number("tolerance", 5...90); number("holdSeconds", 1...10)
                if string("hint").utf16.count > 60 { fail("compass.hint") }
            } else { number("seconds", 5...300, integer: false) }
        }
        return Array(Set(issues)).sorted()
    }
    public mutating func normalizeMiniGame(_ game: TemplateAdvancedGame) {
        let section = game.section
        func cleanedRows(_ field: String) -> [TemplateAuthoringJSON] {
            rows(section, field).map { raw in
                var row = raw.object ?? [:]
                for key in ["id", "label"] { row[key] = .string((row[key]?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)) }
                if let image = row["img"]?.string {
                    let clean = image.trimmingCharacters(in: .whitespacesAndNewlines); row["img"] = clean.isEmpty ? nil : .string(clean)
                }
                return .object(row) // Preserve owned fields that this panel does not edit.
            }
        }
        if game.isReasoning {
            set(section, "prompt", .string(text(section, "prompt").trimmingCharacters(in: .whitespacesAndNewlines)))
            switch game {
            case .sort:
                let items = cleanedRows("items"); set(section, "items", .array(items))
                set(section, "answerOrder", .array(items.compactMap { $0.object?["id"] }))
            case .match:
                let left = cleanedRows("left"), right = cleanedRows("right")
                set(section, "left", .array(left)); set(section, "right", .array(right))
                set(section, "pairs", .array(zip(left, right).map { .array([$0.0.object?["id"] ?? .string(""), $0.1.object?["id"] ?? .string("")]) }))
            case .classify:
                set(section, "items", .array(cleanedRows("items"))); set(section, "bins", .array(cleanedRows("bins")))
                let original = value[section]?.object?["answer"]?.object ?? [:]
                set(section, "answer", .object(original.mapValues { .string(($0.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)) }))
            default: break
            }
        } else {
            let fields = game == .compass ? ["bearing", "tolerance", "holdSeconds", "xp"] : ["seconds", "xp"]
            for field in fields { if let number = value[section]?.object?[field]?.number { set(section, field, .number(number)) } }
            var values = value[section]?.object ?? [:]
            for field in game == .compass ? ["kicker", "hint"] : ["kicker"] {
                let clean = (values[field]?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines); values[field] = clean.isEmpty ? nil : .string(clean)
            }
            value[section] = .object(values)
        }
    }
    /// Explicit author rehearsal, never a live PlayAdvancedState or reward receipt.
    public func miniPreviewSegment(_ game: TemplateAdvancedGame) throws -> PlayWireValue {
        guard game.isMiniProgramAddition, miniGameIssues(game).isEmpty else { throw TemplateAuthoringError.invalidDraft }
        var draft = self; draft.normalizeMiniGame(game)
        var fields = draft.value[game.section]?.object ?? [:]
        for key in ["answerOrder", "pairs", "answer", "xp", "enabled"] { fields.removeValue(forKey: key) }
        return try JSONDecoder().decode(PlayWireValue.self, from: JSONEncoder().encode(TemplateAuthoringJSON.object(fields)))
    }
}
