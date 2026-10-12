import Foundation

/// Local photo-check framing fields. Preview URLs are optional; stored relative paths stay intact.
public struct TemplatePhotoFrameConfiguration {
    public enum Edit { case reference(String), opacity(Double), clear }
    public let reference: String
    public let opacity: Double
    public let isSupported: Bool
    public let canEdit: Bool
    public var canClear: Bool { canEdit && !reference.isEmpty }
    public var canAdjustOpacity: Bool { canClear }
    private let fingerprint: Data?
    public init(_ draft: TemplateAdvancedDraft) {
        let fields = draft.value["photoCheck"]?.object, raw = fields?["frameUrl"], rawOpacity = fields?["frameOpacity"]
        let number = rawOpacity?.number ?? 40, encoded = Self.snapshot(draft)
        let supported = fields != nil && (raw == nil || raw?.string != nil) &&
            (rawOpacity == nil || rawOpacity?.number != nil) && number.isFinite && number.rounded() == number && (0...100).contains(number) && encoded != nil
        reference = raw?.string ?? ""; opacity = number; fingerprint = encoded
        isSupported = supported; canEdit = supported && draft.enabled("photoCheck")
    }
    /// No fetching until an explicit UI action. No relative resolution, credentials, fragments or control characters.
    public var previewURL: URL? {
        guard isSupported, !reference.isEmpty, reference.utf8.count <= 512, !reference.contains("\\"),
              reference.utf8.allSatisfy({ $0 >= 33 && $0 != 127 }), let url = URL(string: reference),
              url.scheme?.lowercased() == "https", url.host?.isEmpty == false,
              url.user == nil, url.password == nil, url.fragment == nil else { return nil }
        return url
    }
    public func isCurrent(_ draft: TemplateAdvancedDraft) -> Bool { fingerprint != nil && fingerprint == Self.snapshot(draft) }
    public func applying(_ edit: Edit, to draft: TemplateAdvancedDraft) -> TemplateAdvancedDraft? {
        guard canEdit, isCurrent(draft) else { return nil }
        var next = draft
        switch edit {
        case .reference(let value): next.set("photoCheck", "frameUrl", .string(value))
        case .opacity(let value):
            guard canAdjustOpacity, value.isFinite, value.rounded() == value, (0...100).contains(value) else { return nil }
            next.set("photoCheck", "frameOpacity", .number(value))
        case .clear:
            guard canClear else { return nil }; next.set("photoCheck", "frameUrl", .string(""))
        }
        return next
    }
    private static func snapshot(_ draft: TemplateAdvancedDraft) -> Data? {
        guard let value = draft.value["photoCheck"] else { return nil }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]; return try? encoder.encode(value)
    }
}
