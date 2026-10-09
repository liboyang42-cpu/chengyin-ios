import SwiftUI

@MainActor final class ProjectDraftStoryPreviewController: ObservableObject {
    struct Capture {
        let controller: UUID
        let generation: Int
        let lease: ProjectEditStarterController.Lease
        let revision: Int
        let projection: ProjectDraftStoryPreview
    }
    struct Presentation: Identifiable { let id = UUID(); let capture: Capture }
    let model: ProjectEditModel
    private let identity = UUID()
    private var generation = 0
    @Published private(set) var presentation: Presentation?
    @Published private(set) var selectedChapter = 0
    init(model: ProjectEditModel) { self.model = model }
    func capture(_ projection: ProjectDraftStoryPreview) -> Capture? {
        guard model.fullEdit, projection.reason == nil, projection.isCurrent(in: model.draft),
              let lease = model.captureStarterLease() else { return nil }
        return .init(controller: identity, generation: generation, lease: lease,
                     revision: model.draftMutationRevision, projection: projection)
    }
    private func current(_ capture: Capture) -> Bool {
        capture.controller == identity && capture.generation == generation && model.fullEdit &&
        model.isCurrentStarterLease(capture.lease) && model.draftMutationRevision == capture.revision &&
        capture.projection.isCurrent(in: model.draft)
    }
    func open(_ capture: Capture) {
        guard presentation == nil, current(capture) else { return }
        selectedChapter = 0; presentation = .init(capture: capture)
    }
    func isCurrent(_ original: Presentation) -> Bool { presentation?.id == original.id && current(original.capture) }
    @discardableResult func select(_ index: Int, in original: Presentation) -> Bool {
        guard isCurrent(original), original.capture.projection.chapters.indices.contains(index) else { return false }
        selectedChapter = index; return true
    }
    func synchronize() { if let presentation, !isCurrent(presentation) { retire() } }
    func close(_ original: Presentation) { guard presentation?.id == original.id else { return }; retire() }
    func retire() { presentation = nil; selectedChapter = 0; generation += 1 }
    func binding(_ original: Presentation?) -> Binding<Presentation?> {
        .init(get: { guard let original, self.isCurrent(original) else { return nil }; return original },
              set: { if $0 == nil, let original { self.close(original) } })
    }
}

@MainActor struct ProjectDraftStoryPreviewEntry: View {
    @ObservedObject private var model: ProjectEditModel
    @StateObject private var controller: ProjectDraftStoryPreviewController
    init(model: ProjectEditModel) {
        self.model = model; _controller = StateObject(wrappedValue: .init(model: model))
    }
    var body: some View {
        let projection = ProjectDraftStoryPreview(draft: model.draft)
        let captured = controller.capture(projection)
        let original = controller.presentation
        Section {
            Button { if let captured { controller.open(captured) } } label: {
                Text("projectDraftStoryPreview.open", tableName: "ProjectDraftStoryPreview")
            }.disabled(captured == nil || original != nil).accessibilityIdentifier("projectDraftStoryPreview.open")
            if let reason = projection.reason {
                Text(LocalizedStringKey("projectDraftStoryPreview.reason." + reason.rawValue), tableName: "ProjectDraftStoryPreview").font(.caption)
            }
        }
        .sheet(item: controller.binding(original)) { original in ProjectDraftStoryPreviewView(controller: controller, original: original) }
        .onChange(of: model.draftMutationRevision) { _, _ in controller.synchronize() }
        .onChange(of: model.editorIncarnation) { _, _ in controller.retire() }
        .onChange(of: model.coordinator.session) { _, _ in controller.synchronize() }
        .onDisappear { controller.retire() }
    }
}

