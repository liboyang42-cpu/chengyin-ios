import Foundation

/// The existing scan authoring contract; mode switches never erase retained fields.
public struct TemplateScanResponseConfiguration {
    public enum Kind: String, CaseIterable, Identifiable { case text = "TEXT", voice = "VOICE", image = "IMAGE", overlay = "OVERLAY"
        public var id: String { rawValue }
    }
    public enum ARMode: String, CaseIterable, Identifiable { case none = "NONE", plane = "PLANE", marker = "MARKER"
        public var id: String { rawValue }
    }
    public enum TextField: String, CaseIterable, Identifiable { case reply, audioUrl, imageUrl, overlayUrl, markerUrl, modelUrl
        public var id: String { rawValue }
        public var labelKey: String { "creator.field." + rawValue }
    }
    public enum Edit { case kind(Kind), arMode(ARMode), text(TextField, String), scale(Double), clearModel }
    public static let managedFields: Set<String> = ["kind", "reply", "audioUrl", "imageUrl", "overlayUrl", "overlayScale", "arMode", "markerUrl", "modelUrl"]
    public let kind: Kind
    public let arMode: ARMode
    public let scale: Double
    public let isSupported: Bool
    public let canEdit: Bool
    private let fields: [String: TemplateAuthoringJSON]
    private let fingerprint: Data?
    public init(_ draft: TemplateAdvancedDraft) {
        let object = draft.value["scan"]?.object, values = object ?? [:], rawKind = values["kind"], rawAR = values["arMode"], rawScale = values["overlayScale"]
        let selectedKind = Kind(rawValue: rawKind?.string ?? "TEXT"), selectedAR = ARMode(rawValue: rawAR?.string ?? "NONE"), number = rawScale?.number ?? 60, encoded = Self.snapshot(draft)
        let supported = object != nil && encoded != nil && (rawKind == nil || rawKind?.string != nil) && selectedKind != nil && (rawAR == nil || rawAR?.string != nil) && selectedAR != nil &&
            TextField.allCases.allSatisfy({ values[$0.rawValue] == nil || values[$0.rawValue]?.string != nil }) &&
            (rawScale == nil || rawScale?.number != nil) && number.isFinite && number.rounded() == number && (20...100).contains(number)
        fields = values; fingerprint = encoded; kind = selectedKind ?? .text; arMode = selectedAR ?? .none; scale = number
        isSupported = supported; canEdit = supported && draft.enabled("scan")
    }
    public func text(_ field: TextField) -> String { fields[field.rawValue]?.string ?? "" }
    public var currentTextFields: [TextField] {
        var result: [TextField] = [.reply]
        switch kind { case .text: break; case .voice: result.append(.audioUrl); case .image: result.append(.imageUrl)
        case .overlay:
            result.append(.overlayUrl)
            if arMode == .marker { result.append(.markerUrl) }
            if arMode != .none { result.append(.modelUrl) }
        }
        return result
    }
    public var retainedTextFields: [TextField] { TextField.allCases.filter { !currentTextFields.contains($0) && !text($0).isEmpty } }
    public var showsRetainedAR: Bool { kind != .overlay && arMode != .none }
    public var canClearModel: Bool { canEdit && !text(.modelUrl).isEmpty }
    public var previewReference: String? {
        guard isSupported else { return nil }
        switch kind { case .image: return text(.imageUrl); case .overlay: return text(.overlayUrl); default: return nil }
    }
    public var previewWidthPercent: Double { kind == .overlay ? scale : 100 }
    public var previewURL: URL? {
        guard let raw = previewReference, !raw.isEmpty, raw.utf8.count <= 512, !raw.contains("\\"), raw.utf8.allSatisfy({ $0 >= 33 && $0 != 127 }),
              let url = URL(string: raw), url.scheme?.lowercased() == "https", url.host?.isEmpty == false, url.user == nil, url.password == nil, url.fragment == nil else { return nil }
        return url
    }
    public func isCurrent(_ draft: TemplateAdvancedDraft) -> Bool { fingerprint != nil && fingerprint == Self.snapshot(draft) }
    public func applying(_ edit: Edit, to draft: TemplateAdvancedDraft) -> TemplateAdvancedDraft? {
        guard canEdit, isCurrent(draft) else { return nil }
        var next = draft
        switch edit {
        case .kind(let value): next.set("scan", "kind", .string(value.rawValue))
        case .arMode(let value): next.set("scan", "arMode", .string(value.rawValue))
        case .text(let field, let value): next.set("scan", field.rawValue, .string(value))
        case .scale(let value):
            guard kind == .overlay, value.isFinite, value.rounded() == value, (20...100).contains(value) else { return nil }
            next.set("scan", "overlayScale", .number(value))
        case .clearModel:
            guard canClearModel else { return nil }; next.set("scan", "modelUrl", .string(""))
        }
        return next
    }
    private static func snapshot(_ draft: TemplateAdvancedDraft) -> Data? {
        guard let value = draft.value["scan"] else { return nil }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]; return try? encoder.encode(value)
    }
}
