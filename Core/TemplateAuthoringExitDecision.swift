import Foundation

/// A navigation decision only. It never saves, discards, restores or submits a draft.
public struct TemplateAuthoringExitDecision: Equatable {
    public enum Status: Equatable { case clean, unsaved, unverified }
    public let status: Status
    public init(draft: TemplateAuthoringDraft, checkpoint: TemplateAuthoringRestore) {
        guard let current = Self.snapshot(draft) else { status = .unverified; return }
        switch checkpoint {
        case .ready(let saved):
            guard let persisted = Self.snapshot(saved.draft) else { status = .unverified; return }
            status = current == persisted ? .clean : .unsaved
        case .missing:
            status = current == Self.snapshot(TemplateAuthoringDraft()) ? .clean : .unsaved
        case .unavailable, .incompatible, .ownerMismatch: status = .unverified
        }
    }
    public static func snapshot(_ draft: TemplateAuthoringDraft) -> Data? {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try? encoder.encode(draft)
    }
}