@MainActor struct ProjectDraftStoryPreviewView: View {
    @ObservedObject var controller: ProjectDraftStoryPreviewController
    @ObservedObject private var model: ProjectEditModel
    let original: ProjectDraftStoryPreviewController.Presentation
    init(controller: ProjectDraftStoryPreviewController, original: ProjectDraftStoryPreviewController.Presentation) {
        self.controller = controller; self.original = original; model = controller.model
    }
    private var projection: ProjectDraftStoryPreview { original.capture.projection }
    private func text(_ key: String) -> Text { Text(LocalizedStringKey("projectDraftStoryPreview." + key), tableName: "ProjectDraftStoryPreview") }
    var body: some View {
        NavigationStack {
            ScrollViewReader { scroll in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        Color.clear.frame(height: 0).id("storyPreviewTop")
                        if controller.isCurrent(original) {
                            VStack(alignment: .leading, spacing: 8) {
                                if projection.title.isEmpty { text("untitledTopic").font(.title.bold()) }
                                else { Text(verbatim: projection.title).font(.title.bold()) }
                                if !projection.subtitle.isEmpty { Text(verbatim: projection.subtitle).font(.subheadline) }
                                text("scope").font(.footnote)
                                text("mediaScope").font(.footnote).foregroundStyle(.secondary)
                                if projection.excludedPendingCount > 0 {
                                    LabeledContent { Text(verbatim: String(projection.excludedPendingCount)) } label: { text("pendingExcluded") }
                                }
                            }
                            if projection.chapters.isEmpty { text("empty") }
                            else if projection.chapters.indices.contains(controller.selectedChapter) {
                                chapter(projection.chapters[controller.selectedChapter])
                            }
                        } else { text("stale") }
                    }.padding().frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: controller.selectedChapter) { _, _ in scroll.scrollTo("storyPreviewTop", anchor: .top) }
            }
            .navigationTitle(text("title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("action.close") { controller.close(original) } } }
            .safeAreaInset(edge: .bottom) {
                if controller.isCurrent(original), !projection.chapters.isEmpty {
                    VStack(spacing: 8) {
                        Picker(selection: Binding(get: { controller.selectedChapter }, set: { _ = controller.select($0, in: original) })) {
                            ForEach(projection.chapters.indices, id: \.self) { index in
                                Text(verbatim: "\(index + 1) · " + projection.chapters[index].title).tag(index)
                            }
                        } label: { text("chapter") }
                        .accessibilityIdentifier("projectDraftStoryPreview.chapter")
                        HStack {
                            Button { _ = controller.select(controller.selectedChapter - 1, in: original) } label: { text("previous") }
                                .disabled(controller.selectedChapter == 0).accessibilityIdentifier("projectDraftStoryPreview.previous")
                            Spacer()
                            Text(verbatim: "\(controller.selectedChapter + 1) / \(projection.chapters.count)")
                                .accessibilityLabel(text("chapterPosition"))
                                .accessibilityValue(Text(verbatim: "\(controller.selectedChapter + 1) / \(projection.chapters.count)"))
                            Spacer()
                            Button { _ = controller.select(controller.selectedChapter + 1, in: original) } label: { text("next") }
                                .disabled(controller.selectedChapter + 1 >= projection.chapters.count).accessibilityIdentifier("projectDraftStoryPreview.next")
                        }.buttonStyle(.bordered)
                    }.padding().background(.regularMaterial)
                }
            }
            .onDisappear { controller.close(original) }
        }
    }
    @ViewBuilder private func chapter(_ chapter: ProjectDraftStoryPreview.Chapter) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            text("role." + chapter.role.rawValue).font(.subheadline).foregroundStyle(.secondary)
            if chapter.title.isEmpty { text("untitledChapter").font(.title2.bold()) }
            else { Text(verbatim: chapter.title).font(.title2.bold()) }
            if chapter.role == .ending { text("endingScope").font(.footnote) }
        }.accessibilityAddTraits(.isHeader)
        if chapter.unsupported { text("unsupportedChapter") }
        else {
            if chapter.rows.isEmpty { text("emptyChapter") }
            ForEach(chapter.rows) { row in
                VStack(alignment: .leading, spacing: 10) {
                    text("kind." + row.kind.rawValue).font(.caption).foregroundStyle(.secondary)
                    if row.conditional { text("conditional").font(.footnote) }
                    if row.unsupported { text("unsupportedBlock").font(.footnote).foregroundStyle(.secondary) }
                    if !row.title.isEmpty { Text(verbatim: row.title).font(.headline) }
                    if !row.text.isEmpty { Text(verbatim: row.text).textSelection(.enabled) }
                    else if [.text, .voice, .narrative, .reveal].contains(row.kind) { text("emptyText").foregroundStyle(.secondary) }
                    if row.kind == .node { text("nodeScope").font(.footnote).foregroundStyle(.secondary) }
                    if row.kind == .image || row.kind == .audio {
                        text(row.emptyMediaReference ? "emptyMedia" : "mediaReference").font(.footnote)
                    }
                    if row.kind == .album {
                        if row.details.isEmpty { text("emptyAlbum") }
                        ForEach(row.details.indices, id: \.self) { index in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(verbatim: String(index + 1)).font(.caption)
                                if row.details[index].isEmpty { text("emptyCaption").foregroundStyle(.secondary) }
                                else { Text(verbatim: row.details[index]).textSelection(.enabled) }
                            }
                        }
                    }
                    if row.kind == .mood || row.kind == .odd { text("effectScope").font(.footnote).foregroundStyle(.secondary) }
                }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .contain)
                    .accessibilityIdentifier("projectDraftStoryPreview.row." + String(row.id))
            }
            if chapter.unplacedNodeCount > 0 {
                LabeledContent { Text(verbatim: String(chapter.unplacedNodeCount)) } label: { text("unplacedNodes") }
            }
        }
    }
}
