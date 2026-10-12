import Foundation

/// P036 automatic choice memory, represented only by existing ADD_TAG effects.
public struct TemplateChoiceMemory {
    public let family: TemplateCreatorFamily
    public let optionPath: [TemplateCreatorPath]
    public let isSupported: Bool
    public let canEdit: Bool
    public let tags: [String]
    public let otherEffectCount: Int
    public var isEnabled: Bool { !tags.isEmpty }
    public var canEnable: Bool { canEdit && otherEffectCount < 16 }
    public let scopeFingerprint: Data?
    private let fingerprint: Data?
    private var effectsPath: [TemplateCreatorPath] { optionPath + [.field("effects")] }

    public static func isOptionPath(_ family: TemplateCreatorFamily, _ path: [TemplateCreatorPath]) -> Bool {
        func index(_ position: Int) -> Bool { if case .index(let value) = path[position] { return value >= 0 }; return false }
        if family == .qa, path.count == 2 { return path[0] == .field("options") && index(1) }
        if family == .profile, path.count == 4 { return path[0] == .field("questions") && index(1) && path[2] == .field("options") && index(3) }
        return false
    }
    public init(_ draft: TemplateAdvancedDraft, family: TemplateCreatorFamily, optionPath: [TemplateCreatorPath]) {
        self.family = family; self.optionPath = optionPath
        let option = draft.creatorValue(family, path: optionPath)?.object, raw = option?["effects"], rows = raw?.array
        let supported = Self.isOptionPath(family, optionPath) && option != nil && (raw == nil || rows != nil) && (rows ?? []).allSatisfy { raw in
            guard let row = raw.object else { return false }
            for key in ["op", "var"] where row[key] != nil && row[key]?.string == nil { return false }
            if let value = row["value"] {
                switch value { case .string: break; case .number(let number): if !number.isFinite { return false }; default: return false }
            }
            return true
        }
        let encoded = Self.snapshot(draft, family: family); fingerprint = encoded
        isSupported = supported && encoded != nil
        var active = draft.enabled(family.rawValue)
        if family == .qa { active = active && draft.text("qa", "mode") == "PICK" }
        if family == .profile { active = active && draft.creatorValue(family, path: Array(optionPath.prefix(2)))?.object?["kind"]?.string == "pick" }
        canEdit = supported && encoded != nil && active
        tags = supported ? (rows ?? []).filter(Self.isMemory).compactMap { $0.object?["value"]?.string } : []
        otherEffectCount = supported ? (rows ?? []).filter { !Self.isMemory($0) }.count : 0
        if supported {
            var scope = draft; scope.setCreatorValue(family, path: optionPath + [.field("effects")], entry: nil)
            scopeFingerprint = Self.snapshot(scope, family: family)
        } else { scopeFingerprint = nil }
    }
    public func applying(enabled: Bool, to draft: TemplateAdvancedDraft, proposedTag: String? = nil) -> TemplateAdvancedDraft? {
        guard canEdit, fingerprint == Self.snapshot(draft, family: family) else { return nil }
        var kept = (draft.creatorValue(family, path: effectsPath)?.array ?? []).filter { !Self.isMemory($0) }
        if enabled {
            guard kept.count < 16 else { return nil }
            let used = Self.reservedTags(.object(draft.value)), tag: String
            if let proposedTag {
                guard Self.validGeneratedTag(proposedTag), !used.contains(proposedTag) else { return nil }; tag = proposedTag
            } else {
                var candidate: String?
                for _ in 0..<32 { let value = Self.makeTag(); if !used.contains(value) { candidate = value; break } }
                guard let candidate else { return nil }; tag = candidate
            }
            kept.append(.object(["var": .string(""), "op": .string("ADD_TAG"), "value": .string(tag)]))
        }
        var next = draft; next.setCreatorValue(family, path: effectsPath, entry: .array(kept)); return next
    }
    private static func isMemory(_ value: TemplateAuthoringJSON) -> Bool {
        value.object?["op"]?.string == "ADD_TAG" && value.object?["value"]?.string?.hasPrefix("tag.m_") == true
    }
    private static func validGeneratedTag(_ tag: String) -> Bool { tag.range(of: "^tag\\.m_[a-z][a-z0-9]{5}$", options: .regularExpression) != nil }
    private static func makeTag() -> String {
        let letters = Array("abcdefghijklmnopqrstuvwxyz"), rest = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        return "tag.m_" + String(letters.randomElement()!) + String((0..<5).map { _ in rest.randomElement()! })
    }
    private static func reservedTags(_ value: TemplateAuthoringJSON) -> Set<String> {
        switch value {
        case .string(let text): return text.hasPrefix("tag.m_") ? [text] : []
        case .array(let values): return values.reduce(into: Set<String>()) { $0.formUnion(reservedTags($1)) }
        case .object(let fields): return fields.values.reduce(into: Set<String>()) { $0.formUnion(reservedTags($1)) }
        default: return []
        }
    }
    private static func snapshot(_ draft: TemplateAdvancedDraft, family: TemplateCreatorFamily) -> Data? {
        guard let value = draft.value[family.rawValue] else { return nil }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]; return try? encoder.encode(value)
    }
}
