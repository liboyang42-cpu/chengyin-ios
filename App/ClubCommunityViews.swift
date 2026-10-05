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
    var onAuthor: ((Int) -> Void)? = nil
    var onTopic: ((Int) -> Void)? = nil
}

@MainActor
final class ClubCommunityViewModel: ObservableObject {
    let context: ClubCommunityContext
    @Published private(set) var snapshot: ClubCommunitySnapshot?
    @Published private(set) var loading = false
    @Published var notice: String?
    @Published var review: ClubCommunityReview?
    @Published private(set) var busy = false
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
        suspend(); snapshot = nil; notice = nil
    }
    func load(_ operation: ClubCommunityRead) async {
        generation &+= 1; let ticket = generation
        snapshot = nil; loading = true; notice = nil
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
        busy = true; defer { busy = false }
        do {
            let session = try context.currentSession(), ticket = generation
            let evidence = try await context.evidence(clubID, post, comment)
            guard ticket == generation, try context.currentSession() == session else { throw ClubCommunityFailure.stale }
            let candidate = try await coordinator.prepare(operation, evidence: evidence)
            guard ticket == generation, try context.currentSession() == session else { coordinator.cancel(); throw ClubCommunityFailure.stale }
            review = candidate
        } catch { notice = "club.community.actionUnavailable" }
    }
    func confirm(refresh: ClubCommunityRead) async {
        guard !busy, let review, let coordinator = context.coordinator else { return }
        busy = true; self.review = nil
        do {
            try await coordinator.confirm(review)
            let queued = coordinator.outcome == .moderationQueued
            await load(refresh)
            notice = queued ? "club.community.queued" : "club.community.refreshRequired"
        } catch { notice = coordinator.outcome == .unknownLocked ? "club.community.unknown" : "club.community.actionUnavailable" }
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
    enum Screen: Hashable { case comments, history }
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
    init(context: ClubCommunityContext, identity: ClubReadIdentity, clubID: Int? = nil) {
        self.identity = identity; self.clubID = clubID; _model = StateObject(wrappedValue: ClubCommunityViewModel(context: context))
    }
    private var operation: ClubCommunityRead { clubID.map { .posts(clubID: $0, page: page) } ?? .feed(page: page) }
    var body: some View {
        List {
            if model.loading { ProgressView().accessibilityLabel(Text("club.community.loading")) }
            if let notice = model.notice { Text(LocalizedStringKey(notice)).accessibilityIdentifier("club.community.notice") }
            if let snapshot = model.snapshot {
                if snapshot.clubCount == 0 { Text("club.community.joinFirst") }
                else if snapshot.posts.isEmpty { Text("club.community.empty") }
                ForEach(snapshot.posts) { post in
                    ClubCommunityPostTile(post: post, clubID: post.clubID ?? clubID, identity: identity, model: model,
                        openComments: { destination = .init(post: post, clubID: post.clubID ?? clubID, screen: .comments) },
                        openHistory: { destination = .init(post: post, clubID: post.clubID ?? clubID, screen: .history) })
                }
                HStack {
                    Button("club.community.previous") { page = max(1, page - 1) }.disabled(page == 1)
                    Spacer()
                    Button("club.community.next") { page += 1 }.disabled(snapshot.posts.count < 20)
                }
            }
            Button("club.community.refresh") { Task { await model.load(operation) } }.disabled(model.loading || model.busy)
            if clubID != nil && identity.isSignedIn {
                Button("club.community.create") { composing = true }.disabled(model.busy || model.context.coordinator?.permitsInjectedWrites != true)
                    .accessibilityIdentifier("club.community.compose")
            }
            if model.context.coordinator?.permitsInjectedWrites != true { Text("club.community.offline").foregroundStyle(.secondary) }
        }
        .navigationTitle(Text("club.community.posts"))
        .navigationDestination(item: $destination) { target in
            switch target.screen {
            case .comments:
                if let clubID = target.clubID { ClubCommunityCommentsView(context: model.context, identity: identity, clubID: clubID, post: target.post) }
            case .history:
                ClubCommunityHistoryView(context: model.context, identity: identity, postID: target.post.id)
            }
        }
        .onChange(of: identity) { _, _ in destination = nil }
        .task(id: identity) { model.invalidate(); page = 1; await model.load(operation) }
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
}

@MainActor
struct ClubCommunityPostTile: View {
    let post: ClubCommunityPost
    let clubID: Int?
    let identity: ClubReadIdentity
    @ObservedObject var model: ClubCommunityViewModel
    let openComments: () -> Void
    let openHistory: () -> Void
    @State private var editing = false
    @State private var evidence: ClubCommunityEvidence?
    private func allows(_ operation: ClubCommunityOperation) -> Bool {
        guard let evidence, evidence.identity == identity, evidence.post == post, Date().timeIntervalSince(evidence.observedAt) < 60 else { return false }
        return evidence.allows(operation)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let author = post.authorMemberID, author > 0, let open = model.context.onAuthor {
                Button { open(author) } label: { authorLabel }
            } else { authorLabel }
            if post.pinned { Label("club.community.pinned", systemImage: "pin") }
            if !post.content.isEmpty { Text(verbatim: post.content).textSelection(.enabled) }
            ForEach(Array(post.images.enumerated()), id: \.offset) { index, image in
                AsyncImage(url: URL(string: image)) { phase in
                    if let image = phase.image { image.resizable().scaledToFit() }
                    else { Image(systemName: "photo").frame(minHeight: 44) }
                }.accessibilityLabel(Text("club.community.image") + Text(" \(index + 1)"))
            }
            if !post.sportName.isEmpty, (post.refType == 1 || !post.sportCover.isEmpty) {
                if let topicID = post.navigableTopicID, let open = model.context.onTopic {
                    Button(post.sportName) { open(topicID) }
                } else { Text(verbatim: post.sportName) }
            }
            if post.likeCount > 0 || post.commentCount > 0 {
                HStack { Label("\(post.likeCount)", systemImage: "heart"); Label("\(post.commentCount)", systemImage: "bubble") }.accessibilityElement(children: .combine)
            }
            if let clubID {
                HStack {
                    Button { Task { await model.prepare(.toggleLike, clubID: clubID, post: post) } } label: { Label("club.community.like", systemImage: post.liked ? "heart.fill" : "heart") }
                        .disabled(!identity.isSignedIn || model.busy || model.context.coordinator?.permitsInjectedWrites != true)
                    Button(action: openComments) { Label("club.community.comments", systemImage: "bubble") }
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
            Button(action: openHistory) { Text("club.community.history") }
                .accessibilityIdentifier("club.community.history.\(post.id)")
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
    private var authorLabel: some View {
        Group { if post.nickname.isEmpty { Text("club.community.user") } else { Text(verbatim: post.nickname) } }
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
    var body: some View {
        NavigationStack {
            Form {
                TextEditor(text: $content).frame(minHeight: 150).accessibilityLabel(Text("club.community.content"))
                    .accessibilityIdentifier("club.community.content")
                Text("\(content.count)/300").foregroundStyle(.secondary)
                ForEach(Array(images.enumerated()), id: \.offset) { index, image in
                    HStack {
                        Text(verbatim: image).lineLimit(1)
                        Spacer()
                        Button { images.remove(at: index) } label: { Label("club.community.removeImage", systemImage: "xmark.circle") }.frame(minWidth: 44, minHeight: 44)
                    }
                }
                if model.context.images.enabled {
                    Button("club.community.addSyntheticImage") {
                        uploading = true
                        Task {
                            do { images += try await model.context.images.uploadSynthetic([Data([1])]) }
                            catch { model.notice = "club.community.actionUnavailable" }
                            uploading = false
                        }
                    }.disabled(images.count >= 9 || uploading)
                } else { Text("club.community.imagesOff") }
                Button("club.community.review") {
                    let operation: ClubCommunityOperation = post == nil ? .create(content: content, images: images) : .update(content: content, images: images, requestID: UUID().uuidString)
                    model.stageDraft(operation, clubID: clubID, post: post)
                    dismiss()
                }.disabled(model.busy || uploading || content.count > 300 || (content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && images.isEmpty))
                    .accessibilityIdentifier("club.community.reviewDraft")
            }
            .navigationTitle(Text(post == nil ? "club.community.create" : "club.community.edit"))
            .toolbar { Button("club.community.cancel") { dismiss() } }
            .onAppear { content = post?.content ?? ""; images = post?.images ?? [] }
        }
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
                .disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !identity.isSignedIn || model.busy || model.context.coordinator?.permitsInjectedWrites != true)
            Button("club.community.refresh") { Task { await model.load(operation) } }
        }
        .navigationTitle(Text("club.community.comments"))
        .task(id: identity) {
            model.invalidate(); content = ""; evidence = nil
            await model.load(operation)
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
