import SwiftUI

/// Additive host context. Session closures reuse the host's ClubReadIdentity epoch.
/// Factory is absent by default; constructing a context never enables writes/uploads.
@MainActor
struct ClubCommunityContext {
    let service: ClubCommunityService
    let currentSession: () throws -> ClubCommunitySession
    let coordinator: ClubCommunityCoordinator?
    let evidence: (Int, ClubCommunityPost?, ClubCommunityComment?) async throws -> ClubCommunityEvidence
    var images: any ClubCommunityImageUploading = ClubCommunityDisabledImages()
    var postImagePicker: ClubPostImagePickerContext = .disabled
    var onAuthor: ((Int) -> Void)? = nil
    var onTopic: ((Int) -> Void)? = nil
}

@MainActor
final class ClubCommunityViewModel: ObservableObject {
    let context: ClubCommunityContext
    @Published private(set) var snapshot: ClubCommunitySnapshot?
    @Published private(set) var imageReadScope = UUID()
    @Published private(set) var loading = false
    @Published var notice: String?
    @Published var review: ClubCommunityReview?
    @Published private(set) var busy = false
    @Published private(set) var pendingRecord: ClubCommunityPendingRecord?
    private var generation: UInt64 = 0
    private var identity: ClubReadIdentity?
    private var pendingDraft: (ClubCommunityOperation, Int, ClubCommunityPost?, ClubReadIdentity)?
    func stageDraft(_ operation: ClubCommunityOperation, clubID: Int, post: ClubCommunityPost?) {
        guard let identity = try? context.currentSession().identity else { return }
        pendingDraft = (operation, clubID, post, identity)
    }
    func reviewPendingDraft() async {
        guard let draft = pendingDraft else { return }; pendingDraft = nil
        guard (try? context.currentSession().identity) == draft.3 else { return }
        await prepare(draft.0, clubID: draft.1, post: draft.2)
    }
    init(context: ClubCommunityContext) { self.context = context }
    func suspend() {
        generation &+= 1; pendingDraft = nil; review = nil; loading = false
        context.coordinator?.cancel()
    }
    func invalidate() {
        suspend(); imageReadScope = UUID(); snapshot = nil; notice = nil; pendingRecord = nil
    }
    private func pendingEvidenceProbe(
        clubID: Int,
        post: ClubCommunityPost? = nil,
        comment: ClubCommunityComment? = nil
    ) -> ClubCommunityEvidence? {
        guard clubID > 0, let session = try? context.currentSession(), session.identity.isSignedIn else { return nil }
        return ClubCommunityEvidence(
            identity: session.identity,
            clubID: clubID,
            joined: false,
            owner: false,
            administrator: false,
            post: post,
            comment: comment
        )
    }
    /// Recovers any durable pending record for `(clubID, post, comment)` on page entry or after restart.
    @discardableResult
    func recoverPendingState(
        clubID: Int,
        post: ClubCommunityPost? = nil,
        comment: ClubCommunityComment? = nil
    ) -> ClubCommunityPendingRecord? {
        guard let coordinator = context.coordinator,
              let probe = pendingEvidenceProbe(clubID: clubID, post: post, comment: comment) else {
            pendingRecord = nil
            return nil
        }
        let locked = coordinator.recoverPendingLock(for: probe)
        let record = coordinator.pendingRecord(for: probe)
        pendingRecord = record
        if locked || record != nil {
            notice = "club.community.unknown"
        }
        return record
    }
    /// Queries the authoritative same-request outcome for an unresolved pending operation on `(clubID, post, comment)`.
    /// Never generates a new request ID, never re-submits the write, and never infers success from list reads.
    func reconcilePending(
        clubID: Int,
        post: ClubCommunityPost? = nil,
        comment: ClubCommunityComment? = nil,
        refresh: ClubCommunityRead
    ) async {
        guard !busy,
              let coordinator = context.coordinator,
              let probe = pendingEvidenceProbe(clubID: clubID, post: post, comment: comment) else {
            notice = "club.community.offline"
            return
        }
        busy = true
        defer { busy = false }
        do {
            let outcome = try await coordinator.reconcilePendingOperation(for: probe)
            pendingRecord = coordinator.pendingRecord(for: probe)
            switch outcome {
            case .acknowledgedRefreshRequired:
                await load(refresh)
                notice = "club.community.refreshRequired"
            case .moderationQueued:
                await load(refresh)
                notice = "club.community.queued"
            case .rejected:
                notice = "club.community.actionUnavailable"
            default:
                notice = "club.community.unknown"
            }
        } catch {
            pendingRecord = coordinator.pendingRecord(for: probe)
            notice = "club.community.unknown"
        }
    }
    func load(_ operation: ClubCommunityRead) async {
        generation &+= 1; let ticket = generation
        imageReadScope = UUID(); snapshot = nil; loading = true; notice = nil
        do {
            let session = try context.currentSession(); identity = session.identity
            let result = try await context.service.read(operation, session: session) {
                guard try self.context.currentSession() == session else { throw ClubCommunityFailure.stale }
            }
            guard ticket == generation, try context.currentSession() == session else { return }
            snapshot = result; loading = false
        } catch {
            guard ticket == generation, (try? context.currentSession().identity) == identity else { return }; loading = false; notice = "club.community.loadError"
        }
    }
    func prepare(_ operation: ClubCommunityOperation, clubID: Int, post: ClubCommunityPost? = nil, comment: ClubCommunityComment? = nil) async {
        guard !busy, let coordinator = context.coordinator else { notice = "club.community.offline"; return }
        if recoverPendingState(clubID: clubID, post: post, comment: comment) != nil {
            notice = "club.community.unknown"
            return
        }
        busy = true; defer { busy = false }
        do {
            let session = try context.currentSession(), ticket = generation
            let evidence = try await context.evidence(clubID, post, comment)
            guard ticket == generation, try context.currentSession() == session else { throw ClubCommunityFailure.stale }
            let candidate = try await coordinator.prepare(operation, evidence: evidence)
            guard ticket == generation, try context.currentSession() == session else { coordinator.cancel(); throw ClubCommunityFailure.stale }
            review = candidate
        } catch {
            _ = recoverPendingState(clubID: clubID, post: post, comment: comment)
            if notice != "club.community.unknown" {
                notice = "club.community.actionUnavailable"
            }
        }
    }
    func confirm(refresh: ClubCommunityRead) async {
        guard !busy, let review, let coordinator = context.coordinator else { return }
        let targetClubID = review.evidence.clubID
        let targetPost = review.evidence.post
        let targetComment = review.evidence.comment
        busy = true; self.review = nil
        do {
            try await coordinator.confirm(review)
            pendingRecord = coordinator.pendingRecord(for: review.evidence)
            let queued = coordinator.outcome == .moderationQueued
            await load(refresh)
            notice = queued ? "club.community.queued" : "club.community.refreshRequired"
        } catch {
            _ = recoverPendingState(clubID: targetClubID, post: targetPost, comment: targetComment)
            notice = coordinator.outcome == .unknownLocked ? "club.community.unknown" : "club.community.actionUnavailable"
        }
        busy = false
    }
    func cancelReview() { review = nil; context.coordinator?.cancel() }
}

