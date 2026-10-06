import SwiftUI

/// A pending-material story sheet edits the same real chapter in the editor's draft. This
/// capability identifies that existing host; it is neither an upload grant nor a temporary draft.
@MainActor final class ProjectStoryMediaChapterScope {
    let id: UUID
    let chapterID: String
    private weak var controller: ProjectEditPendingController?
    private let original: ProjectEditPendingController.Destination
    fileprivate init(controller: ProjectEditPendingController, original: ProjectEditPendingController.Destination, chapterID: String) {
        self.controller = controller; self.original = original; self.chapterID = chapterID; id = original.id
    }
    func isCurrent(editor: ProjectEditModel, chapterID: String) -> Bool {
        guard let controller, controller.model === editor, controller.isCurrent(original), self.chapterID == chapterID else { return false }
        return editor.draft.chapters.contains { $0.id == chapterID && $0.blocks != nil }
    }
    func chapter(editor: ProjectEditModel, chapterID: String) -> Binding<ProjectEditChapter>? {
        guard isCurrent(editor: editor, chapterID: chapterID), let controller else { return nil }
        return controller.storyChapter(original)
    }
}

@MainActor extension ProjectEditPendingController {
    func captureStoryMediaScope(_ original: Destination) -> ProjectStoryMediaChapterScope? {
        guard isCurrent(original), case .story(let chapterID) = original.kind,
              model.draft.chapters.first(where: { $0.id == chapterID })?.blocks != nil else { return nil }
        return .init(controller: self, original: original, chapterID: chapterID)
    }
}

/// Only the ordinary editor and a controller-minted pending story host can open media. An
/// arbitrary chapter Binding never gains access merely by sharing IDs or equal chapter bytes.
@MainActor enum ProjectStoryMediaChapterHost {
    case ordinary
    case pending(ProjectStoryMediaChapterScope)
    case unavailable
    func allows(editor: ProjectEditModel, chapterID: String) -> Bool {
        switch self {
        case .ordinary: return true
        case .pending(let scope): return scope.isCurrent(editor: editor, chapterID: chapterID)
        case .unavailable: return false
        }
    }
}
