import SwiftUI

struct TemplateImageCropDraft: Identifiable {
    let id = UUID()
    let source: RetainedSelectedImage
}

/// Dormant, in-memory selection seam. Confirmation changes only this local
/// selection; a future host must separately review transmission and fence target
/// mutation with its owner/session/draft/field lease. No URL/proof is minted here.
@MainActor final class TemplateImageCropSession: ObservableObject {
    @Published private(set) var draft: TemplateImageCropDraft?
    @Published private(set) var selection: RetainedSelectedImage?
    @Published private(set) var failed = false
    private let isCurrent: () -> Bool
    private var active = true

    init(selection: RetainedSelectedImage? = nil, isCurrent: @escaping () -> Bool) {
        self.selection = selection; self.isCurrent = isCurrent
    }

    func stage(_ source: RetainedSelectedImage) {
        guard checkCurrent() else { return }
        // Replacing a pending candidate retires its callback even if decoding fails.
        draft = nil; failed = false
        do {
            _ = try TemplateImageCropRenderer.validatedImage(source)
            draft = .init(source: source)
        } catch { failed = true }
    }

    @discardableResult func confirm(id: UUID, rect: TemplateImageCropRect) -> RetainedSelectedImage? {
        guard checkCurrent(), let candidate = draft, candidate.id == id else { return nil }
        do {
            let result = try TemplateImageCropRenderer.render(candidate.source, rect: rect)
            selection = result; draft = nil; failed = false
            return result
        } catch { failed = true; return nil }
    }

    /// Cancel, Back, or dismissal drops only the candidate, never the previous selection.
    func cancel(id: UUID) {
        guard checkCurrent(), draft?.id == id else { return }
        draft = nil; failed = false
    }

    /// The future host must call this on leave/background or a changed lease.
    /// This terminal session releases all image bytes and rejects delayed callbacks.
    func invalidate() { active = false; draft = nil; selection = nil; failed = false }

    private func checkCurrent() -> Bool {
        guard active else { return false }
        guard isCurrent() else { invalidate(); return false }
        return true
    }
}
