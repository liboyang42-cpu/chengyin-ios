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
    @Environment(\.squareRelatedTopic) private var relatedTopicContext
    @Environment(\.squareDeletion) private var deletion
    @State private var relatedTopic: SquareRelatedTopicSelection?
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
            if let deletion { SquareDeletionStatusView(coordinator: deletion) { Task { await verifyDeletion() } } }
            if reader.isOfflineExample { Text("square.offlineExample").font(.caption) }
            if !reader.isConfigured { SquareIssueView(error: APIError.notConfigured) }
            else if loadedKey != key { ProgressView("square.loading") }
            else {
                if detailLoading { ProgressView("square.loading") }
                if let detailIssue { SquareIssueView(error: detailIssue) { Task { await reload() } } }
                if let post {
                    Section {
                        SquarePostContent(post: post, mediaScope: reader.scope, showsCounts: actions?.identity.accountID == nil).accessibilityIdentifier("square.detailPost")
                        if !post.videos.isEmpty { SquarePostVideoList(videos: post.videos) }
                        SquareRelatedTopicLink(post: post, source: .init(id: id, generation: contentGeneration), squareReader: reader) { relatedTopic = $0 }
                        if let actions, actions.identity.accountID != nil {
                            postActions(post, actions: actions)
                        }
                        if let accountReader, post.memberID > 0 {
                            NavigationLink { SocialPublicProfileView(memberID: post.memberID, reader: accountReader, squareReader: reader, actions: actions) } label: { Label("social.viewAuthor", systemImage: "person.crop.circle") }
                                .accessibilityIdentifier("social.viewAuthor")
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
                        else if comments.items.isEmpty && commentIssue == nil {
                            // Source empty comments: 还没有评论 / 说说你对这条动态的想法吧.
                            Text("square.xcx.noCommentsTitle").foregroundStyle(.secondary).accessibilityIdentifier("square.noComments")
                        }
                        if !commentsLoading && comments.hasMore && commentIssue == nil {
                            Button("square.moreComments") { Task { await loadComments(operation: generation, captured: key) } }.accessibilityIdentifier("square.moreComments")
                        }
                    }
                }
            }
        }
        .appNavigationTitle("square.detail")
        .toolbar {
            // Mini-program `ph-more`: edit, delete and report live in one overflow menu.
            if let post, let actions, actions.identity.accountID != nil, loadedKey == key {
                ToolbarItem(placement: .topBarTrailing) { postMenu(post, actions: actions) }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let post, let actions, actions.identity.accountID != nil, loadedKey == key {
                // Source sticky bar "留下你的评论"; opens the existing reviewed comment editor.
                Button { editor = .init(purpose: .comment, target: .post(post.id), text: "") } label: {
                    Label("square.xcx.commentPlaceholder", systemImage: "text.bubble").frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }.buttonStyle(.bordered).disabled(!post.viewerCanComment).padding(.horizontal).padding(.vertical, 6)
                    .background(.bar).accessibilityIdentifier("square.commentBar")
            }
        }
        .navigationDestination(item: $relatedTopic) { selected in
            if let context = relatedTopicContext {
                SquareRelatedTopicDestination(selection: selected, squareReader: reader, topicReader: context.reader)
            } else { SocialIssueView(error: SocialActionBlock.changed) }
        }
        .onChange(of: key) { _, _ in relatedTopic = nil }
        .onChange(of: relatedTopicContext?.reader.scope) { _, _ in relatedTopic = nil }
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
        .sheet(item: deletionBinding) { item in
            if let deletion { NavigationStack { SquareDeletionConfirmView(target: item.target, excerpt: SquareDeletionConfirmView.excerpt(post?.contents), coordinator: deletion) }.presentationDetents([.medium]) }
        }
        .onChange(of: deletion?.phase) { _, phase in
            // A confirmed comment deletion refreshes the thread; a deleted post leaves no stale body on screen.
            if case .done(let target)? = phase { if case .post = target { post = nil; comments = SquareCommentPagination() } else { Task { await reload() } } }
        }
        .onChange(of: key) { _, _ in deletion?.retire() }
        .task(id: key) { await reload() }
        .refreshable { await reload() }
        .onDisappear { generation += 1; detailLoading = false; commentsLoading = false }
        .accessibilityIdentifier("square.detail")
    }
    /// Mini-program `actions`: like, comment and favourite with their counts. Favourite only where it can work.
    private func postActions(_ post: SquarePost, actions: SocialActionCoordinator) -> some View {
        HStack(spacing: 28) {
            Button { editor = .init(purpose: .like, target: .post(post.id), text: "") } label: {
                Label { Text(max(0, post.likeCount), format: .number) } icon: { Image(systemName: post.isLiked == 1 ? "heart.fill" : "heart") }
            }
            .tint(post.isLiked == 1 ? .red : .primary)
            .accessibilityLabel(Text("square.xcx.likesA11y \(max(0, post.likeCount))")).accessibilityIdentifier("square.detail.like")
            if post.viewerCanComment {
                Button { editor = .init(purpose: .comment, target: .post(post.id), text: "") } label: {
                    Label { Text(max(0, post.commentCount), format: .number) } icon: { Image(systemName: "bubble.right") }
                }
                .tint(.primary)
                .accessibilityLabel(Text("square.xcx.commentsA11y \(max(0, post.commentCount))")).accessibilityIdentifier("square.detail.comment")
            } else {
                Label { Text(max(0, post.commentCount), format: .number) } icon: { Image(systemName: "bubble.right") }
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(Text("square.xcx.commentsA11y \(max(0, post.commentCount))"))
            }
            if post.generation == .communityV1 {
                Button { editor = .init(purpose: .bookmark, target: .post(post.id), text: "") } label: { Image(systemName: "star") }
                    .tint(.primary)
                    .accessibilityLabel(Text("social.editor.bookmark")).accessibilityIdentifier("square.detail.bookmark")
            }
            Spacer(minLength: 0)
        }
        .buttonStyle(.borderless).font(.body).labelStyle(.titleAndIcon)
        .frame(minHeight: 44)
    }
    private func postMenu(_ post: SquarePost, actions: SocialActionCoordinator) -> some View {
        Menu {
            if post.memberID == actions.identity.accountID {
                if workspace != nil || contentGeneration != .communityV1 {
                    Button("square.edit", systemImage: "pencil") { if workspace != nil { showsWorkspaceEdit = true } else { editor = .init(purpose: .editPost, target: .post(post.id), text: post.contents ?? "") } }
                }
                if let target = SquareDeletionTarget(post: post), deletion?.isAllowed(target) == true {
                    Button("square.xcx.delete.post", systemImage: "trash", role: .destructive) { deletion?.prepare(target) }
                        .accessibilityIdentifier("square.delete.postEntry")
                }
            }
            if post.generation != .unknown {
                Button("square.report", systemImage: "exclamationmark.bubble") {
                    if post.generation == .legacySquare { editor = .init(purpose: .report, target: .post(post.id), text: "") }
                    else if let target = try? SquareReportTarget(post: post) { reportTarget = .init(target: target) }
                }
                .accessibilityIdentifier("squareReport.postEntry")
            }
        } label: {
            Label("social.actions", systemImage: "ellipsis.circle").labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityIdentifier("social.post.actions")
    }
    @ViewBuilder private func commentRow(_ comment: SquareComment) -> some View {
        if comment.lifecycle == "DELETED" {
            // Source deleted-row placeholder; the removed body is never shown.
            Text("square.xcx.commentDeleted").font(.footnote).foregroundStyle(.secondary)
                .padding(.leading, comment.parentID == nil ? 0 : 12)
        } else { liveCommentRow(comment) }
    }
    /// Mini-program comment row: avatar, name and time; the text; then like count, reply and the overflow actions.
    private func liveCommentRow(_ comment: SquareComment) -> some View {
        HStack(alignment: .top, spacing: 10) {
            SquareAuthorAvatar(source: comment.avatar, size: 32)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    if let accountReader, comment.memberID > 0 {
                        NavigationLink { SocialPublicProfileView(memberID: comment.memberID, reader: accountReader, squareReader: reader, actions: actions) } label: { commentAuthor(comment) }
                            .buttonStyle(.borderless).tint(.primary)
                    } else {
                        commentAuthor(comment)
                    }
                    Spacer(minLength: 8)
                    if !comment.createTime.isEmpty { SquareXcxRelativeTime(createTime: comment.createTime, now: Date()).font(.caption).foregroundStyle(.secondary) }
                }
                if let name = comment.replyName(in: comments.items) {
                    Text("square.replyingTo \(name)").font(.caption).foregroundStyle(.secondary)
                }
                if let contents = comment.contents { Text(verbatim: contents).textSelection(.enabled) }
                NativeMediaGalleryEntry(sources: comment.images, scope: reader.scope, titleKey: "media.destination.squareImages")
                HStack(spacing: 20) {
                    Label { Text(max(0, comment.likeCount), format: .number) } icon: { Image(systemName: comment.isLiked == 0 ? "heart" : "heart.fill") }
                        .font(.caption).foregroundStyle(.secondary)
                        .accessibilityLabel(Text("square.xcx.likesA11y \(max(0, comment.likeCount))"))
                    Spacer(minLength: 0)
                    if let actions, actions.identity.accountID != nil {
                        Menu {
                            if post?.viewerCanComment == true {
                                Button("social.reply", systemImage: "arrowshape.turn.up.left") { editor = .init(purpose: .comment, target: .comment(postID: id, commentID: comment.id), text: "") }
                            }
                            Button(comment.isLiked == 0 ? LocalizedStringKey("square.like") : LocalizedStringKey("square.unlike"), systemImage: comment.isLiked == 0 ? "heart" : "heart.slash") { editor = .init(purpose: .commentLike, target: .comment(postID: id, commentID: comment.id), text: "", enabled: comment.isLiked == 0) }
                            if comment.generation != .unknown {
                                Button("square.report", systemImage: "exclamationmark.bubble") {
                                    if comment.generation == .legacySquare { editor = .init(purpose: .report, target: .comment(postID: id, commentID: comment.id), text: "") }
                                    else if let post, let target = try? SquareReportTarget(post: post, comment: comment) { reportTarget = .init(target: target) }
                                }
                                .accessibilityIdentifier("squareReport.commentEntry.\(comment.id)")
                            }
                            if comment.memberID == actions.identity.accountID, let post,
                               let target = SquareDeletionTarget(post: post, comment: comment), deletion?.isAllowed(target) == true {
                                Button("square.xcx.delete.comment", systemImage: "trash", role: .destructive) { deletion?.prepare(target) }
                                    .accessibilityIdentifier("square.delete.commentEntry.\(comment.id)")
                            }
                        } label: {
                            Label("social.actions", systemImage: "ellipsis").labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 32)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("social.comment.actions.\(comment.id)")
                    }
                }
            }
        }
        .padding(.leading, comment.parentID == nil ? 0 : 24)
    }
    @ViewBuilder private func commentAuthor(_ comment: SquareComment) -> some View {
        if let nickname = comment.nickname, !nickname.isEmpty { Text(verbatim: nickname).font(.subheadline.weight(.semibold)) }
        else { Text("square.unknownAuthor").font(.subheadline.weight(.semibold)) }
    }
    private struct DeletionRoute: Identifiable { let target: SquareDeletionTarget; var id: SquareDeletionTarget { target } }
    private var deletionBinding: Binding<DeletionRoute?> {
        Binding(get: {
            if case .confirming(let target)? = deletion?.phase { return DeletionRoute(target: target) }
            if case .sending(let target)? = deletion?.phase { return DeletionRoute(target: target) }
            return nil
        }, set: { if $0 == nil { deletion?.cancel() } })
    }
    /// Unknown-outcome readback through the same scoped reads; a failed read keeps the unknown lock.
    private func verifyDeletion() async {
        guard let deletion, case .unknown(let target) = deletion.phase else { return }
        await reload()
        guard loadedKey == key else { return }
        switch target {
        case .post:
            if post != nil { deletion.resolveUnknown(stillPresent: true) }
            else if (detailIssue as? SquareReadFailure) == .unavailable || (detailIssue as? APIError) == .httpStatus(404) { deletion.resolveUnknown(stillPresent: false) }
        case .comment(_, let commentID, _):
            guard post != nil, commentIssue == nil, !comments.hasMore else { return }
            let row = comments.items.first { $0.id == commentID }
            deletion.resolveUnknown(stillPresent: row.map { $0.lifecycle != "DELETED" } ?? false)
        }
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
