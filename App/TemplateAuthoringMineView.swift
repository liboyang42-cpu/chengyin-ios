import SwiftUI

/// Exact TemplateApi own-shelf. This is not the generic MyProjectApi manager.
@MainActor struct TemplateAuthoringMineView: View {
    let coordinator: TemplateAuthoringCoordinator
    let sessionRevision: UInt64
    var memberDetail: ((MemberPlayTemplateID) -> AnyView)? = nil
    var fixtureSignOut: (() -> Void)? = nil
    @State private var selectedMember: MemberPlayTemplateID?
    @State private var keyword = ""
    @State private var hasMore = false
    @State private var readMessageKey: String?
    @State private var viewRequest = UUID()
    @State private var rows: [DiscoveryPlayTemplate] = []
    @State private var messageKey: String?
    @State private var review: TemplateOwnShelfReview?
    @State private var busy = false
    @State private var locked = true
    var body: some View {
        List {
            Section {
                Text("templateAuthor.mineScope").foregroundStyle(.secondary)
                Text("templateAuthor.shelf.pageScope").font(.caption)
                if !coordinator.canSubmit { Text("templateAuthor.unavailable") }
                TextField("templateAuthor.shelf.keyword", text: $keyword)
                    .disabled(busy).accessibilityIdentifier("templateAuthor.shelf.keyword")
                Button("templateAuthor.shelf.refresh") { Task { await refresh() } }
                    .disabled(busy).accessibilityIdentifier("templateAuthor.shelf.refresh")
            }
            ForEach(rows) { row in
                Section {
                    Text(verbatim: row.title).font(.headline)
                    if let id = MemberPlayTemplateID(rawValue: row.id), memberDetail != nil {
                        Button { selectedMember = id } label: { Label("memberTemplate.title", systemImage: "doc.text.magnifyingglass") }
                            .accessibilityIdentifier("memberTemplate.mine.\(row.id)")
                    }
                    LabeledContent("templateAuthor.shelf.identity", value: String(row.id))
                    if let text = row.description { Text(verbatim: text) }
                    Text(LocalizedStringKey(row.status == 1 ? "templateAuthor.published" : row.status == 2 ? "templateAuthor.underReview" : "templateAuthor.unpublished"))
                    Text(LocalizedStringKey(row.publishStatus == 1 ? "templateAuthor.shelf.inLibrary" : "templateAuthor.shelf.outLibrary"))
                    Text("templateAuthor.existingEditUnavailable").font(.caption).foregroundStyle(.secondary)
                    Button(LocalizedStringKey(row.publishStatus == 1 ? "templateAuthor.shelf.removeLibrary" : "templateAuthor.shelf.addLibrary")) {
                        prepare(row.id, .libraryStatus)
                    }.disabled(locked || busy || !coordinator.rows.contains(row)).accessibilityIdentifier("templateAuthor.shelf.library.\(row.id)")
                    Button("templateAuthor.shelf.delete", role: .destructive) { prepare(row.id, .remove) }
                        .disabled(locked || busy || !coordinator.rows.contains(row)).accessibilityIdentifier("templateAuthor.shelf.delete.\(row.id)")
                }
            }
            if hasMore {
                Button("templateAuthor.shelf.loadMore") { Task { await loadMore() } }
                    .disabled(busy).accessibilityIdentifier("templateAuthor.shelf.loadMore")
            }
            if let readMessageKey { Text(LocalizedStringKey(readMessageKey)).accessibilityIdentifier("templateAuthor.shelf.readStatus") }
            if let messageKey { Text(LocalizedStringKey(messageKey)).accessibilityIdentifier("templateAuthor.shelf.status") }
        }.navigationTitle("templateAuthor.mine")
            // Stable typed destination survives invalidation of its source list on push.
            .navigationDestination(item: $selectedMember) { id in
                if let memberDetail { memberDetail(id) }
            }
            .onChange(of: sessionRevision) { _, _ in selectedMember = nil }
            .task(id: sessionRevision) { rows = []; review = nil; await refresh() }
            .onDisappear { viewRequest = UUID(); coordinator.shelfReader.leave(); coordinator.leaveShelfScreen(); rows = []; review = nil; busy = false }
            .sheet(item: $review, onDismiss: { coordinator.cancelShelfReview() }) { value in
                NavigationStack {
                    Form {
                        Section("templateAuthor.reviewTitle") {
                            Text(verbatim: value.title)
                            LabeledContent("templateAuthor.shelf.identity", value: String(value.templateID.rawValue))
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(Text("templateAuthor.shelf.identity"))
                                .accessibilityValue(Text(verbatim: String(value.templateID.rawValue)))
                                .accessibilityIdentifier("templateAuthor.shelf.identity")
                            Text(LocalizedStringKey(value.action == .remove ? "templateAuthor.shelf.deleteReview" : value.desiredPublishStatus == 1 ? "templateAuthor.shelf.addReview" : "templateAuthor.shelf.removeReview"))
                            Text("templateAuthor.shelf.readback")
                        }
                        if coordinator.canSimulate { Text("templateAuthor.fixtureNotice") }
                        if coordinator.canSubmit {
                            Button(LocalizedStringKey(coordinator.canSimulate ? "templateAuthor.confirmSimulation" : "templateAuthor.confirmRequest"), role: value.action == .remove ? .destructive : nil) {
                                busy = true; locked = true
                                Task {
                                    let stamp = viewRequest
                                    await coordinator.confirmShelf(value)
                                    guard stamp == viewRequest, !Task.isCancelled else { return }
                                    review = nil
                                    await coordinator.shelfReader.refresh(keyword: keyword)
                                    guard stamp == viewRequest, !Task.isCancelled else { return }
                                    sync(); busy = false
                                }
                            }.disabled(busy).accessibilityIdentifier("templateAuthor.shelf.confirm")
                        } else { Text("templateAuthor.unavailable") }
                    }.navigationTitle("templateAuthor.reviewTitle")
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("templateAuthor.cancel") { coordinator.cancelShelfReview(); review = nil }
                                    .accessibilityIdentifier("templateAuthor.shelf.cancel")
                            }
                            #if DEBUG
                            ToolbarItem(placement: .topBarTrailing) {
                                if let fixtureSignOut {
                                    Button("templateAuthor.fixture.signOut", action: fixtureSignOut)
                                        .accessibilityIdentifier("fixtureTemplate.review.signOut")
                                }
                            }
                            #endif
                        }
                }
            }
    }
    private func sync() {
        coordinator.synchronizeSession(); coordinator.shelfReader.synchronizeSession()
        rows = coordinator.shelfReader.rows; hasMore = coordinator.shelfReader.hasMore
        readMessageKey = coordinator.shelfReader.messageKey; messageKey = coordinator.shelfMessageKey; locked = coordinator.shelfLocked
    }
    private func prepare(_ id: Int, _ action: TemplateOwnShelfAction) {
        coordinator.prepareShelf(templateID: id, action: action); review = coordinator.shelfReview; sync()
    }
    private func loadMore() async {
        let stamp = viewRequest; busy = true; review = nil; coordinator.cancelShelfReview()
        await coordinator.shelfReader.loadMore()
        guard stamp == viewRequest, !Task.isCancelled else { return }
        sync(); busy = false
    }
    private func refresh() async {
        let stamp = UUID(); viewRequest = stamp
        busy = true; review = nil; rows = []; hasMore = false; readMessageKey = nil; messageKey = nil
        coordinator.synchronizeSession()
        await coordinator.shelfReader.refresh(keyword: keyword)
        guard stamp == viewRequest, !Task.isCancelled else { return }
        // Preserve the independent, unfiltered first-100 write preflight and reconciliation.
        await coordinator.loadMine()
        guard stamp == viewRequest, !Task.isCancelled else { return }
        sync(); busy = false
    }
}
