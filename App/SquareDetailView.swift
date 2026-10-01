import SwiftUI

@MainActor struct SquareDetailView: View {
    let id: Int
    let reader: any SquareReading
    @State private var post: SquarePost?
    @State private var detailIssue: Error?
    @State private var commentIssue: Error?
    @State private var comments = SquareCommentPagination()
    @State private var detailLoading = false
    @State private var commentsLoading = false
    @State private var generation = 0
    @State private var loadedKey: Key?
    private struct Key: Hashable { let id: Int; let scope: UUID; let configured: Bool }
    private var key: Key { Key(id: id, scope: reader.scope, configured: reader.isConfigured) }
    var body: some View {
        List {
            if reader.isOfflineExample { Text("square.offlineExample").font(.caption) }
            if !reader.isConfigured { SquareIssueView(error: APIError.notConfigured) }
            else if loadedKey != key { ProgressView("square.loading") }
            else {
                if detailLoading { ProgressView("square.loading") }
                if let detailIssue { SquareIssueView(error: detailIssue) { Task { await reload() } } }
                if let post { Section { SquarePostContent(post: post).accessibilityIdentifier("square.detailPost") } }
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
        .task(id: key) { await reload() }
        .refreshable { await reload() }
        .onDisappear { generation += 1; detailLoading = false; commentsLoading = false }
        .accessibilityIdentifier("square.detail")
    }
    private func commentRow(_ comment: SquareComment) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let nickname = comment.nickname, !nickname.isEmpty { Text(verbatim: nickname).font(.headline) }
            else { Text("square.unknownAuthor").font(.headline) }
            if let name = comment.replyName(in: comments.items) { LabeledContent("square.replyTo", value: name).font(.caption) }
            if let contents = comment.contents { Text(verbatim: contents).textSelection(.enabled) }
            ForEach(Array(comment.images.enumerated()), id: \.offset) { _, image in SquareImage(source: image) }
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
            let value = try await reader.squareDetail(id: id)
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
            let page = try await reader.squareComments(postID: id, pageNumber: comments.nextPage)
            try Task.checkCancellation()
            guard operation == generation, captured == key else { return }
            try comments.accept(page)
        } catch is CancellationError { }
        catch { if operation == generation, captured == key { commentIssue = error } }
    }
}
