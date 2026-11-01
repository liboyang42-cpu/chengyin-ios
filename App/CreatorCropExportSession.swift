import SwiftUI
import UIKit

struct CreatorCropExportDraft: Identifiable {
    let id = UUID()
    let sources: [RetainedSelectedImage]
    let images: [UIImage]
}

/// Draft-ID-fenced batch seam for creator crops. Confirming exports every
/// staged source in order; cancelling drops only the candidate and keeps any
/// previously exported selection. Invalidation is terminal.
@MainActor final class CreatorCropExportSession: ObservableObject {
    @Published private(set) var draft: CreatorCropExportDraft?
    @Published private(set) var selections: [RetainedSelectedImage] = []
    @Published private(set) var failed = false
    private let isCurrent: () -> Bool
    private var active = true

    init(isCurrent: @escaping () -> Bool) { self.isCurrent = isCurrent }

    var selection: RetainedSelectedImage? { selections.first }

    func stage(_ sources: [RetainedSelectedImage]) {
        guard checkCurrent(), !sources.isEmpty else { return }
        draft = nil; failed = false
        do { draft = .init(sources: sources, images: try sources.map(CreatorCropExport.validatedImage)) }
        catch { failed = true }
    }

    @discardableResult func confirm(id: UUID, results: [MiniCropView.Result]) -> [RetainedSelectedImage]? {
        guard checkCurrent(), let candidate = draft, candidate.id == id, results.count == candidate.sources.count else { return nil }
        do {
            let exported = try zip(candidate.sources, results).map { pair in try CreatorCropExport.export(pair.0, result: pair.1) }
            selections = exported; draft = nil; failed = false
            return exported
        } catch { failed = true; return nil }
    }

    func cancel(id: UUID) {
        guard checkCurrent(), draft?.id == id else { return }
        draft = nil; failed = false
    }

    func invalidate() { active = false; draft = nil; selections = []; failed = false }

    private func checkCurrent() -> Bool {
        guard active else { return false }
        guard isCurrent() else { invalidate(); return false }
        return true
    }
}
