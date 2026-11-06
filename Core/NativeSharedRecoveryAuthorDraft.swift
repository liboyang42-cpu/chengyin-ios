import Foundation

/// Only explicitly authored TEAM gameplayRuntime.survival recovery definitions are authored here.
/// The original publication and TEAM RECOVER remain the owners; no personal resource or RATION reinterpretation.
public struct NativeSharedRecoveryAuthorDraft: Equatable {
    public enum Failure: Error { case unsupported, changed, invalid }
    public let originalTheme: ProjectEditJSON
    private let originalDraftBytes: Data
    private let originalDefinition: [String:ProjectEditJSON]
    public private(set) var theme: [String:ProjectEditJSON]
    public init(draft: ProjectEditDraft) throws {
        guard case .string(let text)? = draft.preserved["themeRuntimeConfig"], text.utf16.count <= 200_000,
              let theme = try? Self.originalFields(text),
              theme["schemaVersion"] == .number(1), let game = theme["gameplayRuntime"]?.object,
              game["runtimeScope"] == .string("TEAM"), ["TEAM_INDEPENDENT","WORLD_SHARED"].contains(game["worldMode"]?.text ?? ""),
              let quests = game["quests"]?.array, !quests.isEmpty,
              game["acts"]?.array != nil,
              game["survival"] == nil || game["survival"]?.object != nil else { throw Failure.unsupported }
        if let survival = game["survival"]?.object {
            guard survival["recoveries"] == nil || survival["recoveries"]?.array != nil,
                  survival["consumeOnNoEffect"] == nil || survival["consumeOnNoEffect"] == .bool(true) || survival["consumeOnNoEffect"] == .bool(false) else { throw Failure.unsupported }
        }
        // c6 accepts only REST/RESCUE. Preserve newer SUPPLY/unknown source bytes
        // by refusing this editor, never reinterpreting them as an older recovery.
        guard (game["survival"]?.object?["recoveries"]?.array ?? []).allSatisfy({ row in
            guard let fields = row.object, let kind = fields["kind"]?.text else { return false }
            return ["REST", "RESCUE"].contains(kind)
        }), let originalBytes = ProjectEditPendingMaterials.exactData(draft) else { throw Failure.unsupported }
        originalDraftBytes = originalBytes
        self.theme = theme; originalDefinition = theme; originalTheme = .string(text)
    }
    private var game: [String:ProjectEditJSON] { theme["gameplayRuntime"]?.object ?? [:] }
    private var survival: [String:ProjectEditJSON] { game["survival"]?.object ?? [:] }
    public var recoveries: [ProjectEditJSON] { survival["recoveries"]?.array ?? [] }
    public var acts: [String] { (game["acts"]?.array ?? []).compactMap { $0.object?["actKey"]?.text } }
    public var noEffectPolicy: String {
        guard let value = survival["consumeOnNoEffect"] else { return "" }; return value == .bool(true) ? "true" : "false"
    }
    private mutating func changeSurvival(_ action: (inout [String:ProjectEditJSON]) -> Void) {
        var next = survival; action(&next); var game = self.game; game["survival"] = .object(next); theme["gameplayRuntime"] = .object(game)
    }
    public mutating func noEffectPolicy(_ value: String) {
        guard ["","true","false"].contains(value) else { return }
        changeSurvival { if value.isEmpty { $0.removeValue(forKey:"consumeOnNoEffect") } else { $0["consumeOnNoEffect"] = .bool(value == "true") } }
    }
    public mutating func appendBlank() {
        guard recoveries.count < 20 else { return }
        var rows = recoveries; rows.append(.object([:])); changeSurvival { $0["recoveries"] = .array(rows) }
    }
    public mutating func remove(_ index: Int) {
        var rows = recoveries; guard rows.indices.contains(index) else { return }; rows.remove(at:index)
        changeSurvival { $0["recoveries"] = .array(rows) }
    }
    public func text(_ index: Int, _ key: String) -> String {
        guard recoveries.indices.contains(index), let value = recoveries[index].object?[key] else { return "" }
        if let text = value.text { return text }; if let number = value.integer { return String(number) }; return ""
    }
    public func actKeys(_ index: Int) -> [String] {
        guard recoveries.indices.contains(index) else { return [] }
        return (recoveries[index].object?["actKeys"]?.array ?? []).compactMap(\.text)
    }
    public mutating func edit(_ index: Int, _ key: String, _ value: String) {
        var rows = recoveries; guard rows.indices.contains(index), var row = rows[index].object,
              ["recoveryKey","kind","limit","hpDelta","hpFloor"].contains(key) else { return }
        if key == "kind" {
            guard ["","REST","RESCUE"].contains(value) else { return }
            if row[key] != .string(value) { row.removeValue(forKey:"hpDelta"); row.removeValue(forKey:"hpFloor") }
            row[key] = .string(value) // A new kind never inherits an amount with different meaning.
        } else if key == "recoveryKey" { row[key] = .string(value) }
        else if let number = Int(value), value.range(of:"^[0-9]+$",options:.regularExpression) != nil { row[key] = .number(Decimal(number)) }
        else { row[key] = .string(value) } // Keep invalid input visible; preview refuses it, never substitutes a number.
        rows[index] = .object(row); changeSurvival { $0["recoveries"] = .array(rows) }
    }
    public mutating func selectAct(_ index: Int, key: String, selected: Bool) {
        var rows = recoveries; guard rows.indices.contains(index), var row = rows[index].object,
              acts.contains(key) || (!selected && actKeys(index).contains(key)) else { return }
        var keys = actKeys(index).filter { $0 != key }; if selected { keys.append(key) }
        row["actKeys"] = .array(keys.map(ProjectEditJSON.string)); rows[index] = .object(row)
        changeSurvival { $0["recoveries"] = .array(rows) }
    }
    public var issues: [String] {
        var result: [String] = []
        var keys = Set<String>()
        let actualActs = game["acts"]?.array ?? []
        if acts.count != actualActs.count || Set(acts).count != acts.count || acts.contains(where:{ !Self.validKey($0) }) { result.append("原幕目录身份无效或重复，须先修复原目录。") }
        if recoveries.count > 20 { result.append("原恢复方式最多20项。") }
        for (index,value) in recoveries.enumerated() {
            let name = "恢复方式 \(index + 1)"
            guard let row = value.object, Set(row.keys).isSubset(of:["recoveryKey","kind","limit","hpDelta","hpFloor","actKeys"]) else { result.append(name + "含非原合同字段；不会丢弃原字段。"); continue }
            if let key = row["recoveryKey"]?.text, Self.validKey(key), keys.insert(key).inserted {} else { result.append(name + "须有唯一原标识：小写字母起始，后续小写字母、数字或下划线，总长1–32。") }
            if let limit = row["limit"]?.integer, (1...99).contains(limit) {} else { result.append(name + "须明确填写1–99次。") }
            if row["kind"] == .string("REST") {
                if row["hpFloor"] != nil || !Self.validAmount(row["hpDelta"]) { result.append(name + "休整须明确填写1–999生命增加量，不能含救助下限。") }
            } else if row["kind"] == .string("RESCUE") {
                if row["hpDelta"] != nil || !Self.validAmount(row["hpFloor"]) { result.append(name + "救助须明确填写1–999生命下限，不能含休整增加量。") }
            } else { result.append(name + "须明确选择REST或RESCUE。") }
            if let value = row["actKeys"] {
                if let list = value.array, list.count <= 200, list.allSatisfy({ $0.text.map(acts.contains) == true }), Set(list.compactMap(\.text)).count == list.count {} else { result.append(name + "限用幕必须来自原幕目录且不重复。") }
            }
        }
        return result
    }
    private static func originalFields(_ text: String) throws -> [String: ProjectEditJSON] {
        let fields = try ApprovedTopicReleaseWire.envelope(Data(text.utf8))
        func unique(_ value: ContentDraftJSON) throws {
            switch value {
            case .object(let fields):
                var seen = Set<String>()
                for (bytes, child) in fields {
                    guard let key = String(data: bytes, encoding: .utf8), seen.insert(key).inserted else { throw Failure.unsupported }
                    try unique(child)
                }
            case .array(let values): for child in values { try unique(child) }
            default: break
            }
        }
        try unique(ContentDraftJSON.parse(text)); return fields
    }
    private static func validKey(_ value: String) -> Bool { value.range(of:"^[a-z][a-z0-9_]{0,31}$",options:.regularExpression) != nil }
    private static func validAmount(_ value: ProjectEditJSON?) -> Bool { guard let number = value?.integer else { return false }; return (1...999).contains(number) }
    public func applying(to draft: ProjectEditDraft) throws -> ProjectEditDraft {
        guard ProjectEditPendingMaterials.exactData(draft) == originalDraftBytes,
              let raw = draft.preserved["themeRuntimeConfig"]?.text, let original = originalTheme.text, raw.utf8.elementsEqual(original.utf8) else { throw Failure.changed }
        guard issues.isEmpty else { throw Failure.invalid }
        if let bytes = ProjectEditPendingMaterials.exactData(originalDefinition), ProjectEditPendingMaterials.exactData(theme) == bytes { return draft }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(ProjectEditJSON.object(theme))
        guard let text = String(data:bytes,encoding:.utf8), text.utf16.count <= 200_000 else { throw Failure.invalid }
        var next = draft; next.preserved["themeRuntimeConfig"] = .string(text); return next
    }
}
