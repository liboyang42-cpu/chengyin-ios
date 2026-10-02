import Foundation

public enum TemplateRootCapability: String, CaseIterable, Identifiable {
    case mistakeTier, variants, roleViews
    public var id: String { rawValue }
    public var labelKey: String { "creatorRoot." + rawValue }
}
public struct TemplateRootIssue: Identifiable, Equatable {
    public let path: String; public let code: String
    public var id: String { path + "." + code }
    public var labelKey: String { "creatorRoot.validation." + code }
}
public enum TemplateRelaxField: String, CaseIterable, Identifiable {
    case timer = "timer.durationSeconds", typingTime = "typeIn.seconds", shakeTime = "ballShake.seconds"
    case sortAttempts = "sort.maxAttempts", pictureAttempts = "pricePair.maxTries", typingAttempts = "typeIn.tries"
    case qaAttempts = "qa.maxTries", hiddenAttempts = "hiddenObject.maxTries", stopwatchAttempts = "stopwatch.tries"
    case estimateTolerance = "estimate.tolerance", compassTolerance = "compass.tolerance", stopwatchTolerance = "stopwatch.toleranceMs", reaction = "reaction.goalMs"
    case quiet = "quietHold.seconds", shout = "shout.seconds", countdown = "countdown.seconds", compassHold = "compass.holdSeconds", shakeGoal = "ballShake.goal"
    public var id: String { rawValue }
    public var section: String { String(rawValue.split(separator: ".")[0]) }
    public var field: String { String(rawValue.split(separator: ".")[1]) }
    public var labelKey: String { "creatorRoot.relax." + rawValue }
    public var lowers: Bool { [.quiet, .shout, .countdown, .compassHold, .shakeGoal].contains(self) }
    public var attempts: Bool { [.sortAttempts, .pictureAttempts, .typingAttempts, .qaAttempts, .hiddenAttempts, .stopwatchAttempts].contains(self) }
    public var initialOperation: String { lowers ? "-1" : "+1" }
}

