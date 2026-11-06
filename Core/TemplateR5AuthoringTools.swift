import Foundation
import CryptoKit

extension TemplateR5Authoring {
    public enum Tool: String, CaseIterable, Identifiable {
        case cost, reward, clue, uses, vote
        public var id: String { rawValue }
        public var labelKey: String { "templateR5.tool." + rawValue }
    }
    public static let costFields: Set<String> = ["hpCost", "luckCost", "actionCost", "statCosts", "resourceCosts", "costOptions"]
    public static func hasCost(_ draft: TemplateAdvancedDraft) -> Bool {
        let rules = draft.value["interactionRules"]?.object ?? [:]
        return ["hpCost", "luckCost", "actionCost"].contains { (rules[$0]?.number ?? 0) > 0 } || ["statCosts", "resourceCosts", "costOptions"].contains { !(rules[$0]?.array ?? []).isEmpty }
    }
    public static func hasVote(_ draft: TemplateAdvancedDraft) -> Bool {
        let tools = draft.value["interactionTools"]?.object ?? [:]
        return !(tools["plans"]?.array ?? []).isEmpty || tools["votePolicy"] != nil || tools["decidesEnding"]?.bool == true
    }
    public static func slots(_ draft: TemplateAdvancedDraft) -> [[String: JSON]] { (draft.value["interactionRules"]?.object?["resourceSlots"]?.array ?? []).compactMap(\.object) }
    /// Stable semantic names match template-tools.js; no theme item/value is created here.
    public static func clueKey(_ name: String) -> String {
        "clue.h_" + SHA256.hash(data: Data(TemplateAuthoringStory.sourceTrim(name).utf8)).prefix(6).map { String(format: "%02x", $0) }.joined()
    }
    public static func isNamedClue(_ value: String) -> Bool { matches(value, "^clue\\.h_[0-9a-f]{12}$") }
    public static func declare(kind: String, label: String, in draft: inout TemplateAdvancedDraft) throws -> String {
        let label = TemplateAuthoringStory.sourceTrim(label)
        guard ["VALUE", "ITEM"].contains(kind), !label.isEmpty, label.utf16.count <= 20 else { throw TemplateAuthoringError.invalidDraft }
        var rows = slots(draft)
        if let same = rows.first(where: { $0["kind"]?.string == kind && $0["label"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines) == label }), let key = same["key"]?.string { return key }
        guard rows.count < 20 else { throw TemplateAuthoringError.invalidDraft }
        let reserved = references(draft).union(rows.compactMap { $0["key"]?.string })
        let prefix = kind == "VALUE" ? "value_" : "item_"; var index = 1
        while reserved.contains(prefix + String(index)) { index += 1 }
        let key = prefix + String(index)
        rows.append(["key": .string(key), "kind": .string(kind), "label": .string(label), "required": .bool(true)])
        draft.set("interactionRules", "resourceSlots", .array(rows.map(JSON.object))); return key
    }
    /// Registered reference fields only. Unknown configuration is never recursively rewritten.
    public static func references(_ draft: TemplateAdvancedDraft) -> Set<String> {
        var used = Set<String>()
        func inspect(_ value: JSON) {
            if let object = value.object {
                for key in ["statKey", "itemId", "var"] { if let value = object[key]?.string { used.insert(value) } }
                for value in object.values { inspect(value) }
            } else if let rows = value.array { rows.forEach(inspect) }
        }
        for (key, value) in draft.value where key != "clues" { inspect(value) }
        return used
    }
    /// Fixed58's slot migration is performed in the staged tool snapshot only.
    /// Distinct legacy references remain distinct even when their placeholder labels match.
    public static func migrateLegacyReferences(in draft: inout TemplateAdvancedDraft) throws {
        var declarations = slots(draft), migrated: [String: String] = [:]
        let reserved = references(draft)
        func key(_ kind: String, _ original: String) throws -> String {
            if declarations.contains(where: { $0["key"]?.string == original && $0["kind"]?.string == kind }) { return original }
            let identity = kind + ":" + original
            if let current = migrated[identity] { return current }
            guard declarations.count < 20 else { throw TemplateAuthoringError.invalidDraft }
            let prefix = kind == "VALUE" ? "value_" : "item_"; var ordinal = 1
            while reserved.contains(prefix + String(ordinal)) || declarations.contains(where: { $0["key"]?.string == prefix + String(ordinal) }) { ordinal += 1 }
            let result = prefix + String(ordinal)
            declarations.append(["key": .string(result), "kind": .string(kind), "label": .string(kind == "VALUE" ? "需要的数值" : "需要的物资"), "required": .bool(true)])
            migrated[identity] = result; return result
        }
        func migrate(_ owner: [String: JSON]) throws -> [String: JSON] {
            var next = owner
            for (field, reference, kind) in [("statCosts", "statKey", "VALUE"), ("statChanges", "statKey", "VALUE"), ("resourceCosts", "itemId", "ITEM"), ("grants", "itemId", "ITEM"), ("materialCost", "itemId", "ITEM"), ("when", "itemId", "ITEM"), ("when", "var", "VALUE")] {
                guard let rows = next[field]?.array else { continue }
                next[field] = .array(try rows.map { raw in
                    guard var row = raw.object, let original = row[reference]?.string, !original.isEmpty,
                          !declarations.contains(where: { $0["key"]?.string == original }) else { return raw }
                    if kind == "VALUE" && !original.hasPrefix("counter.") && !["sys.hp", "sys.luck", "sys.actions"].contains(original) { return raw }
                    row[reference] = .string(try key(kind, original)); return .object(row)
                })
            }
            for field in ["costOptions", "grantOptions", "plans"] { if let rows = next[field]?.array {
                next[field] = .array(try rows.map { raw in guard let row = raw.object else { return raw }; return .object(try migrate(row)) })
            } }
            return next
        }
        if let rules = draft.value["interactionRules"]?.object { draft.value["interactionRules"] = .object(try migrate(rules)) }
        if let tools = draft.value["interactionTools"]?.object { draft.value["interactionTools"] = .object(try migrate(tools)) }
        if !declarations.isEmpty { draft.set("interactionRules", "resourceSlots", .array(declarations.map(JSON.object))) }
    }
    public static func remove(_ tool: Tool, from draft: TemplateAdvancedDraft) -> TemplateAdvancedDraft {
        var next = draft, rules = draft.value["interactionRules"]?.object ?? [:], tools = draft.value["interactionTools"]?.object ?? [:]
        switch tool {
        case .cost: costFields.forEach { rules.removeValue(forKey: $0) }
        case .reward: rules.removeValue(forKey: "grants"); rules.removeValue(forKey: "grantOptions")
        case .uses: ["limit", "scope", "requireArrival"].forEach { rules.removeValue(forKey: $0) }
        case .clue:
            for field in ["effects", "worldEffects"] { if let rows = rules[field]?.array {
                let retained = rows.filter { !isNamedClue($0.object?["var"]?.string ?? "") }
                rules[field] = retained.isEmpty ? nil : .array(retained)
            } }; rules.removeValue(forKey: "publicOnce")
        case .vote: ["votePolicy", "plans", "decidesEnding", "fallback"].forEach { tools.removeValue(forKey: $0) }
        }
        next.value["interactionRules"] = rules.isEmpty ? nil : .object(rules)
        next.value["interactionTools"] = tools.isEmpty ? nil : .object(tools)
        pruneUnused(in: &next)
        return next
    }
    public static func pruneUnused(in draft: inout TemplateAdvancedDraft) {
        let used = references(draft)
        if let rows = draft.value["interactionRules"]?.object?["resourceSlots"]?.array {
            let retained = rows.filter { used.contains($0.object?["key"]?.string ?? "") }
            var rules = draft.value["interactionRules"]?.object ?? [:]
            rules["resourceSlots"] = retained.isEmpty ? nil : .array(retained)
            draft.value["interactionRules"] = rules.isEmpty ? nil : .object(rules)
        }
        if let names = draft.value["clues"]?.object {
            // Preserve other creator families' clue names; never clear an unrelated table entry.
            let retained = names.filter { !isNamedClue($0.key) || used.contains($0.key) }
            draft.value["clues"] = retained.isEmpty ? nil : .object(retained)
        }
    }
    public static func toolIssues(_ draft: TemplateAdvancedDraft) -> [Issue] {
        var out: [Issue] = []
        func fail(_ path: String, _ code: String) { out.append(.init(path, code)) }
        guard draft.value["interactionRules"] == nil || draft.value["interactionRules"]?.object != nil,
              draft.value["interactionTools"] == nil || draft.value["interactionTools"]?.object != nil else { return [.init("interactionRules", "unknown")] }
        let rules = draft.value["interactionRules"]?.object ?? [:], tools = draft.value["interactionTools"]?.object ?? [:]
        let known = costFields.union(["resourceSlots", "limit", "scope", "targetScope", "hpDelta", "statChanges", "when", "effects", "grants", "grantOptions", "worldEffects", "publicOnce", "requireArrival"])
        for field in rules.keys where !known.contains(field) { fail("interactionRules." + field, "unknown") }
        for field in tools.keys where !["allowTrade", "votePolicy", "decidesEnding", "plans", "fallback"].contains(field) { fail("interactionTools." + field, "unknown") }
        var kinds: [String: String] = [:]
        if let raw = rules["resourceSlots"] {
            if let rows = raw.array, rows.count <= 20 {
                for (index, raw) in rows.enumerated() {
                    let path = "interactionRules.resourceSlots[\(index)]"
                    guard let row = raw.object, Set(row.keys).isSubset(of: ["key", "kind", "label", "required"]),
                          let key = row["key"]?.string, matches(key, "^[a-z][a-z0-9_.]{0,47}$"),
                          let kind = row["kind"]?.string, ["VALUE", "ITEM"].contains(kind),
                          let label = row["label"]?.string, !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, label.utf16.count <= 20,
                          row["required"] == .bool(true) else { fail(path, "slot"); continue }
                    if kinds.updateValue(kind, forKey: key) != nil { fail(path, "duplicate") }
                }
            } else { fail("interactionRules.resourceSlots", "rows") }
            for key in kinds.keys where !references(draft).contains(key) { fail("interactionRules.resourceSlots." + key, "unusedSlot") }
        }
        func amounts(_ owner: [String: JSON], _ field: String, _ path: String) {
            let maximum = ["statCosts", "statChanges"].contains(field) ? 32 : 200
            guard let raw = owner[field] else { return }
            guard let rows = raw.array, rows.count <= maximum else { fail(path + "." + field, "rows"); return }
            var seen = Set<String>()
            let stat = field == "statCosts" || field == "statChanges", keyField = stat ? "statKey" : "itemId", numberField = field == "statChanges" ? "delta" : stat ? "amount" : "quantity"
            for (index, raw) in rows.enumerated() {
                let p = path + ".\(field)[\(index)]"
                guard let row = raw.object, Set(row.keys).isSubset(of: [keyField, numberField]), let key = row[keyField]?.string else { fail(p, "unknown"); continue }
                if let kind = kinds[key] { if kind != (stat ? "VALUE" : "ITEM") { fail(p, "slot") } }
                else if rules["resourceSlots"] != nil || !matches(key, stat ? "^counter\\.[a-z][a-z0-9_]{0,47}$" : "^[a-z][a-z0-9_]{0,31}$") { fail(p, "slot") }
                if !integer(row[numberField], field == "statChanges" ? -999...999 : 1...999) { fail(p, "quantity") }
                if !seen.insert(key).inserted { fail(p, "duplicate") }
            }
        }
        func effects(_ owner: [String: JSON], _ field: String, _ path: String) {
            guard let raw = owner[field] else { return }
            guard let rows = raw.array, rows.count <= 20 else { fail(path + "." + field, "rows"); return }
            for (index, raw) in rows.enumerated() {
                let p = path + ".\(field)[\(index)]"
                guard let row = raw.object, Set(row.keys).isSubset(of: ["var", "op", "value"]) else { fail(p, "unknown"); continue }
                let key = row["var"]?.string ?? "", op = row["op"]?.string ?? ""
                if kinds[key] == "VALUE" {
                    if !["INC", "FLOOR"].contains(op) || !integer(row["value"], 1...999) { fail(p, "operation") }
                } else if !matches(key, "^(clue|relation|counter)\\.[a-z][a-z0-9_]{0,47}$") || !["SET", "INC"].contains(op) || !integer(row["value"], -99...99) { fail(p, "operation") }
                if field == "worldEffects" && !key.hasPrefix("clue.") { fail(p, "operation") }
            }
        }
        func conditions(_ raw: JSON?, _ path: String) {
            guard let raw else { return }
            guard let rows = raw.array, rows.count <= 20 else { fail(path, "rows"); return }
            for (index, raw) in rows.enumerated() {
                guard let row = raw.object, TemplateAuthorCondition(row).issues.isEmpty else { fail(path + "[\(index)]", "condition"); continue }
            }
        }
        for field in ["hpCost", "luckCost", "actionCost"] { if rules[field] != nil && !integer(rules[field], 0...999) { fail("interactionRules." + field, "quantity") } }
        if rules["hpDelta"] != nil && !integer(rules["hpDelta"], -999...999) { fail("interactionRules.hpDelta", "quantity") }
        if rules["limit"] != nil && !integer(rules["limit"], 1...99) { fail("interactionRules.limit", "limit") }
        for (field, allowed) in [("scope", ["OWNER", "WORLD"]), ("targetScope", ["OWNER", "PARTICIPANTS", "WORLD"])] {
            if let value = rules[field], !allowed.contains(value.string ?? "") { fail("interactionRules." + field, "scope") }
        }
        for field in ["publicOnce", "requireArrival"] { if let value = rules[field], case .bool = value {} else if rules[field] != nil { fail("interactionRules." + field, "unknown") } }
        if rules["publicOnce"]?.bool == true && (rules["scope"]?.string != "WORLD" || (rules["worldEffects"]?.array ?? []).isEmpty) { fail("interactionRules.publicOnce", "publicOnce") }
        ["statCosts", "resourceCosts", "grants", "statChanges"].forEach { amounts(rules, $0, "interactionRules") }
        ["effects", "worldEffects"].forEach { effects(rules, $0, "interactionRules") }
        conditions(rules["when"], "interactionRules.when")
        for field in ["costOptions", "grantOptions"] {
            guard let raw = rules[field] else { continue }
            guard let groups = raw.array, (2...4).contains(groups.count) else { fail("interactionRules." + field, "groups"); continue }
            let reward = field == "grantOptions"
            if reward ? rules["grants"] != nil : costFields.subtracting(["costOptions"]).contains(where: { rules[$0] != nil }) { fail("interactionRules." + field, "groups") }
            for (index, raw) in groups.enumerated() {
                let p = "interactionRules.\(field)[\(index)]"
                guard let group = raw.object, Set(group.keys).isSubset(of: reward ? ["label", "grants"] : ["label", "hpCost", "luckCost", "actionCost", "statCosts", "resourceCosts"]) else { fail(p, "unknown"); continue }
                if let label = group["label"], label.string == nil || label.string?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true || (label.string?.utf16.count ?? 0) > 20 { fail(p + ".label", "label") }
                for field in reward ? ["grants"] : ["statCosts", "resourceCosts"] { amounts(group, field, p) }
                if reward && (group["grants"]?.array ?? []).isEmpty { fail(p, "required") }
                if !reward && !["hpCost", "luckCost", "actionCost"].contains(where: { (group[$0]?.number ?? 0) > 0 }) && (group["statCosts"]?.array ?? []).isEmpty && (group["resourceCosts"]?.array ?? []).isEmpty { fail(p, "required") }
                for field in ["hpCost", "luckCost", "actionCost"] where group[field] != nil { if !integer(group[field], 0...999) { fail(p + "." + field, "quantity") } }
            }
        }
        for field in ["allowTrade", "decidesEnding"] { if let value = tools[field], case .bool = value {} else if tools[field] != nil { fail("interactionTools." + field, "unknown") } }
        if let policy = tools["votePolicy"], !["MAJORITY", "UNANIMOUS", "MAJORITY_ACCEPTANCE"].contains(policy.string ?? "") { fail("interactionTools.votePolicy", "unknown") }
        if hasVote(draft) && !Set(rules.keys).isSubset(of: ["resourceSlots"]) { fail("interactionRules", "voteConflict") }
        if let raw = tools["plans"] {
            guard let plans = raw.array, (1...30).contains(plans.count) else { return out + [.init("interactionTools.plans", "plans")] }
            var keys = Set<String>()
            for (index, raw) in plans.enumerated() {
                let p = "interactionTools.plans[\(index)]"
                guard let plan = raw.object, Set(plan.keys).isSubset(of: ["title", "summary", "materialCost", "when", "endingKey", "planKey"]) else { fail(p, "unknown"); continue }
                if let key = plan["planKey"]?.string { if !matches(key, "^[a-z][a-z0-9_]{0,31}$") || !keys.insert(key).inserted { fail(p + ".planKey", "identity") } }
                if let key = plan["endingKey"], tools["decidesEnding"]?.bool != true || !matches(key.string ?? "", "^[a-z][a-z0-9_]{0,31}$") { fail(p + ".endingKey", "identity") }
                if let title = plan["title"]?.string, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.utf16.count <= 80 {} else { fail(p + ".title", "title") }
                if let summary = plan["summary"], summary.string == nil || (summary.string?.utf16.count ?? 0) > 2000 { fail(p + ".summary", "reply") }
                amounts(plan, "materialCost", p); conditions(plan["when"], p + ".when")
            }
        }
        if let raw = tools["fallback"] {
            if let value = raw.object, Set(value.keys).isSubset(of: ["title", "summary"]), let title = value["title"]?.string, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.utf16.count <= 80, value["summary"] == nil || value["summary"]?.string != nil && (value["summary"]?.string?.utf16.count ?? 0) <= 2000, !(tools["plans"]?.array ?? []).isEmpty {} else { fail("interactionTools.fallback", "title") }
        }
        return out
    }
}