@MainActor
struct ClubCommunityEntry: View {
    let clubID: Int
    let identity: ClubReadIdentity
    let context: ClubCommunityContext
    var body: some View {
        NavigationLink {
            ClubCommunityFeedView(context: context, identity: identity, clubID: clubID)
        } label: { Label("club.community.posts", systemImage: "text.bubble") }
            .accessibilityIdentifier("club.community.entry")
    }
}

private struct ClubCommunityDestination: Hashable {
    enum Screen: Hashable { case detail, comments, history }
    let post: ClubCommunityPost
    let clubID: Int?
    let screen: Screen
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.post == rhs.post && lhs.clubID == rhs.clubID && lhs.screen == rhs.screen }
    func hash(into hasher: inout Hasher) { hasher.combine(post.id); hasher.combine(post.version); hasher.combine(clubID); hasher.combine(screen) }
}

@MainActor
struct ClubCommunityFeedView: View {
    let identity: ClubReadIdentity
    let clubID: Int?
    @StateObject private var model: ClubCommunityViewModel
    @State private var page = 1
    @State private var composing = false
    @State private var destination: ClubCommunityDestination?
    @State private var discussion = ClubPostDiscussionState()
    @Environment(\.clubCustomerTopics) private var topics
    @Environment(\.clubPostPlayHost) private var discussionHost
    init(context: ClubCommunityContext, identity: ClubReadIdentity, clubID: Int? = nil) {
        self.identity = identity; self.clubID = clubID; _model = StateObject(wrappedValue: ClubCommunityViewModel(context: context))
    }
    private var operation: ClubCommunityRead { clubID.map { .posts(clubID: $0, page: page) } ?? .feed(page: page) }
    var body: some View {
        List {
            if model.loading { ProgressView().accessibilityLabel(Text("club.community.loading")) }
            if let notice = model.notice { Text(LocalizedStringKey(notice)).accessibilityIdentifier("club.community.notice") }
            if let pending = model.pendingRecord, let clubID {
                VStack(alignment: .leading, spacing: 6) {
                    Text(LocalizedStringKey("club.community.pendingLocked"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("club.community.pendingLocked.\(pending.operationKind)")
                    if model.context.coordinator?.permitsAuthoritativeOutcomeQueries == true {
                        Button("club.community.reconcilePending") {
                            Task { await model.reconcilePending(clubID: clubID, refresh: operation) }
                        }
                        .disabled(model.busy || model.loading)
                        .accessibilityIdentifier("club.community.reconcilePending")
                    }
                }
            }
            if let snapshot = model.snapshot {
                if snapshot.clubCount == 0 { Text("club.community.joinFirst") }
                else if snapshot.posts.isEmpty { Text("club.community.empty") }
                if clubID == nil, snapshot.posts.isEmpty {
                    // Cross-club feed (俱乐部 tab 帖文): the source names the next step for each empty case.
                    Text(LocalizedStringKey(ClubTabPresentation.feedEmptyKeys(clubCount: snapshot.clubCount).detail))
                        .font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("clubTab.feed.emptyHint")
                }
                ForEach(snapshot.posts) { post in
                    let target = discussionTarget(post, acceptedPosts: snapshot.posts)
                    VStack(alignment: .leading, spacing: 8) {
                        ClubCommunityPostTile(post: post, clubID: post.clubID ?? clubID, identity: identity, model: model,
                            commentsExpanded: discussion.selection?.post.id == post.id, canOpenComments: target != nil,
                            openComments: { if let target { toggleDiscussion(target) } },
                            openHistory: { destination = .init(post: post, clubID: post.clubID ?? clubID, screen: .history) },
                            openDetail: { destination = .init(post: post, clubID: post.clubID ?? clubID, screen: .detail) })
                        if let selected = discussion.selection, selected.post == post {
                            ClubPostDiscussionPanel(target: selected, source: model, close: { discussion.close() }).id(selected.id)
                        }
                    }
                }
                HStack {
                    Button("club.community.previous") { page = max(1, page - 1) }.disabled(page == 1)
                    Spacer()
                    Button("club.community.next") { page += 1 }.disabled(snapshot.posts.count < 20)
                }
            }
            Button("club.community.refresh") { Task { await model.load(operation) } }.disabled(model.loading || model.busy)
            if clubID != nil && identity.isSignedIn {
                Button("club.community.create") { composing = true }
                    .disabled(model.busy || model.pendingRecord != nil || model.context.coordinator?.permitsInjectedWrites != true)
                    .accessibilityIdentifier("club.community.compose")
            }
            if model.context.coordinator?.permitsInjectedWrites != true { Text("club.community.offline").foregroundStyle(.secondary) }
        }
        .navigationTitle(Text("club.community.posts"))
        .background(alignment: .topLeading) { ClubPostDiscussionFixtureTraceView() }
        .navigationDestination(item: $destination) { target in
            switch target.screen {
            case .detail:
                ClubCommunityPostDetailView(
                    context: model.context,
                    identity: identity,
                    clubID: target.clubID,
                    post: target.post
                )
            case .comments:
                if let clubID = target.clubID { ClubCommunityCommentsView(context: model.context, identity: identity, clubID: clubID, post: target.post) }
            case .history:
                ClubCommunityHistoryView(context: model.context, identity: identity, postID: target.post.id)
            }
        }
        .onChange(of: identity) { _, _ in destination = nil; discussion.close() }
        .onChange(of: destination) { oldValue, newValue in
            if oldValue != nil, newValue == nil, (try? model.context.currentSession().identity) == identity {
                Task {
                    await model.load(operation)
                    if let clubID { _ = model.recoverPendingState(clubID: clubID) }
                }
            }
        }
        .onChange(of: model.imageReadScope) { _, _ in discussion.close() }
        .onChange(of: topics.viewerRevision) { _, _ in discussion.close() }
        .task(id: identity) {
            model.invalidate()
            page = 1
            await model.load(operation)
            if let clubID { _ = model.recoverPendingState(clubID: clubID) }
        }
        .task(id: page) { await model.load(operation) }
        // Pushing a row destination must not remove the NavigationLink that owns it.
        // Identity changes still clear all private snapshots in the task above.
        .onDisappear { model.suspend() }
        .sheet(isPresented: $composing, onDismiss: { Task { await model.reviewPendingDraft() } }) {
            if let clubID { ClubCommunityComposer(model: model, clubID: clubID, post: nil) }
        }
        .sheet(item: $model.review, onDismiss: { model.cancelReview() }) { review in
            ClubCommunityReviewView(review: review, model: model, refresh: operation)
        }
    }
    private func discussionTarget(_ post: ClubCommunityPost, acceptedPosts: [ClubCommunityPost]) -> ClubPostDiscussionSelection? {
        guard let id = post.clubID ?? clubID else { return nil }
        return .init(post: post, acceptedPosts: acceptedPosts, context: .init(clubID: id, identity: identity,
            readScope: model.imageReadScope, viewerRevision: topics.viewerRevision))
    }
    private func toggleDiscussion(_ target: ClubPostDiscussionSelection) {
        guard !model.busy, (discussionHost?.isCurrent() ?? true), (try? model.context.currentSession().identity) == identity else { return }
        discussion.toggle(target, acceptedPosts: model.snapshot?.posts, context: .init(clubID: target.context.clubID,
            identity: identity, readScope: model.imageReadScope, viewerRevision: topics.viewerRevision))
    }
}

@MainActor
struct ClubCommunityPostTile: View {
    let post: ClubCommunityPost
    let clubID: Int?
    let identity: ClubReadIdentity
    @ObservedObject var model: ClubCommunityViewModel
    var commentsExpanded = false
    var canOpenComments = true
    let openComments: () -> Void
    let openHistory: () -> Void
    var openDetail: (() -> Void)? = nil
    @State private var editing = false
    @State private var evidence: ClubCommunityEvidence?
    private func allows(_ operation: ClubCommunityOperation) -> Bool {
        guard let evidence, evidence.identity == identity, evidence.post == post, Date().timeIntervalSince(evidence.observedAt) < 60 else { return false }
        return evidence.allows(operation)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ClubPostAuthorProfile(post: post, clubID: clubID, identity: identity, model: model)
            ClubPostDiscussionBody(post: post, expanded: commentsExpanded, open: canOpenComments ? openComments : nil)
            ClubPostImageGallery(post: post, clubID: clubID, identity: identity, model: model)
            if !post.sportName.isEmpty, (post.refType == 1 || !post.sportCover.isEmpty) {
                ClubPostReferenceView(post: post, clubID: clubID, identity: identity, model: model, openComments: openComments)
                ClubPostPlayPreview(post: post, clubID: clubID, identity: identity, model: model, openComments: openComments)
            }
            if post.likeCount > 0 || post.commentCount > 0 {
                HStack { Label("\(post.likeCount)", systemImage: "heart"); Label("\(post.commentCount)", systemImage: "bubble") }.accessibilityElement(children: .combine)
            }
            if let clubID {
                HStack {
                    Button { Task { await model.prepare(.toggleLike, clubID: clubID, post: post) } } label: { Label("club.community.like", systemImage: post.liked ? "heart.fill" : "heart") }
                        .disabled(!identity.isSignedIn || model.busy || model.context.coordinator?.permitsInjectedWrites != true)
                    Button(action: openComments) { Label(commentsExpanded ? "club.discussion.collapse" : "club.community.comments", systemImage: "bubble") }
                        .disabled(!canOpenComments)
                        .accessibilityIdentifier("club.community.comments.\(post.id)")
                }
                Menu {
                    if allows(.update(content: post.content, images: post.images, requestID: "display")) { Button("club.community.edit") { editing = true } }
                    if allows(.pin(!post.pinned, requestID: "display")) { Button(post.pinned ? "club.community.unpin" : "club.community.pin") { Task { await model.prepare(.pin(!post.pinned, requestID: UUID().uuidString), clubID: clubID, post: post) } } }
                    if allows(.delete) { Button("club.community.delete", role: .destructive) { Task { await model.prepare(.delete, clubID: clubID, post: post) } } }
                    if allows(.report) { Button("club.community.report") { Task { await model.prepare(.report, clubID: clubID, post: post) } } }
                } label: { Label("club.community.actions", systemImage: "ellipsis") }
                    .disabled(!identity.isSignedIn || model.busy || model.context.coordinator?.permitsInjectedWrites != true)
            }
            HStack(spacing: 12) {
                if let openDetail {
                    Button(action: openDetail) { Text("club.community.detail") }
                        .accessibilityIdentifier("club.community.detail.\(post.id)")
                }
                Button(action: openHistory) { Text("club.community.history") }
                    .accessibilityIdentifier("club.community.history.\(post.id)")
            }
        }
        .buttonStyle(.borderless)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("club.community.post.\(post.id)")
        .task(id: identity) {
            evidence = nil
            if let clubID, let fresh = try? await model.context.evidence(clubID, post, nil), fresh.identity == identity { evidence = fresh }
        }
        .sheet(isPresented: $editing, onDismiss: { Task { await model.reviewPendingDraft() } }) { if let clubID { ClubCommunityComposer(model: model, clubID: clubID, post: post) } }
    }
}

@MainActor
struct ClubCommunityPostDetailView: View {
    let identity: ClubReadIdentity
    let clubID: Int?
    let post: ClubCommunityPost
    @StateObject private var model: ClubCommunityViewModel
    @State private var commentPage = 1
    @State private var showingHistory = false

