import SwiftUI

@MainActor struct SquareDetailView: View {
    let id: Int
    var contentGeneration: SquareContentGeneration = .legacySquare
    let reader: any SquareReading
    var accountReader: (any SocialAccountReading)? = nil
    var actions: SocialActionCoordinator? = nil
    var governanceContext: SquareGovernanceContext? = nil
    var workspace: SquareWorkspaceCoordinator? = nil
    @Environment(\.squareReportContext) private var reportContext
    @State private var reportTarget: ReportRoute?
    private struct ReportRoute: Identifiable { let id = UUID(); let target: SquareReportTarget }
    @State private var showsWorkspaceEdit = false
    private struct EditorRoute: Identifiable { let id = UUID(); let purpose: SocialEditorPurpose; let target: SocialActionTarget; let text: String; var enabled = true }
    @State private var editor: EditorRoute?
    @State private var post: SquarePost?
    @State private var detailIssue: Error?
    @State private var commentIssue: Error?
    @State private var comments = SquareCommentPagination()
    @State private var detailLoading = false
    @State private var commentsLoading = false
    @State private var generation = 0
    @State private var loadedKey: Key?
    private struct Key: Hashable { let id: Int; let generation: SquareContentGeneration; let scope: UUID; let configured: Bool }
    private var key: Key { Key(id: id, generation: contentGeneration, scope: reader.scope, configured: reader.isConfigured) }
    var body: some View {
        List {
            if let governanceContext { SquareGovernanceEntryView(context: governanceContext) }
            if reader.isOfflineExample { Text("square.offlineExample").font(.caption) }
            if !reader.isConfigured { SquareIssueView(error: APIError.notConfigured) }
            else if loadedKey != key { ProgressView("square.loading") }
            else {
                if detailLoading { ProgressView("square.loading") }
                if let detailIssue { SquareIssueView(error: detailIssue) { Task { await reload() } } }
                if let post {
                    Section {
                        SquarePostContent(post: post, mediaScope: reader.scope).accessibilityIdentifier("square.detailPost")
                        if let accountReader, post.memberID > 0 {
                            NavigationLink { SocialPublicProfileView(memberID: post.memberID, reader: accountReader, squareReader: reader, actions: actions) } label: { Label("social.viewAuthor", systemImage: "person.crop.circle") }
                                .accessibilityIdentifier("social.viewAuthor")
                        }
                        if let actions {
                            postActions(post, actions: actions)
                        }
                    }
                }
                // Detail failure never renders orphan comments without their post context.
                if post != nil {
                    Section("square.comments") {
                        if let commentIssue { SquareIssueView(error: commentIssue) { Task { await loadComments(operation: generation, captured: key) } } }
                        ForEach(SquareComment.threaded(comments.items)) { comment in
                            commentRow(comment).accessibilityIdentifier("square.comment.\(comment.id)")
                        }
                        if commentsLoading { ProgressView("square.commentsLoading") }
                        else if comments.items.isEmpty && commentIssue == nil { Text("square.noComments").accessibilityIdentifier("square.noComments") }
                        if !commentsLoading && comments.hasMore && commentIssue == nil {
                            Button("square.moreComments") { Task { await loadComments(operation: generation, captured: key) } }.accessibilityIdentifier("square.moreComments")
                        }
                    }
                }
                Section { Text("square.readOnly").font(.footnote).foregroundStyle(.secondary) }
            }
        }
        .appNavigationTitle("square.detail")
        .sheet(item: $editor) { item in
            if let actions { NavigationStack { SocialActionEditorView(purpose: item.purpose, target: item.target, coordinator: actions, initialText: item.text, contentGeneration: contentGeneration, initialEnabled: item.enabled) }.id(actions.identity) }
        }
        .sheet(item: $reportTarget) { item in
            NavigationStack { SquareReportView(target: item.target, context: reportContext) }
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showsWorkspaceEdit) {
            if let workspace { NavigationStack { SquareWorkspaceView(coordinator: workspace, initialPostID: id, initialLane: contentGeneration == .communityV1 ? .communityV1 : .legacy) }.id(workspace.session) }
        }
        .task(id: key) { await reload() }
        .refreshable { await reload() }
        .onDisappear { generation += 1; detailLoading = false; commentsLoading = false }
        .accessibilityIdentifier("square.detail")
    }
    @ViewBuilder private func postActions(_ post: SquarePost, actions: SocialActionCoordinator) -> some View {
        if actions.identity.accountID != nil {
            Button("social.editor.comment") { editor = .init(purpose: .comment, target: .post(post.id), text: "") }.disabled(!post.viewerCanComment)
            Menu {
                Button("social.editor.like") { editor = .init(purpose: .like, target: .post(post.id), text: "") }
                Button("social.editor.bookmark") { editor = .init(purpose: .bookmark, target: .post(post.id), text: "") }
                    .disabled(post.generation != .communityV1)
                if post.memberID == actions.identity.accountID {
                    Button("social.editor.editPost") { if workspace != nil { showsWorkspaceEdit = true } else { editor = .init(purpose: .editPost, target: .post(post.id), text: post.contents ?? "") } }
                        .disabled(contentGeneration == .communityV1 && workspace == nil)
                }
                Button("social.editor.report") {
                    if post.generation == .legacySquare { editor = .init(purpose: .report, target: .post(post.id), text: "") }
                    else if let target = try? SquareReportTarget(post: post) { reportTarget = .init(target: target) }
                }.disabled(post.generation == .unknown)
                    .accessibilityIdentifier("squareReport.postEntry")
            } label: {
                Text("social.actions").frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }.buttonStyle(.borderless).accessibilityIdentifier("social.post.actions")
            if post.generation == .legacySquare { Text("squareReport.legacyBookmarkBoundary").font(.footnote).foregroundStyle(.secondary) }
        } else { Text("social.signIn").font(.footnote) }
    }
    private func commentRow(_ comment: SquareComment) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let nickname = comment.nickname, !nickname.isEmpty { Text(verbatim: nickname).font(.headline) }
            else { Text("square.unknownAuthor").font(.headline) }
            if let accountReader, comment.memberID > 0 {
                NavigationLink { SocialPublicProfileView(memberID: comment.memberID, reader: accountReader, squareReader: reader, actions: actions) } label: { Text("social.viewAuthor") }
            }
            if let actions, actions.identity.accountID != nil {
                Menu {
                    Button("social.reply") { editor = .init(purpose: .comment, target: .comment(postID: id, commentID: comment.id), text: "") }.disabled(post?.viewerCanComment != true)
                    Button("social.editor.commentLike") { editor = .init(purpose: .commentLike, target: .comment(postID: id, commentID: comment.id), text: "", enabled: comment.isLiked == 0) }
                    Button("social.editor.report") {
                        if comment.generation == .legacySquare { editor = .init(purpose: .report, target: .comment(postID: id, commentID: comment.id), text: "") }
                        else if let post, let target = try? SquareReportTarget(post: post, comment: comment) { reportTarget = .init(target: target) }
                    }.disabled(comment.generation == .unknown)
                        .accessibilityIdentifier("squareReport.commentEntry.\(comment.id)")
                } label: {
                    Text("social.actions").frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }.buttonStyle(.borderless).accessibilityIdentifier("social.comment.actions.\(comment.id)")
            }
            if let name = comment.replyName(in: comments.items) { LabeledContent("square.replyTo", value: name).font(.caption) }
            if let contents = comment.contents { Text(verbatim: contents).textSelection(.enabled) }
            NativeMediaGalleryEntry(sources: comment.images, scope: reader.scope, titleKey: "media.destination.squareImages")
            LabeledContent("square.likes", value: String(max(0, comment.likeCount))).font(.caption)
            if !comment.createTime.isEmpty { Text(verbatim: comment.createTime).font(.caption).foregroundStyle(.secondary) }
        }.padding(.leading, comment.parentID == nil ? 0 : 12)
    }
    private func reload() async {
        generation += 1
        let operation = generation, captured = key
        post = nil; comments = SquareCommentPagination(); detailIssue = nil; commentIssue = nil
        detailLoading = false; commentsLoading = false; loadedKey = captured
        guard reader.isConfigured else { return }
        detailLoading = true
        // Independent read states: a comment failure does not discard a successfully loaded post.
        async let detailTask: Void = loadDetail(operation: operation, captured: captured)
        async let commentTask: Void = loadComments(operation: operation, captured: captured)
        _ = await (detailTask, commentTask)
    }
    private func loadDetail(operation: Int, captured: Key) async {
        defer { if operation == generation { detailLoading = false } }
        do {
            let value = try await reader.squareDetail(route: .init(id: id, generation: contentGeneration))
            try Task.checkCancellation()
            guard operation == generation, captured == key else { return }
            post = value
        } catch is CancellationError { }
        catch { if operation == generation, captured == key { detailIssue = error } }
    }
    private func loadComments(operation: Int, captured: Key) async {
        guard !commentsLoading, comments.hasMore, operation == generation, captured == key else { return }
        commentsLoading = true; commentIssue = nil
        defer { if operation == generation { commentsLoading = false } }
        do {
            let page = try await reader.squareComments(route: .init(id: id, generation: contentGeneration), pageNumber: comments.nextPage)
            try Task.checkCancellation()
            guard operation == generation, captured == key else { return }
            try comments.accept(page)
        } catch is CancellationError { }
        catch { if operation == generation, captured == key { commentIssue = error } }
    }
}
