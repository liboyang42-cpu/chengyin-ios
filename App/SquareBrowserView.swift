import SwiftUI

/// The session host should observe AppSession and apply .id(reader.scope) to this subtree.
@MainActor struct SquareBrowserView: View {
    let reader: any SquareReading
    var accountReader: (any SocialAccountReading)? = nil
    var actions: SocialActionCoordinator? = nil
    var workspace: SquareWorkspaceCoordinator? = nil
    var governance: SquareGovernanceCoordinator? = nil
    var governanceAccess: ((Int?) -> SquareGovernanceSessionAccess)? = nil
    var onSignIn: (() -> Void)? = nil
    @State private var showsWorkspace = false
    @State private var showsComposer = false
    var onClose: (() -> Void)? = nil
    @State private var query = SquareQuery()
    @State private var keyword = ""
    @State private var cityCode = ""
    @State private var topicCode = ""
    @State private var communityID = ""
    @State private var pagination = SquareFeedPagination()
    @State private var loadedKey: Key?
    @State private var generation = 0
    @State private var loading = false
    @State private var issue: Error?
    @State private var path: [Int] = []
    private struct Key: Hashable { let scope: UUID; let configured: Bool; let query: SquareQuery }
    private var key: Key { Key(scope: reader.scope, configured: reader.isConfigured, query: query) }
    var body: some View {
        NavigationStack(path: $path) {
            List {
                if let workspace {
                    Button("squareWorkspace.title") { showsWorkspace = true }.accessibilityIdentifier("square.workspace.entry")
                        .disabled(workspace.busy)
                }
                if let context = governanceContext(postID: nil) { SquareGovernanceEntryView(context: context) }
                Section {
                    if reader.isOfflineExample { Text("square.offlineExample").font(.caption) }
                    Picker("square.feed", selection: $query.mode) {
                        ForEach(SquareFeedMode.visible, id: \.self) { mode in Text(mode.labelKey).tag(mode) }
                    }.accessibilityIdentifier("square.feed")
                    filters
                }
                if !reader.isConfigured { SquareIssueView(error: APIError.notConfigured) }
                else if query.mode.requiresAccount && !reader.isSignedIn { SquareIssueView(error: SquareReadFailure.signInRequired) }
                else if loadedKey != key { ProgressView("square.loading") }
                else {
                    if let issue { SquareIssueView(error: issue) { Task { await load(reset: !pagination.hasLoadedPage) } } }
                    if pagination.items.isEmpty && !loading && issue == nil { Text("square.empty").accessibilityIdentifier("square.empty") }
                    ForEach(pagination.items) { post in
                        NavigationLink(value: post.id) { SquarePostContent(post: post, compact: true, showImages: false) }
                            .accessibilityIdentifier("square.row.\(post.id)")
                        NativeMediaGalleryEntry(sources: post.images, scope: reader.scope, titleKey: "media.destination.squareImages", compact: true)
                    }
                    if pagination.continuationInvalid { Text("square.invalidCursor").accessibilityIdentifier("square.invalidCursor") }
                    if loading { ProgressView("square.loading") }
                    else if pagination.hasMore && issue == nil {
                        Button("square.loadMore") { Task { await load(reset: false) } }.accessibilityIdentifier("square.loadMore")
                    }
                }
                Section { Text("square.readOnly").font(.footnote).foregroundStyle(.secondary) }
            }
            .appNavigationTitle("square.title")
            .navigationDestination(for: Int.self) { id in SquareDetailView(id: id, contentGeneration: .communityV1, reader: reader, accountReader: accountReader, actions: actions, governanceContext: governanceContext(postID: id), workspace: workspace) }
            .toolbar { if let onClose { ToolbarItem(placement: .cancellationAction) { Button("action.close", action: onClose) } } }
            .toolbar {
                if let actions {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("social.editor.createPost", systemImage: "square.and.pencil") { if workspace != nil { showsWorkspace = true } else { showsComposer = true } }
                            .disabled(actions.identity.accountID == nil).accessibilityIdentifier("social.compose")
                    }
                }
            }
            .sheet(isPresented: $showsComposer) {
                if let actions { NavigationStack { SocialActionEditorView(purpose: .createPost, target: .newPost, coordinator: actions) }.id(actions.identity) }
            }
            .sheet(isPresented: $showsWorkspace) {
                if let workspace { NavigationStack { SquareWorkspaceView(coordinator: workspace) }.id(workspace.session) }
            }
            .searchable(text: $keyword, prompt: "square.search")
            .onSubmit(of: .search) { query.keyword = keyword.isEmpty ? nil : keyword }
            .onChange(of: keyword) { _, value in if value.isEmpty { query.keyword = nil } }
            .onChange(of: reader.scope) { _, _ in path = []; generation += 1; pagination = SquareFeedPagination(); loadedKey = nil }
            .task(id: key) { await load(reset: true) }
            .refreshable { await load(reset: true) }
            .onDisappear { generation += 1; loading = false }
            .accessibilityIdentifier("square.browser")
        }
    }
    private func governanceContext(postID: Int?) -> SquareGovernanceContext? {
        guard let governance, let governanceAccess else { return nil }
        return .init(coordinator: governance, access: governanceAccess(postID), communityPostRead: reader.isConfigured,
            openPost: { id in guard reader.isConfigured, id > 0 else { return }; path.append(id) },
            openDrafts: { if workspace != nil { showsWorkspace = true } }, signIn: { onSignIn?() })
    }
    @ViewBuilder private var filters: some View {
        if query.mode == .nearby {
            Text("square.cityPurpose").font(.caption)
            TextField("square.cityCode", text: $cityCode).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("square.cityCode")
            Button("square.applyFilter") { query.cityCode = cityCode }.accessibilityIdentifier("square.applyFilter")
        } else if query.mode == .topic {
            TextField("square.topicCode", text: $topicCode).textInputAutocapitalization(.never).autocorrectionDisabled()
            Button("square.applyFilter") { query.topicCode = topicCode }
        } else if query.mode == .community {
            TextField("square.communityID", text: $communityID).keyboardType(.numberPad)
            Button("square.applyFilter") { query.communityID = Int(communityID.trimmingCharacters(in: .whitespacesAndNewlines)) }
        }
    }
    private func load(reset: Bool) async {
        guard reset || !loading else { return }
        generation += 1
        let operation = generation, captured = key
        if reset { pagination = SquareFeedPagination(); loadedKey = nil }
        issue = nil
        guard reader.isConfigured, !query.mode.requiresAccount || reader.isSignedIn else { loading = false; return }
        loading = true
        defer { if operation == generation { loading = false } }
        let cursor = reset ? nil : pagination.nextCursor
        do {
            let page = try await reader.squareFeed(query: captured.query, cursor: cursor)
            try Task.checkCancellation()
            guard operation == generation, captured == key else { return }
            try pagination.accept(page, requestedCursor: cursor); loadedKey = captured
        } catch is CancellationError { }
        catch {
            guard operation == generation, captured == key else { return }
            issue = error; loadedKey = captured
        }
    }
}
