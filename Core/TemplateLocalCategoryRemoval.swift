import Foundation

/// Removal-only local projection. It cannot add IDs, replace malformed text, or read a catalogue.
public struct TemplateLocalCategoryRemoval {
    public let selection: TemplateMetadataCategorySelection
    private let source: Data?
    public init(_ draft: TemplateAuthoringDraft) {
        selection = .init(raw: draft.activityCategoryids)
        source = Self.snapshot(draft)
    }
    public var isSupported: Bool { selection.isSupported && source != nil }
    public var selectedIDs: [Int] { isSupported ? selection.selectedIDs : [] }
    public var original: String? { selection.original }
    public func isCurrent(_ draft: TemplateAuthoringDraft) -> Bool {
        source != nil && source == Self.snapshot(draft)
    }
    public func removing(_ id: Int, from draft: TemplateAuthoringDraft) -> TemplateAuthoringDraft? {
        guard isSupported, selectedIDs.contains(id), isCurrent(draft) else { return nil }
        var nextSelection = selection
        nextSelection.toggle(id)
        var next = draft
        next.activityCategoryids = nextSelection.savedValue
        return next
    }
    private static func snapshot(_ draft: TemplateAuthoringDraft) -> Data? {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try? encoder.encode(draft)
    }
}