/// Exact backend condition DSL; arbitrary future keys survive snapshots but block submission.
public struct TemplateAuthorCondition: Equatable {
    public var value: [String: TemplateAuthoringJSON]
    public init(_ value: [String: TemplateAuthoringJSON] = ["var": .string("sys.hp"), "op": .string("LTE"), "value": .number(3)]) { self.value = value }
    public var op: String { value["op"]?.string ?? "" }
    public static let operations = ["EQ", "NE", "GT", "GTE", "LT", "LTE", "HAS_TAG", "NODE_COMPLETED"]
    public var issues: [String] {
        var out: [String] = []
        if !Set(value.keys).isSubset(of: ["var", "op", "value", "nodeId"]) { out.append("unknown") }
        guard Self.operations.contains(op) else { return out + ["condition"] }
        if op == "NODE_COMPLETED" {
            if let n = value["nodeId"]?.number, n.isFinite, n.rounded() == n, n >= 1, n <= 9_007_199_254_740_991 {} else { out.append("condition") }
        } else if op == "HAS_TAG" {
            if (value["value"]?.string ?? "").range(of: "^tag\\.[a-z][a-z0-9_]{0,47}$", options: .regularExpression) == nil { out.append("condition") }
        } else {
            let variable = value["var"]?.string ?? ""
            let named = variable.range(of: "^(clue|relation|counter)\\.[a-z][a-z0-9_]{0,47}$", options: .regularExpression) != nil
            let system = ["sys.hp", "sys.luck", "sys.exhausted"].contains(variable) || variable.range(of: "^sys\\.(mistakes|outcome|passed)\\.[1-9][0-9]*$", options: .regularExpression) != nil || variable.range(of: "^sys\\.asked\\.[1-9][0-9]*\\.[A-Za-z0-9_-]{1,32}$", options: .regularExpression) != nil
            if !named && !system { out.append("condition") }
            if let n = value["value"]?.number, n.isFinite, n.rounded() == n, (-99...99).contains(n), !(value["value"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? false) {} else { out.append("condition") }
        }
        return out
    }
    public var normalized: [String: TemplateAuthoringJSON] {
        var copy = value
        if op == "NODE_COMPLETED" { if let n = copy["nodeId"]?.number { copy["nodeId"] = .number(n) } }
        else if op != "HAS_TAG", let n = copy["value"]?.number { copy["value"] = .number(n) }
        return copy
    }
    public func matches(sample: TemplateRootSampleState) -> Bool {
        guard issues.isEmpty else { return false }
        if op == "NODE_COMPLETED" { return sample.completedNodes.contains(value["nodeId"]?.integer ?? -1) }
        if op == "HAS_TAG" { return sample.tags.contains(value["value"]?.string ?? "") }
        guard let lhs = sample.values[value["var"]?.string ?? ""], let rhs = value["value"]?.integer else { return false }
        switch op { case "EQ": return lhs == rhs; case "NE": return lhs != rhs; case "GT": return lhs > rhs; case "GTE": return lhs >= rhs; case "LT": return lhs < rhs; case "LTE": return lhs <= rhs; default: return false }
    }
}
public struct TemplateRootSampleState: Equatable {
    public var values: [String: Int] = ["sys.hp": 3, "sys.luck": 0, "sys.exhausted": 0]
    public var tags = Set<String>(); public var completedNodes = Set<Int>()
    public init() {}
}

extension TemplateAdvancedDraft {
    public static let rootCreatorKeys = Set(TemplateRootCapability.allCases.map(\.rawValue))
    public var hasRootAuthoringConfiguration: Bool { Self.rootCreatorKeys.contains { value[$0] != nil } }
    public var rootVariants: [TemplateAuthoringJSON] { value["variants"]?.array ?? [] }
    public var diceMode: String { value["diceRoll"]?.object?["mode"]?.string ?? "d6" }
    public mutating func setDiceMode(_ mode: String) {
        set("diceRoll", "mode", .string(mode))
        if mode == "d20" {
            let defaults: [String: TemplateAuthoringJSON] = ["dc": .number(10), "modifier": .number(0), "rollMode": .string("normal"), "successText": .string(""), "failText": .string("")]
            for (key, initial) in defaults where value["diceRoll"]?.object?[key] == nil { set("diceRoll", key, initial) }
        }
    }
    public mutating func setRoleViewsEnabled(_ enabled: Bool) {
        if value["roleViews"] == nil {
            value["roleViews"] = .object(["enabled": .bool(false), "roles": .array(["A", "B"].map { .object(["id": .string($0), "label": .string($0)]) }), "views": .array(["A", "B"].map { .object(["roleId": .string($0), "title": .string(""), "body": .string(""), "items": .array([])]) })])
        }
        set("roleViews", "enabled", .bool(enabled))
    }
    public mutating func appendRootVariant() {
        var variants = rootVariants; guard variants.count < 16 else { return }
        variants.append(.object(["when": .object(TemplateAuthorCondition().value), "relax": .object([:])]))
        value["variants"] = .array(variants)
    }
    public mutating func setRootVariant(_ index: Int, key: String, entry: TemplateAuthoringJSON?) {
        var variants = rootVariants; guard variants.indices.contains(index) else { return }
        var row = variants[index].object ?? [:]; row[key] = entry; variants[index] = .object(row); value["variants"] = .array(variants)
    }
    public var eligibleRelaxFields: [TemplateRelaxField] {
        TemplateRelaxField.allCases.filter { field in
            guard enabled(field.section) else { return false }
            if field == .shakeTime && value["ballShake"]?.object?["timed"]?.bool != true { return false }
            if field.attempts && (value[field.section]?.object?[field.field]?.number ?? 0) <= 0 { return false }
            return true
        }
    }
    public var rootCreatorIssues: [TemplateRootIssue] {
        var result: [TemplateRootIssue] = []
        func fail(_ path: String, _ code: String) { result.append(.init(path: path, code: code)) }
        func unknown(_ fields: [String: TemplateAuthoringJSON], _ known: Set<String>, _ path: String) { for key in fields.keys where !known.contains(key) { fail(path + "." + key, "unknown") } }
        if let tier = value["mistakeTier"], !["easy", "medium", "hard"].contains(tier.string ?? "") { fail("mistakeTier", "tier") }
        if let variants = value["variants"] {
            guard let rows = variants.array else { fail("variants", "shape"); return result }
            if rows.count > 16 { fail("variants", "count") }
            for (index, raw) in rows.enumerated() {
                let path = "variants[\(index + 1)]"
                guard let row = raw.object else { fail(path, "shape"); continue }
                unknown(row, ["when", "relax"], path)
                guard let condition = row["when"]?.object else { fail(path + ".when", "condition"); continue }
                for code in TemplateAuthorCondition(condition).issues { fail(path + ".when", code) }
                guard let relax = row["relax"]?.object, !relax.isEmpty else { fail(path + ".relax", "empty"); continue }
                var simulated = self; simulated.value.removeValue(forKey: "variants")
                var valid = true
                for (key, entry) in relax {
                    guard let field = TemplateRelaxField(rawValue: key), eligibleRelaxFields.contains(field), let operation = entry.string,
                          operation.range(of: "^[+=-][0-9]{1,5}$", options: .regularExpression) != nil,
                          let amount = Double(operation.dropFirst()) else { fail(path + "." + key, "relax"); valid = false; continue }
                    let sign = operation.first!
                    if field.lowers ? sign != "-" || amount == 0 : (sign == "-" || (sign == "+" && amount == 0) || (sign == "=" && (!field.attempts || amount != 0))) { fail(path + "." + key, "direction"); valid = false; continue }
                    let base = value[field.section]?.object?[field.field]?.number ?? 0
                    let changed = sign == "=" ? 0 : base + (sign == "-" ? -amount : amount)
                    simulated.set(field.section, field.field, .number(changed))
                }
                // First-match semantics: independently validate each possible snapshot, never stack them.
                if valid && !simulated.issues.isEmpty { fail(path, "relaxedBounds") }
            }
        }
        if let roleViews = value["roleViews"] {
            guard let fields = roleViews.object else { fail("roleViews", "shape"); return result }
            unknown(fields, ["enabled", "roles", "views"], "roleViews")
            if let enabled = fields["enabled"] { if case .bool = enabled {} else { fail("roleViews.enabled", "shape") } }
            let roles = fields["roles"]?.array ?? [], views = fields["views"]?.array ?? []
            for (index, raw) in roles.enumerated() {
                if let role = raw.object { unknown(role, ["id", "label"], "roleViews.roles[\(index)]") }
            }
            for (index, raw) in views.enumerated() {
                if let view = raw.object {
                    unknown(view, ["roleId", "title", "body", "items"], "roleViews.views[\(index)]")
                    for (itemIndex, item) in (view["items"]?.array ?? []).enumerated() { if let fields = item.object { unknown(fields, ["label", "text"], "roleViews.views[\(index)].items[\(itemIndex)]") } }
                }
            }
            if fields["enabled"]?.bool == true {
                if roles.count != 2 || Set(roles.compactMap { $0.object?["id"]?.string }) != ["A", "B"] { fail("roleViews.roles", "roles") }
                if views.count != 2 || Set(views.compactMap { $0.object?["roleId"]?.string }) != ["A", "B"] { fail("roleViews.views", "roles") }
                func textValid(_ fields: [String: TemplateAuthoringJSON], _ key: String, required: Bool) -> Bool {
                    guard let raw = fields[key] else { return !required }
                    guard let text = raw.string else { return false }; let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    return (!required || !value.isEmpty) && value.utf16.count <= 200
                }
                for raw in roles { guard let role = raw.object, textValid(role, "label", required: true) else { fail("roleViews.roles", "text"); continue } }
                for raw in views {
                    guard let view = raw.object, textValid(view, "title", required: false), textValid(view, "body", required: false) else { fail("roleViews.views", "text"); continue }
                    if let itemsValue = view["items"] {
                        guard let items = itemsValue.array, items.count <= 8 else { fail("roleViews.items", "count"); continue }
                        for item in items { guard let item = item.object, textValid(item, "label", required: true), textValid(item, "text", required: true) else { fail("roleViews.items", "text"); continue } }
                    }
                }
            }
        }
        return result
    }
    public mutating func normalizeRootAuthoring() {
        if let variants = value["variants"]?.array {
            value["variants"] = .array(variants.map { raw in var row = raw.object ?? [:]; if let condition = row["when"]?.object { row["when"] = .object(TemplateAuthorCondition(condition).normalized) }; return .object(row) })
        }
        if enabled("diceRoll") && diceMode == "d20" {
            for key in ["dc", "modifier"] { if let n = value["diceRoll"]?.object?[key]?.number { set("diceRoll", key, .number(n)) } }
            for key in ["successText", "failText"] { set("diceRoll", key, .string(text("diceRoll", key).trimmingCharacters(in: .whitespacesAndNewlines))) }
        }
        if enabled("sort"), let attempts = value["sort"]?.object?["maxAttempts"]?.number { set("sort", "maxAttempts", .number(attempts)) }
    }
    public func rehearsedVariant(sample: TemplateRootSampleState) throws -> (index: Int?, draft: TemplateAdvancedDraft) {
        guard issues.isEmpty else { throw TemplateAuthoringError.invalidDraft }
        for (index, raw) in rootVariants.enumerated() {
            guard let row = raw.object, let condition = row["when"]?.object, TemplateAuthorCondition(condition).matches(sample: sample) else { continue }
            var simulated = self; simulated.value.removeValue(forKey: "variants")
            for (key, operation) in row["relax"]?.object ?? [:] {
                guard let field = TemplateRelaxField(rawValue: key), let raw = operation.string, let amount = Double(raw.dropFirst()) else { throw TemplateAuthoringError.invalidDraft }
                let original = value[field.section]?.object?[field.field]?.number ?? 0
                simulated.set(field.section, field.field, .number(raw.first == "=" ? 0 : original + (raw.first == "-" ? -amount : amount)))
            }
            return (index, simulated)
        }
        return (nil, self)
    }
}
