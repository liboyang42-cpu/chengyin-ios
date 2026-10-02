import Foundation

public struct TemplateCreatorIssue: Equatable, Identifiable {
    public let family: TemplateCreatorFamily
    public let path: String
    public let code: String
    public var id: String { family.rawValue + "." + path + "." + code }
    public var labelKey: String { "creator.validation." + code }
}
public enum TemplateCreatorPath: Equatable { case field(String), index(Int) }

extension TemplateAdvancedDraft {
    public static var creatorDefaults: [String: TemplateAuthoringJSON] {
        Dictionary(uniqueKeysWithValues: TemplateCreatorFamily.allCases.map { family in
            var fields = TemplateCreatorSchema.defaults(TemplateCreatorSchema.fields(family)); fields["enabled"] = .bool(false)
            // Stable, meaningful defaults from the contract; no inferred answers for imported drafts.
            if family == .branch {
                var rows = fields["steps"]?.array ?? []; var row = rows.first?.object ?? [:]
                row["id"] = .string("start"); rows = [.object(row)]; fields["steps"] = .array(rows)
            }
            if family == .compare {
                for side in ["left", "right"] {
                    var part = fields[side]?.object ?? [:]
                    part["items"] = .array((1...2).map { .object(["id": .string(side + "_" + String($0)), "time": .string(""), "text": .string("")]) })
                    fields[side] = .object(part)
                }
            }
            if family == .multiplayer {
                fields["roles"] = .array([.object(["id": .string("player"), "label": .string("队员"), "min": .number(1), "max": .number(4)])])
                fields["turnOrder"] = .array([.string("player")])
            }
            if family == .blindTaste || family == .predict {
                fields["options"] = .array([.object(["key": .string("A"), "label": .string("")]), .object(["key": .string("B"), "label": .string("")])])
                if family == .blindTaste { fields["answerKey"] = .string("A") }
            }
            if family == .hiddenObject {
                fields["hotspots"] = .array([(0.25, 0.3), (0.7, 0.45), (0.45, 0.75)].enumerated().map { index, xy in
                    .object(["id": .string("spot_\(index + 1)"), "label": .string(""), "x": .number(xy.0), "y": .number(xy.1), "r": .number(0.08)])
                })
            }
            return (family.rawValue, .object(fields))
        })
    }
    public var enabledCreatorFamilies: [TemplateCreatorFamily] { TemplateCreatorFamily.allCases.filter { enabled($0.rawValue) } }
    public mutating func setCreatorEnabled(_ family: TemplateCreatorFamily, _ enabled: Bool) {
        set(family.rawValue, "enabled", .bool(enabled))
        if enabled && family == .check && text("check", "checkId").isEmpty { set("check", "checkId", .string("check_" + UUID().uuidString.replacingOccurrences(of: "-", with: ""))) }
    }
    public func creatorValue(_ family: TemplateCreatorFamily, path: [TemplateCreatorPath]) -> TemplateAuthoringJSON? {
        var current = value[family.rawValue]
        for part in path {
            switch part { case .field(let key): current = current?.object?[key]
            case .index(let index): let rows = current?.array ?? []; current = rows.indices.contains(index) ? rows[index] : nil }
        }
        return current
    }
    /// Patches only the selected leaf. Siblings and future extension fields survive edits and snapshots.
    public mutating func setCreatorValue(_ family: TemplateCreatorFamily, path: [TemplateCreatorPath], entry: TemplateAuthoringJSON?) {
        func patch(_ current: TemplateAuthoringJSON?, _ remaining: ArraySlice<TemplateCreatorPath>) -> TemplateAuthoringJSON? {
            guard let part = remaining.first else { return entry }
            switch part {
            case .field(let key): var fields = current?.object ?? [:]; fields[key] = patch(fields[key], remaining.dropFirst()); return .object(fields)
            case .index(let index): var rows = current?.array ?? []; guard rows.indices.contains(index), let replacement = patch(rows[index], remaining.dropFirst()) else { return current }; rows[index] = replacement; return .array(rows)
            }
        }
        value[family.rawValue] = patch(value[family.rawValue], path[...])
    }
    public mutating func addCreatorRow(_ family: TemplateCreatorFamily, path: [TemplateCreatorPath], field: TemplateCreatorField) {
        guard case .rows(let fields, _, let maximum, let identity) = field.kind else { return }
        var rows = creatorValue(family, path: path)?.array ?? []; guard rows.count < maximum else { return }
        var row = TemplateCreatorSchema.defaults(fields)
        if let identity {
            let identityRows = family == .compare ? ["left", "right"].flatMap { value["compare"]?.object?[$0]?.object?["items"]?.array ?? [] } : rows
            let used = Set(identityRows.compactMap { $0.object?[identity]?.string }); var index = 1
            while used.contains("\(field.id)_\(index)") { index += 1 }
            row[identity] = .string("\(field.id)_\(index)")
        }
        rows.append(.object(row)); setCreatorValue(family, path: path, entry: .array(rows))
    }
    public func creatorIssues(_ family: TemplateCreatorFamily) -> [TemplateCreatorIssue] {
        guard enabled(family.rawValue) else { return [] }
        var result: [TemplateCreatorIssue] = []
        func fail(_ path: String, _ code: String) { result.append(.init(family: family, path: path, code: code)) }
        func string(_ fields: [String: TemplateAuthoringJSON], _ key: String) -> String { (fields[key]?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
        func matches(_ value: String, _ pattern: String) -> Bool { value.range(of: pattern, options: .regularExpression) != nil }
        func media(_ text: String) -> Bool {
            guard !text.contains("\\"), !text.contains(where: { $0.isNewline }) else { return false }
            if text.hasPrefix("/") { return !text.hasPrefix("//") }
            guard let url = URLComponents(string: text), url.scheme?.lowercased() == "https", url.host?.isEmpty == false, url.user == nil, url.password == nil else { return false }
            return true
        }
        func walk(_ fields: [String: TemplateAuthoringJSON], _ schema: [TemplateCreatorField], _ path: String) {
            let known = Set(schema.map(\.id) + (path.isEmpty ? ["enabled"] : []))
            for key in fields.keys where !known.contains(key) { fail(path + key, "unknown") }
            for field in schema {
                let p = path + field.id
                // Inactive variants are preserved verbatim, and become validated when selected.
                let inactive = (family == .qa && path.isEmpty && field.id == "options" && string(fields, "mode") != "PICK") ||
                    (family == .profile && path.contains("questions[") && !path.contains("options[") && ((field.id == "options" || field.id == "override") && string(fields, "kind") != "pick" || field.id == "maxLength" && string(fields, "kind") == "pick"))
                if inactive { continue }
                if field.id == "override" && (fields[field.id] == nil || fields[field.id] == .null) { continue }
                if family == .compare && path.isEmpty && ["maxAttempts", "effects"].contains(field.id) && (fields[field.id] == nil || fields[field.id] == .null) { continue }
                let raw = fields[field.id] ?? field.initial
                let requiredRowNumber = ["weight", "x", "y", "r"].contains(field.id) || (family == .multiplayer && path.hasPrefix("roles[") && ["min", "max"].contains(field.id))
                if requiredRowNumber && fields[field.id] == nil { fail(p, "required") }
                if field.id == "value", fields["op"] != nil, string(fields, "op") != "NODE_COMPLETED", fields[field.id] == nil { fail(p, "required") }
                if field.id == "nodeId", string(fields, "op") == "NODE_COMPLETED", fields[field.id] == nil { fail(p, "required") }
                switch field.kind {
                case .text(let max, let required, let pattern):
                    guard let text = raw.string else { fail(p, "type"); continue }
                    let v = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if required && v.isEmpty { fail(p, "required") }
                    if v.utf16.count > max { fail(p, "length") }
                    if let pattern, !v.isEmpty, !matches(v, pattern) { fail(p, "identifier") }
                    if ["audioUrl", "imageUrl", "overlayUrl", "markerUrl", "modelUrl", "frameUrl", "url"].contains(field.id), !v.isEmpty, !media(v) { fail(p, "media") }
                case .number(let min, let max, let integer):
                    guard let n = raw.number, n.isFinite, n >= min, n <= max, !integer || n.rounded() == n, !(raw.string?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? false) else { fail(p, "range"); continue }
                case .choice(let choices): if !choices.contains(raw.string ?? "__invalid__") { fail(p, "choice") }
                case .toggle: if case .bool = raw {} else { fail(p, "type") }
                case .stateValue:
                    if ["ADD_TAG", "HAS_TAG"].contains(string(fields, "op")) {
                        if !matches(raw.string ?? "", "^tag\\.[a-z][a-z0-9_]{0,47}$") { fail(p, "state") }
                    } else if string(fields, "op") != "NODE_COMPLETED" {
                        guard let n = raw.number, n.isFinite, n.rounded() == n, (-99...99).contains(n) else { fail(p, "state"); continue }
                    }
                case .object(let nested): guard let object = raw.object else { fail(p, "type"); continue }; walk(object, nested, p + ".")
                case .rows(let nested, let min, let max, let identity):
                    guard let rows = raw.array else { fail(p, "type"); continue }
                    if rows.count < min || rows.count > max { fail(p, "count") }
                    var ids = Set<String>()
                    for (index, row) in rows.enumerated() {
                        guard let object = row.object else { fail(p, "type"); continue }
                        if let identity, !ids.insert(string(object, identity)).inserted { fail(p, "duplicate") }
                        walk(object, nested, p + "[\(index + 1)].")
                    }
                case .strings(let min, let max, let length):
                    guard let rows = raw.array else { fail(p, "type"); continue }
                    if rows.count < min || rows.count > max { fail(p, "count") }
                    for row in rows { guard let text = row.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.utf16.count <= length else { fail(p, "length"); continue } }
                case .poems:
                    guard let poems = raw.array else { fail(p, "type"); continue }
                    if poems.isEmpty || poems.count > 60 { fail(p, "count") }
                    for poem in poems {
                        guard let lines = poem.array, (1...4).contains(lines.count) else { fail(p, "count"); continue }
                        for line in lines { guard let text = line.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.utf16.count <= 24 else { fail(p, "length"); continue } }
                    }
                }
            }
            if let op = fields["op"]?.string {
                let variable = string(fields, "var")
                if ["SET", "INC"].contains(op) {
                    if variable == "sys.luck" {
                        if op != "INC" || !(1...3).contains(fields["value"]?.number ?? 0) { fail(path + "var", "state") }
                    } else if !matches(variable, "^(clue|relation|counter)\\.[a-z][a-z0-9_]{0,47}$") { fail(path + "var", "state") }
                } else if ["EQ", "NE", "GT", "GTE", "LT", "LTE"].contains(op) {
                    let named = matches(variable, "^(clue|relation|counter)\\.[a-z][a-z0-9_]{0,47}$")
                    let system = ["sys.hp", "sys.luck", "sys.exhausted"].contains(variable) || matches(variable, "^sys\\.(mistakes|outcome|passed)\\.[1-9][0-9]*$") || matches(variable, "^sys\\.asked\\.[1-9][0-9]*\\.[A-Za-z0-9_-]{1,32}$")
                    if !named && !system { fail(path + "var", "state") }
                }
            }
        }
        guard let fields = value[family.rawValue]?.object else { fail("", "type"); return result }
        walk(fields, TemplateCreatorSchema.fields(family), "")
        func text(_ key: String) -> String { string(fields, key) }
        func num(_ key: String) -> Double { fields[key]?.number ?? .nan }
        func rows(_ key: String) -> [[String: TemplateAuthoringJSON]] { (fields[key]?.array ?? []).compactMap(\.object) }
        switch family {
        case .compare:
            let allItems = ["left", "right"].flatMap { fields[$0]?.object?["items"]?.array ?? [] }
            let ids = allItems.compactMap { $0.object?["id"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines) }
            if Set(ids).count != ids.count { fail("left/right.items", "duplicate") }
            let answer = (fields["answer"]?.array ?? []).compactMap(\.string)
            if Set(answer).count != answer.count { fail("answer", "duplicate") }
            if !Set(answer).isSubset(of: Set(ids)) { fail("answer", "reference") }
        case .random: if num("drawCount") > Double(rows("items").count) { fail("drawCount", "reference") }
        case .branch:
            let steps = rows("steps"); let ids = Set(steps.compactMap { $0["id"]?.string })
            if !ids.contains(text("startStepId")) { fail("startStepId", "reference") }
            for step in steps {
                let options = step["options"]?.array ?? []
                if (step["terminal"]?.bool == true) != options.isEmpty { fail("steps", "branch") }
                if step["terminal"]?.bool == true && !matches(string(step, "outcomeCode"), TemplateCreatorSchema.keyPattern) { fail("outcomeCode", "identifier") }
                if options.contains(where: { !ids.contains($0.object?["nextStepId"]?.string ?? "") }) { fail("options", "reference") }
            }
            var pending = [text("startStepId")], visited = Set<String>(), reached = false
            while let id = pending.popLast() {
                guard visited.insert(id).inserted, let step = steps.first(where: { $0["id"]?.string == id }) else { continue }
                if step["terminal"]?.bool == true { reached = true }
                pending += (step["options"]?.array ?? []).compactMap { $0.object?["nextStepId"]?.string }
            }
            if !reached { fail("steps", "unreachable") }
        case .multiplayer:
            let roles = rows("roles"), min = num("minPlayers"), max = num("maxPlayers")
            let order = (fields["turnOrder"]?.array ?? []).compactMap(\.string)
            let ids = Set(roles.compactMap { $0["id"]?.string })
            if min > max { fail("minPlayers", "range") }
            if order.contains(where: { !ids.contains($0) }) { fail("turnOrder", "reference") }
            if roles.contains(where: { ($0["min"]?.number ?? 0) > ($0["max"]?.number ?? 0) || ($0["max"]?.number ?? 0) > max }) { fail("roles", "range") }
            if roles.reduce(0, { $0 + ($1["min"]?.number ?? 0) }) > min || roles.reduce(0, { $0 + ($1["max"]?.number ?? 0) }) < max { fail("roles", "coverage") }
            if text("assignment") == "AUTO", !order.isEmpty, min.isFinite, max.isFinite, min >= 2, max <= 20, min <= max {
                for count in Int(min)...Int(max) {
                    var assigned: [String: Int] = [:]; for index in 0..<count { assigned[order[index % order.count], default: 0] += 1 }
                    if roles.contains(where: { role in let count = Double(assigned[role["id"]?.string ?? ""] ?? 0); return count < (role["min"]?.number ?? 0) || count > (role["max"]?.number ?? 0) }) { fail("turnOrder", "coverage"); break }
                }
            }
        case .timeWindow: if text("openFrom") == text("openTo") { fail("openTo", "timeWindow") }
        case .blindTaste: if !rows("options").contains(where: { $0["key"]?.string == text("answerKey") }) { fail("answerKey", "reference") }
        case .silentOrder: if num("limitSeconds") != 0 && num("limitSeconds") < 60 { fail("limitSeconds", "range") }
        case .diyName, .note:
            let key = family == .diyName ? "suggestions" : "presets"
            if (fields[key]?.array ?? []).contains(where: { Double(($0.string ?? "").utf16.count) > num("maxLength") }) { fail(key, "length") }
        case .musicCorner: if num("durationSeconds") != 0 && num("durationSeconds") < 10 { fail("durationSeconds", "range") }
        case .estimate:
            let min = num("min"), max = num("max"), answer = num("answer"), tolerance = num("tolerance")
            if min >= max || max - min > 1000000 { fail("max", "range") }
            if answer < min || answer > max || tolerance <= 0 || tolerance > (max - min) / 2 { fail("answer", "range") }
        case .pricePair: if rows("items").filter({ $0["correct"]?.bool == true }).count != 1 { fail("items", "answer") }
        case .hiddenObject:
            let spots = rows("hotspots")
            for i in spots.indices { for j in spots.indices where j > i {
                let dx = (spots[i]["x"]?.number ?? 0) - (spots[j]["x"]?.number ?? 0), dy = (spots[i]["y"]?.number ?? 0) - (spots[j]["y"]?.number ?? 0)
                if hypot(dx, dy) < (spots[i]["r"]?.number ?? 0.08) + (spots[j]["r"]?.number ?? 0.08) { fail("hotspots", "overlap") }
            } }
        case .predict: if num("revealDays") == 0 && num("revealHour") < num("closeAtHour") { fail("revealHour", "range") }
        case .qa:
            if text("mode") == "TYPE" && text("answerText").isEmpty { fail("answerText", "required") }
            if text("mode") == "SHOT" && text("lead").isEmpty { fail("lead", "required") }
            if text("mode") == "PICK" {
                let correct = rows("options").filter { $0["correct"]?.bool == true }.count
                if fields["multi"]?.bool == true ? correct < 1 : correct != 1 { fail("options", "answer") }
            }
        case .scan:
            let needed = ["TEXT": "reply", "VOICE": "audioUrl", "IMAGE": "imageUrl", "OVERLAY": "overlayUrl"][text("kind")] ?? "reply"
            if text(needed).isEmpty { fail(needed, "required") }
            if text("arMode") != "NONE" && text("kind") != "OVERLAY" { fail("arMode", "reference") }
            if text("arMode") == "MARKER" && text("markerUrl").isEmpty { fail("markerUrl", "required") }
            if !text("modelUrl").isEmpty && (text("arMode") == "NONE" || URLComponents(string: text("modelUrl"))?.path.lowercased().hasSuffix(".glb") != true) { fail("modelUrl", "model") }
        case .profile:
            var optionKeys = Set<String>()
            for question in rows("questions") where question["kind"]?.string == "pick" {
                let options = question["options"]?.array ?? []
                for option in options { if !optionKeys.insert(option.object?["key"]?.string ?? "").inserted { fail("questions.options", "duplicate") } }
                if let override = question["override"]?.object, !options.contains(where: { $0.object?["key"]?.string == override["option"]?.string }) { fail("questions.override", "reference") }
            }
        case .check: if !text("failCostTag").isEmpty && !matches(text("failCostTag"), "^tag\\.[a-z][a-z0-9_]{0,47}$") { fail("failCostTag", "state") }
        default: break
        }
        if explicitPresentation == "inline" && family.fullscreenOnly { fail("present", "fullscreen") }
        return result
    }
    public var creatorUnknownIssues: [TemplateCreatorIssue] {
        var issues: [TemplateCreatorIssue] = []
        func walk(_ value: TemplateAuthoringJSON?, fields: [TemplateCreatorField], family: TemplateCreatorFamily, path: String) {
            guard let object = value?.object else { return }
            let known = Set(fields.map(\.id) + (path.isEmpty ? ["enabled"] : []))
            for key in object.keys where !known.contains(key) { issues.append(.init(family: family, path: path + key, code: "unknown")) }
            for field in fields {
                switch field.kind {
                case .object(let nested): walk(object[field.id], fields: nested, family: family, path: path + field.id + ".")
                case .rows(let nested, _, _, _): for (index, row) in (object[field.id]?.array ?? []).enumerated() { walk(row, fields: nested, family: family, path: path + field.id + "[\(index + 1)].") }
                default: break
                }
            }
        }
        for family in TemplateCreatorFamily.allCases { walk(value[family.rawValue], fields: TemplateCreatorSchema.fields(family), family: family, path: "") }
        return issues
    }
    public mutating func normalizeCreatorFamilies() {
        func normalized(_ object: [String: TemplateAuthoringJSON], _ fields: [TemplateCreatorField]) -> [String: TemplateAuthoringJSON] {
            var result = object
            for field in fields {
                guard let raw = object[field.id] else { continue }
                switch field.kind {
                case .text:
                    if let text = raw.string { result[field.id] = .string(text.trimmingCharacters(in: .whitespacesAndNewlines)) }
                case .number:
                    if let n = raw.number { result[field.id] = .number(n) }
                case .stateValue:
                    if ["ADD_TAG", "HAS_TAG"].contains(object["op"]?.string ?? "") { if let text = raw.string { result[field.id] = .string(text.trimmingCharacters(in: .whitespacesAndNewlines)) } }
                    else if let n = raw.number { result[field.id] = .number(n) }
                case .object(let nested): if let inner = raw.object { result[field.id] = .object(normalized(inner, nested)) }
                case .rows(let nested, _, _, _): if let rows = raw.array { result[field.id] = .array(rows.map { row in guard let inner = row.object else { return row }; return .object(normalized(inner, nested)) }) }
                case .strings: if let rows = raw.array { result[field.id] = .array(rows.map { .string(($0.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)) }) }
                case .poems: if let rows = raw.array { result[field.id] = .array(rows.map { .array(($0.array ?? []).map { .string(($0.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)) }) }) }
                default: break
                }
                if ["audioUrl", "imageUrl", "overlayUrl", "markerUrl", "modelUrl", "frameUrl", "failCostTag"].contains(field.id), result[field.id]?.string == "" { result.removeValue(forKey: field.id) }
            }
            if let op = result["op"]?.string {
                if ["ADD_TAG", "HAS_TAG"].contains(op) { result.removeValue(forKey: "var"); result.removeValue(forKey: "nodeId") }
                else if op == "NODE_COMPLETED" { result.removeValue(forKey: "var"); result.removeValue(forKey: "value") }
                else { result.removeValue(forKey: "nodeId") }
            }
            return result
        }
        for family in enabledCreatorFamilies {
            var fields = normalized(value[family.rawValue]?.object ?? [:], TemplateCreatorSchema.fields(family))
            if family == .photoCheck {
                if fields["frameUrl"] == nil { fields.removeValue(forKey: "frameOpacity") }
                if fields["mode"]?.string == "" { fields.removeValue(forKey: "mode") }
                if fields["cardTitle"]?.string == "" { fields.removeValue(forKey: "cardTitle") }
                if fields["cardStyle"]?.string == "" { fields["cardStyle"] = .string("foil") }
            }
            if family == .profile {
                fields["questions"] = .array((fields["questions"]?.array ?? []).map { entry in
                    var question = entry.object ?? [:]; question["required"] = .bool(true); return .object(question)
                })
            }
            value[family.rawValue] = .object(fields)
        }
    }
    /// An imported public projection must never receive an invented secret default.
    public mutating func retainCreatorSecretAbsence(_ incoming: [String: TemplateAuthoringJSON]) {
        let protected: [String: [String]] = ["estimate": ["answer", "tolerance"], "blindTaste": ["answerKey"], "dailySign": ["poems"], "qa": ["answerText"], "compare": ["answer"]]
        for (section, keys) in protected {
            guard let fields = incoming[section]?.object, fields["enabled"]?.bool == true else { continue }
            for key in keys where fields[key] == nil {
                set(section, key, key == "answerKey" || key == "answerText" ? .string("") : .null)
            }
        }
    }
}
