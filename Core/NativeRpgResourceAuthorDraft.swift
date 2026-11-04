import Foundation

/// Edits only original schema2 resource declarations. No run balance, refill or role growth is written.
public struct NativeRpgResourceAuthorDraft: Equatable {
    public enum Failure:Error {case unsupported,changed,invalid}
    public static let names = ["hp","morale","luck","inspiration"]
    public let originalRules:ProjectEditJSON
    private let originalDefinition:[String:ProjectEditJSON]
    public private(set) var rules:[String:ProjectEditJSON]
    private var touched:Set<String> = []
    public init(draft:ProjectEditDraft)throws {
        guard case .string(let text)? = draft.preserved["journeyRules"], text.utf8.count <= 24 * 1024 else { throw Failure.unsupported }
        let fields = try Self.originalFields(text)
        guard fields["schemaVersion"] == .number(2),
              Self.names.allSatisfy({fields[$0] == nil || fields[$0]?.object != nil}) else {throw Failure.unsupported}
        originalRules = .string(text);originalDefinition = fields;rules = fields
    }
    public func text(_ name:String,_ field:String)->String {
        guard let value = rules[name]?.object?[field] else{return ""}
        if field == "enabled" {if value == .bool(true){return "true"};if value == .bool(false){return "false"}}
        if let text = value.text{return text};if let value = value.integer{return String(value)};return ""
    }
    public mutating func edit(_ name:String,_ field:String,_ text:String) {
        guard Self.names.contains(name),["enabled","max","init"].contains(field) else{return}
        var row = rules[name]?.object ?? [:]
        if field == "enabled" {
            guard ["","true","false"].contains(text) else{return}
            if text.isEmpty {row.removeValue(forKey:field)}else{row[field] = .bool(text == "true")}
        } else if let value = Int(text),text.range(of:"^[0-9]+$",options:.regularExpression) != nil {row[field] = .number(Decimal(value))}
        else {row[field] = .string(text)}
        rules[name] = .object(row);touched.insert(name)
    }
    public mutating func restore(_ name:String) {
        guard Self.names.contains(name) else{return};rules[name] = originalDefinition[name];touched.remove(name)
    }
    public var stageMoraleFloorText:String {
        guard let value = rules["recovery"]?.object?["stageRestMoraleFloor"] else{return ""}
        if let number = value.integer{return String(number)};return value.text ?? ""
    }
    /// Only this existing optional recovery field changes; other original recovery declarations are preserved.
    public mutating func editStageMoraleFloor(_ text:String) {
        guard rules["recovery"] == nil || rules["recovery"]?.object != nil else{return}
        var recovery = rules["recovery"]?.object ?? [:]
        if text.isEmpty {recovery.removeValue(forKey:"stageRestMoraleFloor")}
        else if let number = Int(text),text.range(of:"^[0-9]+$",options:.regularExpression) != nil {recovery["stageRestMoraleFloor"] = .number(Decimal(number))}
        else {recovery["stageRestMoraleFloor"] = .string(text)}
        if recovery.isEmpty && originalDefinition["recovery"] == nil {rules.removeValue(forKey:"recovery")}
        else {rules["recovery"] = .object(recovery)}
    }
    public mutating func restoreStageMoraleFloor() {
        guard rules["recovery"] == nil || rules["recovery"]?.object != nil else{return}
        var recovery = rules["recovery"]?.object ?? [:]
        recovery["stageRestMoraleFloor"] = originalDefinition["recovery"]?.object?["stageRestMoraleFloor"]
        if recovery.isEmpty && originalDefinition["recovery"] == nil {rules.removeValue(forKey:"recovery")}
        else {rules["recovery"] = .object(recovery)}
    }
    public var issues:[String] {
        var result:[String] = []
        if let floor = rules["recovery"]?.object?["stageRestMoraleFloor"] {
            if let maximum = rules["morale"]?.object?["max"]?.integer,maximum >= 0 {
                if !Self.integer(floor,in:0...maximum){result.append("原阶段士气保底须为0至明确士气上限的整数；不会代填恢复量。")}
            } else {result.append("阶段士气保底需要明确士气上限；不会推定默认上限。")}
        }
        for name in Self.names {
            guard let row = rules[name]?.object else{continue}
            if !Set(row.keys).isSubset(of:["enabled","max","init"]){result.append(name + "含原资源合同之外字段；不会删除它们。");continue}
            if let enabled = row["enabled"],enabled != .bool(true),enabled != .bool(false){result.append(name + "启用配置须为明确布尔值。")}
            let upper = name == "hp" ? 20 : name == "luck" ? 5 : 1000
            let lower = name == "hp" ? 1 : 0
            if row["max"] != nil && !Self.integer(row["max"],in:lower...upper){result.append(name + "上限须为\(lower)–\(upper)整数。")}
            if row["init"] != nil && !Self.integer(row["init"],in:0...Int.max){result.append(name + "初始值须为非负整数。")}
            if let maximum = row["max"]?.integer,let initial = row["init"]?.integer,initial > maximum{result.append(name + "初始值不能超过该资源上限。")}
            if touched.contains(name) && ((row["enabled"] != .bool(true) && row["enabled"] != .bool(false)) || row["max"]?.integer == nil || row["init"]?.integer == nil){result.append(name + "本次编辑须明确启用状态、上限和初始值；不代填默认值。")}
            let floors = name == "hp" ? ["stationEndIfHurt","stageRestHpFloor","exhaustRestHp"] : name == "luck" ? ["stageRestLuckFloor"] : name == "morale" ? ["stageRestMoraleFloor"] : []
            if let maximum = row["max"]?.integer {
                for key in floors {if let value = rules["recovery"]?.object?[key]?.integer,value < 0 || value > maximum{result.append("原recovery.\(key)超出\(name)新上限；保留原值并拒绝预览，不自动改恢复量。")}}
            }
        }
        return result
    }
    public func applying(to draft:ProjectEditDraft)throws->ProjectEditDraft {
        // String Equatable treats Unicode-normalized spellings as equal. An author
        // confirmation belongs to the original bytes, not a later equivalent definition.
        guard let current = draft.preserved["journeyRules"]?.text,let original = originalRules.text,
              current.utf8.elementsEqual(original.utf8) else{throw Failure.changed}
        guard issues.isEmpty else{throw Failure.invalid}
        if rules == originalDefinition{return draft}
        let encoder = JSONEncoder();encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(ProjectEditJSON.object(rules));guard bytes.count <= 24 * 1024,let text = String(data:bytes,encoding:.utf8) else{throw Failure.invalid}
        var next = draft;next.preserved["journeyRules"] = .string(text);return next
    }
    /// Reject duplicate or Unicode-equivalent keys before Foundation can collapse original declarations.
    /// This only refuses ambiguous input; it does not normalize, repair or supply any resource value.
    private static func originalFields(_ text: String) throws -> [String: ProjectEditJSON] {
        func uniqueKeys(_ value: ContentDraftJSON) throws {
            switch value {
            case .object(let fields):
                var seen = Set<String>()
                for (bytes, child) in fields {
                    guard let key = String(data: bytes, encoding: .utf8), seen.insert(key).inserted else { throw Failure.unsupported }
                    try uniqueKeys(child)
                }
            case .array(let values): for child in values { try uniqueKeys(child) }
            default: break
            }
        }
        do {
            try uniqueKeys(ContentDraftJSON.parse(text))
            guard let fields = try JSONDecoder().decode(ProjectEditJSON.self, from: Data(text.utf8)).object else { throw Failure.unsupported }
            return fields
        } catch { throw Failure.unsupported }
    }
    private static func integer(_ value:ProjectEditJSON?,in range:ClosedRange<Int>)->Bool {guard let number = value?.integer else{return false};return range.contains(number)}
}
