import SwiftUI

@MainActor final class ProjectStoryTemplatePresentation: ObservableObject {
    enum Target: Equatable {
        case storyGap(ProjectStoryTemplateTarget)
        case nodeReference(ProjectNodeTemplateSelectionTarget)
        func applying(_ selected: ProjectStoryTemplateDraft, to draft: ProjectEditDraft,
                      identity: ProjectEditDraftIdentity, session: ProjectEditSession) throws -> ProjectEditDraft {
            switch self {
            case .storyGap(let target): return try target.applying(selected, to: draft, identity: identity, session: session)
            case .nodeReference(let target): return try target.applying(selected, to: draft, identity: identity, session: session)
            }
        }
    }
    struct Opening: Identifiable {
        let id = UUID()
        let lease: ProjectEditStarterController.Lease
        let target: Target
        let draftRevision: Int
        let sourceID: UUID
        let source: any ProjectStoryTemplateReading
    }
    struct Review: Identifiable {
        let id = UUID()
        let source: ProjectStoryTemplateDraft
        let draft: ProjectEditDraft
    }
    enum State: String { case idle, loading, ready, resolving, applying, failed, saveFailed, changed, saveRequired, unsupported }
    @Published private(set) var opening: Opening?
    @Published private(set) var rows: [ProjectStoryTemplateRow] = []
    @Published private(set) var review: Review?
    @Published private(set) var state: State = .idle
    @Published private(set) var nextPage: Int?
    private let editor: ProjectEditModel
    private let host: ProjectStoryMediaChapterHost
    private var request: Task<Void, Never>?
    private var requestID: UUID?
    init(editor: ProjectEditModel, host: ProjectStoryMediaChapterHost = .ordinary) { self.editor = editor; self.host = host }
    var busy: Bool { [.loading, .resolving, .applying].contains(state) }
    func capture(chapterID: String, before blockID: String?) -> Opening? {
        guard opening == nil, host.allows(editor: editor, chapterID: chapterID),
              let lease = editor.captureStarterLease(), let source = editor.coordinator.storyTemplateSource,
              source.isCurrent(session: lease.session),
              let target = try? ProjectStoryTemplateTarget(draft: editor.draft, identity: lease.identity, session: lease.session, chapterID: chapterID, before: blockID) else { return nil }
        return .init(lease: lease, target: .storyGap(target), draftRevision: editor.draftMutationRevision, sourceID: source.identity, source: source)
    }
    func captureNode(chapterID: String, nodeID: String) -> Opening? {
        guard opening == nil, let lease = editor.captureStarterLease(), let source = editor.coordinator.storyTemplateSource,
              source.isCurrent(session: lease.session),
              let target = try? ProjectNodeTemplateSelectionTarget(draft: editor.draft, identity: lease.identity, session: lease.session, chapterID: chapterID, nodeID: nodeID) else { return nil }
        return .init(lease: lease, target: .nodeReference(target), draftRevision: editor.draftMutationRevision, sourceID: source.identity, source: source)
    }
    func isCurrent(_ original: Opening) -> Bool {
        guard editor.isCurrentStarterLease(original.lease), editor.draftMutationRevision == original.draftRevision,
              let source = editor.coordinator.storyTemplateSource, source.identity == original.sourceID,
              ObjectIdentifier(source) == ObjectIdentifier(original.source), source.isCurrent(session: original.lease.session) else { return false }
        let target: Target
        switch original.target {
        case .storyGap(let saved):
            guard host.allows(editor: editor, chapterID: saved.gap.chapterID),
                  let current = try? ProjectStoryTemplateTarget(draft: editor.draft, identity: original.lease.identity, session: original.lease.session,
                      chapterID: saved.gap.chapterID, before: saved.gap.beforeBlockID) else { return false }
            target = .storyGap(current)
        case .nodeReference(let saved):
            guard let current = try? ProjectNodeTemplateSelectionTarget(draft: editor.draft, identity: original.lease.identity, session: original.lease.session,
                chapterID: saved.chapterID, nodeID: saved.nodeID) else { return false }
            target = .nodeReference(current)
        }
        return target == original.target
    }
    @discardableResult func open(_ original: Opening) -> Task<Void, Never>? {
        guard opening == nil, isCurrent(original) else { return nil }
        if case .storyGap = original.target {
            guard editor.canReplaceExistingStoryDraft() else { state = .saveRequired; return nil }
        }
        opening = original; rows = []; review = nil; nextPage = nil
        return load(original, page: 1)
    }
    @discardableResult func refresh(_ original: Opening) -> Task<Void, Never>? {
        guard owns(original), !busy else { return nil }
        rows = []; review = nil; nextPage = nil
        return load(original, page: 1)
    }
    @discardableResult func loadMore(_ original: Opening) -> Task<Void, Never>? {
        guard owns(original), state == .ready, review == nil, let nextPage else { return nil }
        return load(original, page: nextPage)
    }
    private func owns(_ original: Opening) -> Bool { opening?.id == original.id && isCurrent(original) }
    private func load(_ original: Opening, page: Int) -> Task<Void, Never> {
        let stamp = UUID(); requestID = stamp; state = .loading
        let task = Task { [weak self] in
            do {
                let result = try await original.source.list(page: page, session: original.lease.session)
                guard let self, self.accepts(stamp, original) else { return }
                let ids = self.rows.map { $0.id.rawValue } + result.rows.map { $0.id.rawValue }
                guard Set(ids).count == ids.count, result.rows.allSatisfy({ $0.accountID == original.lease.session.accountID }),
                      result.nextPage == nil || result.nextPage == page + 1 else { throw ProjectStoryTemplateError.invalidResponse }
                self.rows += result.rows; self.nextPage = result.nextPage; self.state = .ready
            } catch {
                guard let self, self.accepts(stamp, original) else { return }
                self.rows = []; self.nextPage = nil; self.review = nil; self.state = .failed
            }
            self?.finishRequest(stamp)
        }
        request = task; return task
    }
    @discardableResult func select(_ row: ProjectStoryTemplateRow, original: Opening) -> Task<Void, Never>? {
        guard owns(original), [.ready, .failed, .changed, .unsupported].contains(state), rows.contains(row), review == nil else { return nil }
        return resolve(row.id, expected: row, original: original)
    }
    /// A real /draft receipt supplies this member ID. Still owner-read before preview and again before apply.
    @discardableResult func openCreatedNode(_ original: Opening, id: MemberPlayTemplateID) -> Task<Void, Never>? {
        guard opening == nil, isCurrent(original), case .nodeReference = original.target else { return nil }
        opening = original; rows = []; review = nil; nextPage = nil
        return resolve(id, expected: nil, original: original)
    }
    @discardableResult func refreshCreatedNode(_ original: Opening, id: MemberPlayTemplateID) -> Task<Void, Never>? {
        guard owns(original), !busy, review == nil, case .nodeReference = original.target else { return nil }
        return resolve(id, expected: nil, original: original)
    }
    private func resolve(_ id: MemberPlayTemplateID, expected: ProjectStoryTemplateRow?, original: Opening) -> Task<Void, Never> {
        let stamp = UUID(); requestID = stamp; state = .resolving
        let task = Task { [weak self] in
            do {
                let source = try await original.source.detail(id: id, session: original.lease.session)
                guard let self, self.accepts(stamp, original) else { return }
                guard source.row.id == id, source.row.accountID == original.lease.session.accountID,
                      expected == nil || source.row == expected else { throw ProjectStoryTemplateError.sourceChanged }
                let next = try original.target.applying(source, to: self.editor.draft, identity: original.lease.identity, session: original.lease.session)
                self.review = .init(source: source, draft: next); self.state = .ready
            } catch {
                guard let self, self.accepts(stamp, original) else { return }; self.review = nil
                if case .nodeReference = original.target, error as? ProjectStoryTemplateError == .unsupported { self.state = .unsupported }
                else { self.state = .failed }
            }
            self?.finishRequest(stamp)
        }
        request = task; return task
    }
    func back(_ original: Opening) {
        guard owns(original), !busy else { return }; review = nil; state = .ready
    }
    @discardableResult func apply(_ selected: Review, original: Opening, authorization: @escaping @MainActor () -> Bool = { true }) -> Task<Void, Never>? {
        guard authorization(), owns(original), review?.id == selected.id, [.ready, .saveFailed].contains(state) else { return nil }
        // Claim synchronously before the second owner read. A read never applies by itself.
        let stamp = UUID(); requestID = stamp; state = .applying
        let task = Task { [weak self] in
            do {
                let current = try await original.source.detail(id: selected.source.row.id, session: original.lease.session)
                guard let self, self.accepts(stamp, original), self.review?.id == selected.id else { return }
                guard authorization() else { self.close(original); return }
                guard current == selected.source else { throw ProjectStoryTemplateError.sourceChanged }
                // No suspension between this final capability check and the local write.
                guard authorization() else { self.close(original); return }
                let saved: Bool
                switch original.target {
                case .storyGap: saved = self.editor.persistExistingStoryChange(selected.draft, lease: original.lease)
                case .nodeReference:
                    if ProjectEditPendingMaterials.exactData(selected.draft) == ProjectEditPendingMaterials.exactData(self.editor.draft) { self.close(original); return }
                    saved = self.editor.persistLocalChange(selected.draft, lease: original.lease)
                }
                guard saved else { self.state = .saveFailed; self.finishRequest(stamp); return }
                self.close(original)
            } catch {
                guard let self, self.accepts(stamp, original) else { return }; self.review = nil; self.state = .changed
            }
            self?.finishRequest(stamp)
        }
        request = task; return task
    }
    private func accepts(_ stamp: UUID, _ original: Opening) -> Bool { !Task.isCancelled && requestID == stamp && owns(original) }
    private func finishRequest(_ stamp: UUID) { guard requestID == stamp else { return }; request = nil; requestID = nil }
    func close(_ original: Opening) {
        guard opening?.id == original.id else { return }
        request?.cancel(); request = nil; requestID = nil; opening = nil; rows = []; review = nil; nextPage = nil; state = .idle
    }
    func binding(_ original: Opening?) -> Binding<Opening?> {
        .init(get: { guard let original, self.owns(original) else { return nil }; return original },
              set: { if $0 == nil, let original { self.close(original) } })
    }
}
