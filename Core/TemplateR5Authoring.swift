import Foundation

/// Fixed58 outcome-after.js / GameplayOutcomeRules. This is author configuration,
/// never a client PASS/FAIL decision, participant selection or settlement receipt.
public enum TemplateR5Authoring {
    public typealias JSON = TemplateAuthoringJSON
    public static let rootKeys: Set<String> = ["outcomeRules", "interactionRules", "interactionTools"]
    public static let mains = ["qa", "pricePair", "blindTaste", "predict", "photoCheck", "coinFlip", "diceRoll", "random", "sort", "match", "classify", "estimate", "hiddenObject", "profile", "album", "note", "dailySign", "steps", "reaction", "ballShake", "quietHold", "compass", "shout", "countdown", "stopwatch", "typeIn", "check"]
    public static let once: Set<String> = ["profile", "album", "note", "dailySign"]
    public struct Issue: Identifiable, Equatable {
        public let path: String
        public let code: String
        public var id: String { path + ":" + code }
        public var labelKey: String { "templateR5.error." + code }
        public init(_ path: String, _ code: String) { self.path = path; self.code = code }
    }
    public enum Address: Hashable, Identifiable, Codable {
        case outcome(String)
        case option(section: String, field: String, identityField: String, identity: String)
        case coin(String)
        case face(Int)
        public var id: String {
            switch self {
            case .outcome(let key): return "outcomeRules." + key
            case let .option(section, field, _, identity): return section + "." + field + "." + identity + ".after"
            case .coin(let side): return "coinFlip." + side + ".after"
            case .face(let index): return "diceRoll.faces.\(index).after"
            }
        }
    }
    public struct Row: Identifiable {
        public let address: Address
        public let title: String
        public let value: [String: JSON]
        public let issue: String?
        public var id: String { address.id }
    }
    public static func main(_ draft: TemplateAdvancedDraft) -> [String] { mains.filter { draft.enabled($0) } }
    public static func completionOnly(_ draft: TemplateAdvancedDraft) -> Bool { main(draft).contains { once.contains($0) } }
    public static func rows(_ draft: TemplateAdvancedDraft) -> [Row] {
        var out: [Row] = []
        let rules = draft.value["outcomeRules"]?.object ?? [:]
        for key in ["pass", "fail"] where key == "pass" || !completionOnly(draft) || rules[key] != nil {
            out.append(.init(address: .outcome(key), title: key, value: rules[key]?.object ?? [:], issue: completionOnly(draft) && key == "fail" ? "once" : nil))
        }
        for (section, field, identity) in [("qa", "options", "id"), ("pricePair", "items", "id"), ("blindTaste", "options", "key"), ("predict", "options", "key"), ("random", "items", "id")] where draft.enabled(section) {
            let options = draft.value[section]?.object?[field]?.array ?? []
            for raw in options {
                guard let item = raw.object, let key = item[identity]?.string, !key.isEmpty else { continue }
                let duplicate = options.filter { $0.object?[identity]?.string == key }.count != 1
                let disabled = section == "qa" && draft.value["qa"]?.object?["multi"]?.bool == true || section == "random" && (draft.value["random"]?.object?["drawCount"]?.integer ?? 1) > 1
                out.append(.init(address: .option(section: section, field: field, identityField: identity, identity: key), title: item["label"]?.string ?? item["name"]?.string ?? key, value: item["after"]?.object ?? [:], issue: duplicate ? "identity" : disabled ? "perOption" : nil))
            }
        }
        if draft.enabled("coinFlip") { for side in ["heads", "tails"] {
            let value = draft.value["coinFlip"]?.object?[side]?.object ?? [:]
            out.append(.init(address: .coin(side), title: value["label"]?.string ?? side, value: value["after"]?.object ?? [:], issue: nil))
        } }
        if draft.enabled("diceRoll") { for (index, face) in (draft.value["diceRoll"]?.object?["faces"]?.array ?? []).enumerated() {
            out.append(.init(address: .face(index), title: face.string ?? face.object?["action"]?.string ?? "\(index + 1)", value: face.object?["after"]?.object ?? [:], issue: draft.diceMode == "d20" || draft.value["diceRoll"]?.object?["diceCount"]?.integer == 2 ? "perOption" : nil))
        } }
        return out
    }
    public static func replacing(_ row: [String: JSON], at address: Address, in draft: TemplateAdvancedDraft) throws -> TemplateAdvancedDraft {
        guard let current = rows(draft).first(where: { $0.address == address }), current.issue == nil, main(draft).count == 1 else { throw TemplateAuthoringError.invalidDraft }
        var next = draft
        if next.value["outcomeRules"] == nil {
            var rules: [String: JSON] = ["version": .number(1), "pass": .object([:])]
            if !completionOnly(next) { rules["fail"] = .object([:]) }
            next.value["outcomeRules"] = .object(rules)
        }
        switch address {
        case .outcome(let key): next.set("outcomeRules", key, .object(row))
        case let .option(section, field, identityField, identity):
            var options = next.value[section]?.object?[field]?.array ?? []
            guard let index = options.firstIndex(where: { $0.object?[identityField]?.string == identity }), var value = options[index].object else { throw TemplateAuthoringError.staleReview }
            value["after"] = .object(row); options[index] = .object(value); next.set(section, field, .array(options))
        case .coin(let side):
            var value = next.value["coinFlip"]?.object?[side]?.object ?? [:]; value["after"] = .object(row); next.set("coinFlip", side, .object(value))
        case .face(let index):
            var faces = next.value["diceRoll"]?.object?["faces"]?.array ?? []
            guard faces.indices.contains(index) else { throw TemplateAuthoringError.staleReview }
            var face = faces[index].object ?? ["action": .string(faces[index].string ?? "")]
            face["after"] = .object(row); faces[index] = .object(face); next.set("diceRoll", "faces", .array(faces))
        }
        return next
    }
    public static func isAfterField(family: TemplateCreatorFamily, path: String, field: String) -> Bool {
        guard field == "after" else { return false }
        let list = [.qa, .blindTaste, .predict].contains(family) ? "options" : [.pricePair, .random].contains(family) ? "items" : ""
        return !list.isEmpty && path.range(of: "^" + list + "\\[[0-9]+\\]\\.$", options: .regularExpression) != nil
    }
    public static func issues(_ draft: TemplateAdvancedDraft) -> [Issue] {
        var out = toolIssues(draft)
        let slots = draft.value["interactionRules"]?.object?["resourceSlots"]?.array ?? []
        let values = Set(slots.filter { $0.object?["kind"]?.string == "VALUE" }.compactMap { $0.object?["key"]?.string })
        var authored: [(String, JSON)] = []
        if let rules = draft.value["outcomeRules"] {
            guard let object = rules.object, Set(object.keys).isSubset(of: ["version", "pass", "fail"]), object["version"] == .number(1) else { return out + [.init("outcomeRules", "version")] }
            if main(draft).count != 1 { out.append(.init("outcomeRules", "main")) }
            if object["pass"]?.object == nil || (!completionOnly(draft) && object["fail"]?.object == nil) { out.append(.init("outcomeRules", "required")) }
            if completionOnly(draft) && object["fail"] != nil { out.append(.init("outcomeRules.fail", "once")) }
            if object["fail"] != nil && draft.value["interactionRules"]?.object?["targetScope"]?.string == "PARTICIPANTS" { out.append(.init("interactionRules.targetScope", "failScope")) }
            if hasVote(draft) { out.append(.init("interactionTools", "voteConflict")) }
            for key in ["pass", "fail"] { if let value = object[key] { authored.append(("outcomeRules." + key, value)) } }
        }
        for (section, field) in [("qa", "options"), ("pricePair", "items"), ("blindTaste", "options"), ("predict", "options"), ("random", "items"), ("diceRoll", "faces")] {
            for (index, row) in (draft.value[section]?.object?[field]?.array ?? []).enumerated() {
                if let after = row.object?["after"] {
                    let path = "\(section).\(field)[\(index)].after"; authored.append((path, after))
                    if section == "qa" && draft.value[section]?.object?["multi"]?.bool == true || section == "random" && (draft.value[section]?.object?["drawCount"]?.integer ?? 1) > 1 || section == "diceRoll" && (draft.diceMode == "d20" || draft.value[section]?.object?["diceCount"]?.integer == 2) { out.append(.init(path, "perOption")) }
                }
            }
        }
        for side in ["heads", "tails"] { if let after = draft.value["coinFlip"]?.object?[side]?.object?["after"] { authored.append(("coinFlip." + side + ".after", after)) } }
        for step in draft.value["branch"]?.object?["steps"]?.array ?? [] { for option in step.object?["options"]?.array ?? [] where option.object?["after"] != nil { out.append(.init("branch.options.after", "perOption")) } }
        if !authored.isEmpty && draft.value["outcomeRules"] == nil { out.append(.init("outcomeRules", "required")) }
        let steps = Set((draft.value["branch"]?.object?["steps"]?.array ?? []).compactMap { $0.object?["id"]?.string })
        var hasCosts = false
        for (path, raw) in authored {
            guard let row = raw.object, Set(row.keys).isSubset(of: ["reply", "images", "costs", "effects", "nextStepId"]) else { out.append(.init(path, "unknown")); continue }
            if let reply = row["reply"], reply.string == nil || (reply.string?.utf16.count ?? 0) > 2000 { out.append(.init(path + ".reply", "reply")) }
            if let raw = row["images"] {
                if let images = raw.array, images.count <= 3, images.allSatisfy({ validMedia($0.string) }) {} else { out.append(.init(path + ".images", "images")) }
            }
            if let raw = row["nextStepId"], let key = raw.string, matches(key, "^[A-Za-z0-9_-]{1,64}$"), steps.contains(key) {} else if row["nextStepId"] != nil { out.append(.init(path + ".nextStepId", "next")) }
            for kind in ["costs", "effects"] {
                guard let raw = row[kind] else { continue }
                guard let items = raw.array, items.count <= 20 else { out.append(.init(path + "." + kind, "rows")); continue }
                var seen = Set<String>()
                for (index, raw) in items.enumerated() {
                    let p = path + ".\(kind)[\(index)]", cost = kind == "costs"
                    guard let item = raw.object, Set(item.keys).isSubset(of: cost ? ["statKey", "amount"] : ["var", "op", "value"]) else { out.append(.init(p, "unknown")); continue }
                    let key = item[cost ? "statKey" : "var"]?.string ?? ""
                    if !values.contains(key) { out.append(.init(p, "slot")) }
                    if !integer(item[cost ? "amount" : "value"], 1...999) { out.append(.init(p, "quantity")) }
                    if !cost && !["INC", "FLOOR"].contains(item["op"]?.string ?? "") { out.append(.init(p, "operation")) }
                    if cost && !seen.insert(key).inserted { out.append(.init(p, "duplicate")) }
                }
                hasCosts = hasCosts || kind == "costs" && !items.isEmpty
            }
        }
        if hasCosts && hasCost(draft) { out.append(.init("interactionRules", "doubleCost")) }
        return out
    }
    static func integer(_ value: JSON?, _ range: ClosedRange<Int>) -> Bool {
        guard let value, case .number(let n) = value, n.isFinite, n.rounded() == n else { return false }; return n >= Double(range.lowerBound) && n <= Double(range.upperBound)
    }
    static func matches(_ value: String, _ pattern: String) -> Bool { value.range(of: pattern, options: .regularExpression) != nil }
    public static func validMedia(_ value: String?) -> Bool {
        guard let raw = value, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, raw.utf16.count <= 512 else { return false }
        return raw.hasPrefix("https://") || raw.hasPrefix("/") && !raw.hasPrefix("//") && !raw.contains("\\") || matches(raw, "^media-asset:[1-9][0-9]{0,18}$")
    }
}
