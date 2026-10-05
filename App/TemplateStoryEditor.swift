import SwiftUI

/// Explicit local edits only. Opening or returning to this screen never rewrites stored JSON.
@MainActor final class TemplateStoryEditor: ObservableObject {
    let model: TemplateAuthoringModel
    @Published private(set) var beats: [TemplateStoryBeat] = []
    @Published private(set) var issueKey: String?
    @Published private(set) var supported = false
    private var session: TemplateAuthoringSession?
    private var identity: TemplateAuthoringIdentity?
    private var originalJSON: String?
    private var modelGeneration = 0
    private var generation = 0

    init(model: TemplateAuthoringModel) { self.model = model; load() }
    var canEdit: Bool {
        supported && model.canEdit && modelGeneration == model.storyEditorGeneration && session == model.coordinator.session &&
        identity == model.coordinator.identity && originalJSON == model.draft.storyJson
    }
    // Read ownership is independent from write-only locks and comes from the model's captured lease.
    private var hasCurrentReadLease: Bool {
        model.canReadStoryDraft && session != nil && modelGeneration == model.storyEditorGeneration &&
        session == model.coordinator.session && identity == model.coordinator.identity && originalJSON == model.draft.storyJson
    }
    var canRead: Bool { supported && hasCurrentReadLease }
    var visibleBeats: [TemplateStoryBeat] { canRead ? beats : [] }
    var visibleIssueKey: String? { hasCurrentReadLease ? issueKey : nil }
    func load() {
        generation += 1; modelGeneration = model.storyEditorGeneration
        session = model.coordinator.session; identity = model.coordinator.identity
        originalJSON = model.draft.storyJson; issueKey = nil
        do {
            beats = try TemplateAuthoringStory.editableBeats(raw: originalJSON)
            if beats.isEmpty { beats = [.init()] }
            supported = true; issueKey = model.draft.storyProjectionIssue
        } catch { beats = []; supported = false; issueKey = "templateStory.unsupported" }
    }
    func text(_ id: UUID, _ path: WritableKeyPath<TemplateStoryBeat, String>) -> Binding<String> {
        let stamp = generation
        return .init(get: {
            guard self.generation == stamp, self.canRead else { return "" }
            return self.beats.first(where: { $0.id == id })?[keyPath: path] ?? ""
        }, set: { value in
            guard self.generation == stamp, self.canEdit else { return }
            self.model.mediaReferencesWillChange()
            self.apply { rows in
                guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
                rows[index][keyPath: path] = value
            }
        })
    }
    func images(_ id: UUID) -> Binding<String> {
        let stamp = generation
        return .init(get: {
            guard self.generation == stamp, self.canRead else { return "" }
            return self.beats.first(where: { $0.id == id })?.imgs.joined(separator: "\n") ?? ""
        }, set: { value in
            guard self.generation == stamp, self.canEdit else { return }
            self.model.mediaReferencesWillChange()
            self.apply { rows in
                guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
                rows[index].imgs = value.split(separator: "\n").map(String.init)
            }
        })
    }
    func add() { apply { $0.append(.init()) } }
    func remove(_ offsets: IndexSet) {
        guard offsets.allSatisfy({ beats.indices.contains($0) }), offsets.count < beats.count else { return }
        apply { $0.remove(atOffsets: offsets) }
    }
    func move(_ offsets: IndexSet, to destination: Int) {
        guard offsets.allSatisfy({ beats.indices.contains($0) }), (0...beats.count).contains(destination) else { return }
        apply { $0.move(fromOffsets: offsets, toOffset: destination) }
    }
    private func apply(_ edit: (inout [TemplateStoryBeat]) -> Void) {
        guard canEdit else { return }
        var next = beats; edit(&next)
        guard next != beats else { return }
        do {
            var draft = model.draft; try draft.setStory(next)
            model.mediaReferencesWillChange()
            model.draft = draft
            beats = next; originalJSON = draft.storyJson; issueKey = draft.storyProjectionIssue
            model.changed()
        } catch TemplateAuthoringStory.Issue.imageLimit { issueKey = "templateStory.imageLimit" }
        catch { issueKey = "templateStory.unsupported" }
    }
}