    init(context: ClubCommunityContext, identity: ClubReadIdentity, clubID: Int?, post: ClubCommunityPost) {
        self.identity = identity
        self.clubID = clubID
        self.post = post
        _model = StateObject(wrappedValue: ClubCommunityViewModel(context: context))
    }

    private var commentsOperation: ClubCommunityRead {
        .comments(postID: post.id, page: commentPage)
    }

    var body: some View {
        List {
            Section {
                ClubCommunityPostTile(
                    post: post,
                    clubID: post.clubID ?? clubID,
                    identity: identity,
                    model: model,
                    commentsExpanded: true,
                    canOpenComments: false,
                    openComments: {},
                    openHistory: { showingHistory = true }
                )
            }
            if let pending = model.pendingRecord, let targetClubID = post.clubID ?? clubID {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(LocalizedStringKey("club.community.pendingLocked"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("club.community.detail.pendingLocked.\(pending.operationKind)")
                        if model.context.coordinator?.permitsAuthoritativeOutcomeQueries == true {
                            Button("club.community.reconcilePending") {
                                Task {
                                    await model.reconcilePending(
                                        clubID: targetClubID,
                                        post: post,
                                        refresh: commentsOperation
                                    )
                                }
                            }
                            .disabled(model.busy || model.loading)
                            .accessibilityIdentifier("club.community.detail.reconcilePending")
                        }
                    }
                }
            }
            Section("club.community.comments") {
                if model.loading { ProgressView() }
                if let notice = model.notice {
                    Text(LocalizedStringKey(notice))
                        .accessibilityIdentifier("club.community.detail.notice")
                }
                if model.snapshot?.comments.isEmpty == true {
                    Text("club.community.noComments")
                }
                ForEach(model.snapshot?.comments ?? []) { comment in
                    VStack(alignment: .leading, spacing: 4) {
                        if comment.nickname.isEmpty {
                            Text("club.community.user")
                        } else {
                            Text(verbatim: comment.nickname)
                        }
                        Text(verbatim: comment.content)
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("club.community.detail.comment.\(comment.id)")
                }
                HStack {
                    Button("club.community.previous") { commentPage = max(1, commentPage - 1) }
                        .disabled(commentPage == 1)
                    Spacer()
                    Button("club.community.next") { commentPage += 1 }
                        .disabled((model.snapshot?.comments.count ?? 0) < 50)
                }
                Button("club.community.refresh") {
                    Task { await model.load(commentsOperation) }
                }
                .disabled(model.loading || model.busy)
                .accessibilityIdentifier("club.community.detail.refresh")
            }
        }
        .navigationTitle(Text("club.community.detail"))
        .navigationDestination(isPresented: $showingHistory) {
            ClubCommunityHistoryView(context: model.context, identity: identity, postID: post.id)
        }
        .task(id: identity) {
            model.invalidate()
            commentPage = 1
            await model.load(commentsOperation)
            if let targetClubID = post.clubID ?? clubID {
                _ = model.recoverPendingState(clubID: targetClubID, post: post)
            }
        }
        .task(id: commentPage) {
            await model.load(commentsOperation)
        }
        .onDisappear { model.suspend() }
        .sheet(item: $model.review, onDismiss: { model.cancelReview() }) { review in
            ClubCommunityReviewView(review: review, model: model, refresh: commentsOperation)
        }
    }
}

@MainActor
struct ClubCommunityComposer: View {
    @ObservedObject var model: ClubCommunityViewModel
    let clubID: Int
    let post: ClubCommunityPost?
    @Environment(\.dismiss) private var dismiss
    @State private var content = ""
    @State private var images: [String] = []
    @State private var uploading = false
    @StateObject private var imageBridge: ClubPostImageComposerBridge
    init(model: ClubCommunityViewModel, clubID: Int, post: ClubCommunityPost?) {
        self.model = model
        self.clubID = clubID
        self.post = post
        _imageBridge = StateObject(
            wrappedValue: ClubPostImageComposerBridge(
                context: model.context.postImagePicker,
                clubID: clubID,
                postID: post?.id
            )
        )
    }
    var body: some View {
        NavigationStack {
            Form {
                TextEditor(text: $content).frame(minHeight: 150).accessibilityLabel(Text("club.community.content"))
                    .accessibilityIdentifier("club.community.content")
                Text("\(content.count)/300").foregroundStyle(.secondary)
                ClubPostImageSectionView(
                    bridge: imageBridge,
                    images: $images,
                    uploading: $uploading,
                    notice: $model.notice
                )
                Button("club.community.review") {
                    let operation: ClubCommunityOperation = post == nil ? .create(content: content, images: images) : .update(content: content, images: images, requestID: UUID().uuidString)
                    model.stageDraft(operation, clubID: clubID, post: post)
                    dismiss()
                }.disabled(model.busy || uploading || imageBridge.isBusy || content.count > 300 || (content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && images.isEmpty))
                    .accessibilityIdentifier("club.community.reviewDraft")
            }
            .navigationTitle(Text(post == nil ? "club.community.create" : "club.community.edit"))
            .toolbar {
                if let post {
                    ClubPostEditExitControl(post: post, clubID: clubID, source: model,
                        content: $content, images: $images, canExit: { !model.busy && !uploading && !imageBridge.isBusy }, close: { dismiss() })
                } else { Button("club.community.cancel") { dismiss() } }
            }
            .onAppear {
                if content.isEmpty && images.isEmpty {
                    content = post?.content ?? ""
                    images = post?.images ?? []
                }
                imageBridge.bind(initialReferences: images)
            }
            .onDisappear {
                imageBridge.invalidate()
            }
        }
        .interactiveDismissDisabled(post.map {
            model.busy || uploading || imageBridge.isBusy || ClubPostEditDraft(content: content, images: images) !=
                ClubPostEditDraft(content: $0.content, images: $0.images)
        } ?? false)
    }
}

@MainActor
struct ClubCommunityReviewView: View {
    let review: ClubCommunityReview
    @ObservedObject var model: ClubCommunityViewModel
    let refresh: ClubCommunityRead
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Text(LocalizedStringKey("club.community." + review.operation.labelKey)).font(.headline)
                LabeledContent("club.community.clubID", value: String(review.evidence.clubID))
                if let post = review.evidence.post { LabeledContent("club.community.postID", value: String(post.id)) }
                if let comment = review.evidence.comment { LabeledContent("club.community.commentID", value: String(comment.id)) }
                switch review.operation {
                case let .create(content, images), let .update(content, images, _):
                    Text(verbatim: content)
                    ForEach(Array(images.enumerated()), id: \.offset) { _, image in Text(verbatim: image) }
                case let .comment(content): Text(verbatim: content)
                case .report, .reportComment: Text("club.community.queuedExplanation")
                case .toggleLike: Text("club.community.toggleWarning")
                case let .pin(pinned, _): Text(pinned ? "club.community.pin" : "club.community.unpin")
                default: Text("club.community.deleteWarning")
                }
                Text("club.community.offline")
                Button("club.community.confirm") { Task { await model.confirm(refresh: refresh); dismiss() } }.disabled(model.busy)
                    .accessibilityIdentifier("club.community.confirm")
                Button("club.community.cancel", role: .cancel) { model.cancelReview(); dismiss() }
            }.navigationTitle(Text("club.community.review"))
        }.interactiveDismissDisabled(model.busy)
    }
}

