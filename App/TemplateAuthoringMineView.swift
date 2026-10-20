import SwiftUI

/// Exact TemplateApi own-shelf. This is not the generic MyProjectApi manager.
@MainActor struct TemplateAuthoringMineView: View {
    let coordinator: TemplateAuthoringCoordinator
    let sessionRevision: UInt64
    var memberDetail: ((MemberPlayTemplateID) -> AnyView)? = nil
    var ownerConfiguration: ((MemberPlayTemplateID) -> AnyView)? = nil
    var creatorConsent: ((WorkshopCreatorConsentSelection) -> AnyView)? = nil
    var fixtureSignOut: (() -> Void)? = nil
    @Environment(\.locale) private var creatorLocale
    @State private var selectedCreatorConsent: WorkshopCreatorConsentSelection?
    @State private var selectedMember: MemberPlayTemplateID?
    @State private var selectedConfiguration: MemberPlayTemplateID?
    @State private var keyword = ""
    @State private var appliedKeyword: String?
    @State private var hasMore = false
    @State private var readMessageKey: String?
    @State private var viewRequest = UUID()
    @State private var rows: [DiscoveryPlayTemplate] = []
    @State private var rowStates: [Int: TemplateOwnShelfStateProjection] = [:]
    @State private var messageKey: String?
    @State private var review: TemplateOwnShelfReview?
    @State private var busy = false
    @State private var locked = true
    @State private var readSnapshot = false
    var body: some View {
        List {
            Section {
                Text("templateAuthor.mineScope").foregroundStyle(.secondary)
                Text("templateAuthor.shelf.pageScope").font(.caption)
                if !coordinator.canRead { Text("templateAuthor.unavailable") }
                TextField("templateAuthor.shelf.keyword", text: $keyword)
                    .submitLabel(.search)
                    .onSubmit { Task { await refresh() } }
                    .disabled(busy).accessibilityIdentifier("templateAuthor.shelf.keyword")
                if !keyword.isEmpty {
                    Button {
                        guard !busy else { return }
                        let stamp = viewRequest
                        keyword = ""
                        Task { await refreshClearedKeyword(stamp: stamp, refreshUnfiltered: true) }
                    } label: {
                        Label {
                            Text(verbatim: creatorLocale.language.languageCode?.identifier == "zh" ? "清除搜索" : "Clear search")
                        } icon: { Image(systemName: "xmark.circle") }
                    }.disabled(busy).accessibilityIdentifier("templateAuthor.shelf.clearSearch")
                }
                Button("templateAuthor.shelf.refresh") { Task { await refresh() } }
                    .disabled(busy).accessibilityIdentifier("templateAuthor.shelf.refresh")
            }
            ForEach(appliedKeyword == keyword ? rows : []) { row in
                Section {
                    Text(verbatim: row.title).font(.headline)
                    if let id = MemberPlayTemplateID(rawValue: row.id), memberDetail != nil {
                        Button { selectedMember = id } label: { Label("memberTemplate.title", systemImage: "doc.text.magnifyingglass") }
                            .accessibilityIdentifier("memberTemplate.mine.\(row.id)")
                    }
                    if let id = MemberPlayTemplateID(rawValue: row.id), ownerConfiguration != nil {
                        Button("templateOwnerConfig.open") { selectedConfiguration = id }
                            .accessibilityIdentifier("templateOwnerConfig.open.\(row.id)")
                    }
                    if let id = MemberPlayTemplateID(rawValue: row.id), creatorConsent != nil {
                        Button(workshopCreatorLocalized("workshopCreator.open", locale: creatorLocale)) { selectedCreatorConsent = WorkshopCreatorConsentSelection(source: id) }
                            .accessibilityIdentifier("workshopCreator.open.\(row.id)")
                    }
                    LabeledContent("templateAuthor.shelf.identity", value: String(row.id))
                    if let text = row.description { Text(verbatim: text) }
                    let state = rowStates[row.id] ?? .unknown
                    LabeledContent("templateShelfState.personal.title") { Text(LocalizedStringKey(state.personal.rawValue)) }
                        .accessibilityIdentifier("templateShelfState.personal.\(row.id)")
                    LabeledContent("templateShelfState.market.title") { Text(LocalizedStringKey(state.market.rawValue)) }
                        .accessibilityIdentifier("templateShelfState.market.\(row.id)")
                    if let reason = state.marketReason {
                        LabeledContent("templateShelfState.market.feedback") { Text(verbatim: reason).textSelection(.enabled) }
                            .accessibilityIdentifier("templateShelfState.feedback.\(row.id)")
                    }
                    Text("templateAuthor.existingEditUnavailable").font(.caption).foregroundStyle(.secondary)
                    Button(LocalizedStringKey(row.publishStatus == 1 ? "templateAuthor.shelf.removeLibrary" : "templateAuthor.shelf.addLibrary")) {
                        prepare(row.id, .libraryStatus)
                    }.disabled(!coordinator.canSubmit || locked || busy || !coordinator.rows.contains(row)).accessibilityIdentifier("templateAuthor.shelf.library.\(row.id)")
                        .disabled(readSnapshot)
                    Button("templateAuthor.shelf.delete", role: .destructive) { prepare(row.id, .remove) }
                        .disabled(!coordinator.canSubmit || locked || busy || !coordinator.rows.contains(row)).accessibilityIdentifier("templateAuthor.shelf.delete.\(row.id)")
                        .disabled(readSnapshot)
                }
            }
            if hasMore, appliedKeyword == keyword {
                Button("templateAuthor.shelf.loadMore") { Task { await loadMore() } }
                    .disabled(busy).accessibilityIdentifier("templateAuthor.shelf.loadMore")
            }
            if appliedKeyword == keyword, let readMessageKey { Text(LocalizedStringKey(readMessageKey)).accessibilityIdentifier("templateAuthor.shelf.readStatus") }
            if appliedKeyword == keyword, let messageKey { Text(LocalizedStringKey(messageKey)).accessibilityIdentifier("templateAuthor.shelf.status") }
        }.navigationTitle("templateAuthor.mine")
            // Stable typed destination survives invalidation of its source list on push.
            .navigationDestination(item: $selectedMember) { id in
                if let memberDetail { memberDetail(id) }
            }
            .navigationDestination(item: $selectedConfiguration) { id in
                if let ownerConfiguration { ownerConfiguration(id) }
            }
            .navigationDestination(item: $selectedCreatorConsent) { selection in
                if let creatorConsent { creatorConsent(selection) }
            }
            .onChange(of: keyword) { _, newValue in
                review = nil
                coordinator.cancelShelfReview()
                // An empty field is a submitted clear. Non-empty drafts stay unapplied.
                guard newValue.isEmpty, appliedKeyword?.isEmpty == false else { return }
                let stamp = viewRequest
                Task { await refreshClearedKeyword(stamp: stamp) }
            }
            .onChange(of: sessionRevision) { _, _ in selectedCreatorConsent = nil }
            .onChange(of: sessionRevision) { _, _ in selectedConfiguration = nil }
            .onChange(of: sessionRevision) { _, _ in selectedMember = nil }
            .task(id: sessionRevision) { viewRequest = UUID(); busy = false; rows = []; review = nil; rowStates = [:]; await refresh() }
            .onDisappear { viewRequest = UUID(); coordinator.shelfReader.leave(); coordinator.leaveShelfScreen(); rows = []; review = nil; busy = false; rowStates = [:] }
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
        rowStates = coordinator.shelfReader.rowStates
        readSnapshot = coordinator.shelfReader.isShowingRefreshSnapshot
        readMessageKey = coordinator.shelfReader.messageKey; messageKey = coordinator.shelfMessageKey; locked = coordinator.shelfLocked
    }
    private func prepare(_ id: Int, _ action: TemplateOwnShelfAction) {
        guard !busy, appliedKeyword == keyword, !coordinator.shelfReader.isShowingRefreshSnapshot else { return }
        coordinator.prepareShelf(templateID: id, action: action); review = coordinator.shelfReview; sync()
    }
    private func loadMore() async {
        guard !busy, appliedKeyword == keyword else { return }
        let stamp = viewRequest; busy = true; review = nil; coordinator.cancelShelfReview()
        await coordinator.shelfReader.loadMore()
        guard stamp == viewRequest, !Task.isCancelled else { return }
        sync(); busy = false
    }
    private func refreshClearedKeyword(stamp: UUID, refreshUnfiltered: Bool = false) async {
        guard stamp == viewRequest, keyword.isEmpty, !Task.isCancelled else { return }
        // Explicit Clear still refreshes an already-unfiltered shelf. The first
        // refresh rotates viewRequest before suspension, retiring a duplicate listener task.
        guard refreshUnfiltered || appliedKeyword?.isEmpty == false else { return }
        await refresh()
    }
    private func refresh() async {
        guard !busy else { return }
        appliedKeyword = keyword
        let stamp = UUID(); viewRequest = stamp
        defer {
            if stamp == viewRequest, Task.isCancelled {
                rows = []; hasMore = false; readSnapshot = false; busy = false; rowStates = [:]
            }
        }
        busy = true; review = nil; hasMore = false; readMessageKey = nil; messageKey = nil
        coordinator.synchronizeSession(); coordinator.cancelShelfReview()
        rows = coordinator.shelfReader.refreshSnapshot(keyword: keyword)
        rowStates = rows.isEmpty ? [:] : coordinator.shelfReader.rowStates
        readSnapshot = !rows.isEmpty
        await coordinator.shelfReader.refresh(keyword: keyword)
        guard stamp == viewRequest, !Task.isCancelled else { return }
        // Preserve the independent, unfiltered first-100 write preflight and reconciliation.
        if coordinator.canSubmit { await coordinator.loadMine() }
        guard stamp == viewRequest, !Task.isCancelled else { return }
        sync(); busy = false
    }
}