@MainActor
struct ClubCommunityCommentsView: View {
    let identity: ClubReadIdentity, clubID: Int, post: ClubCommunityPost
    @StateObject private var model: ClubCommunityViewModel
    @State private var content = ""
    @State private var page = 1
    @State private var evidence: ClubCommunityEvidence?
    init(context: ClubCommunityContext, identity: ClubReadIdentity, clubID: Int, post: ClubCommunityPost) {
        self.identity = identity; self.clubID = clubID; self.post = post
        _model = StateObject(wrappedValue: ClubCommunityViewModel(context: context))
    }
    private var operation: ClubCommunityRead { .comments(postID: post.id, page: page) }
    var body: some View {
        List {
            if model.loading { ProgressView() }
            if let notice = model.notice { Text(LocalizedStringKey(notice)) }
            if let pending = model.pendingRecord {
                VStack(alignment: .leading, spacing: 6) {
                    Text(LocalizedStringKey("club.community.pendingLocked"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("club.community.comments.pendingLocked.\(pending.operationKind)")
                    if model.context.coordinator?.permitsAuthoritativeOutcomeQueries == true {
                        Button("club.community.reconcilePending") {
                            Task { await model.reconcilePending(clubID: clubID, post: post, refresh: operation) }
                        }
                        .disabled(model.busy || model.loading)
                        .accessibilityIdentifier("club.community.comments.reconcilePending")
                    }
                }
            }
            if model.snapshot?.comments.isEmpty == true { Text("club.community.noComments") }
            ForEach(model.snapshot?.comments ?? []) { comment in
                VStack(alignment: .leading) {
                    if comment.nickname.isEmpty { Text("club.community.user") } else { Text(verbatim: comment.nickname) }
                    Text(verbatim: comment.content)
                    let moderator = evidence?.owner == true || evidence?.administrator == true || post.viewerCanManage
                    if identity.isSignedIn {
                        let canDelete = comment.memberID == identity.accountID || moderator
                        Button(canDelete ? "club.community.deleteComment" : "club.community.reportComment") {
                            Task { await model.prepare(canDelete ? .deleteComment : .reportComment, clubID: clubID, post: post, comment: comment) }
                        }.disabled(model.busy || model.context.coordinator?.permitsInjectedWrites != true)
                    }
                }.accessibilityElement(children: .contain)
                    .accessibilityIdentifier("club.community.comment.\(comment.id)")
            }
            HStack {
                Button("club.community.previous") { page = max(1, page - 1) }.disabled(page == 1)
                Spacer()
                Button("club.community.next") { page += 1 }.disabled((model.snapshot?.comments.count ?? 0) < 50)
            }
            TextField("club.community.commentContent", text: $content, axis: .vertical).accessibilityIdentifier("club.community.commentContent")
            Button("club.community.review") { Task { await model.prepare(.comment(content), clubID: clubID, post: post) } }
                .disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !identity.isSignedIn || model.busy || model.pendingRecord != nil || model.context.coordinator?.permitsInjectedWrites != true)
            Button("club.community.refresh") { Task { await model.load(operation) } }
        }
        .navigationTitle(Text("club.community.comments"))
        .task(id: identity) {
            model.invalidate(); content = ""; evidence = nil
            await model.load(operation)
            _ = model.recoverPendingState(clubID: clubID, post: post)
            if let fresh = try? await model.context.evidence(clubID, post, nil), fresh.identity == identity { evidence = fresh }
        }
        .task(id: page) { await model.load(operation) }
        .onDisappear { model.invalidate(); content = ""; evidence = nil }
        .sheet(item: $model.review, onDismiss: { model.cancelReview() }) { review in ClubCommunityReviewView(review: review, model: model, refresh: operation) }
    }
}

@MainActor
struct ClubCommunityHistoryView: View {
    let identity: ClubReadIdentity, postID: Int
    @StateObject private var model: ClubCommunityViewModel
    init(context: ClubCommunityContext, identity: ClubReadIdentity, postID: Int) {
        self.identity = identity; self.postID = postID; _model = StateObject(wrappedValue: ClubCommunityViewModel(context: context))
    }
    var body: some View {
        List {
            if model.loading { ProgressView() }
            if let notice = model.notice { Text(LocalizedStringKey(notice)) }
            if model.snapshot?.history.isEmpty == true { Text("club.community.noHistory") }
            ForEach(model.snapshot?.history ?? []) { revision in
                VStack(alignment: .leading) {
                    LabeledContent("club.community.version", value: String(revision.snapshotVersion))
                    Text(verbatim: revision.content)
                    Text(verbatim: revision.createTime).foregroundStyle(.secondary)
                    ForEach(Array(revision.images.enumerated()), id: \.offset) { index, value in
                        AsyncImage(url: URL(string: value)) { image in image.resizable().scaledToFit() } placeholder: { Image(systemName: "photo") }
                            .accessibilityLabel(Text("club.community.image") + Text(" \(index + 1)"))
                    }
                }
            }
            Button("club.community.refresh") { Task { await model.load(.history(postID: postID)) } }
        }.navigationTitle(Text("club.community.history"))
            .task(id: identity) { model.invalidate(); await model.load(.history(postID: postID)) }
            .onDisappear { model.invalidate() }
    }
}
