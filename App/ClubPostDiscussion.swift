import SwiftUI

/// A read-only owner: closing inline discussion never cancels a shared write review.
@MainActor final class ClubPostDiscussionReader: ObservableObject {
    enum Phase: Equatable { case idle, loading, ready, failed }
    let target: ClubPostDiscussionSelection
    private let context: ClubCommunityContext
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var comments: [ClubCommunityComment] = []
    @Published private(set) var page = 1
    @Published private(set) var hasNext = false
    private var generation: UInt64 = 0
    init(target: ClubPostDiscussionSelection, context: ClubCommunityContext) { self.target = target; self.context = context }
    func invalidate() {
        generation &+= 1; comments = []; phase = .idle; hasNext = false
    }
    func load(page: Int, isCurrent: @escaping () -> Bool) async {
        guard page > 0, isCurrent(), (try? context.currentSession().identity) == target.context.identity else { invalidate(); return }
        generation &+= 1; let ticket = generation
        self.page = page; phase = .loading; comments = []; hasNext = false
        do {
            let session = try context.currentSession()
            let result = try await context.service.read(.comments(postID: target.post.id, page: page), session: session) {
                guard !Task.isCancelled, ticket == self.generation, isCurrent(),
                      try self.context.currentSession() == session else { throw CancellationError() }
            }
            guard !Task.isCancelled, ticket == generation, isCurrent(), try context.currentSession() == session else { return }
            guard Set(result.comments.map(\.id)).count == result.comments.count else { throw ClubCommunityFailure.invalid }
            comments = result.comments; hasNext = comments.count >= 50 && page < Int.max; phase = .ready
        } catch {
            guard ticket == generation else { return }
            guard !Task.isCancelled, isCurrent(), (try? context.currentSession().identity) == target.context.identity else { invalidate(); return }
            comments = []; hasNext = false; phase = .failed
        }
    }
}

/// Only the body/meta region is interactive here; author, media, references and
/// moderation remain sibling controls so opening discussion cannot steal their taps.
@MainActor struct ClubPostDiscussionBody: View {
    let post: ClubCommunityPost
    let expanded: Bool
    let open: (() -> Void)?
    var body: some View {
        Group {
            if let open {
                content.contentShape(Rectangle())
                    .onTapGesture(perform: open)
                    .accessibilityElement(children: .combine).accessibilityAddTraits(.isButton)
                    .accessibilityHint(expanded ? "club.discussion.collapse" : "club.discussion.expand")
                    .accessibilityAction { open() }
                    .accessibilityIdentifier("club.discussion.body.\(post.id)")
            } else { content }
        }
    }
    private var content: some View {
        VStack(alignment: .leading, spacing: 6) {
            if post.pinned { Label("club.community.pinned", systemImage: "pin") }
            if !post.content.isEmpty { Text(verbatim: post.content).textSelection(.enabled) }
            else { Text("club.discussion.openPost").font(.subheadline) }
            if !post.createTime.isEmpty { Text(verbatim: post.createTime).font(.caption).foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }
}

@MainActor struct ClubPostDiscussionPanel: View {
    let target: ClubPostDiscussionSelection
    @ObservedObject var source: ClubCommunityViewModel
    let close: () -> Void
    @Environment(\.clubCustomerTopics) private var topics
    @Environment(\.clubPostPlayHost) private var host
    @StateObject private var reader: ClubPostDiscussionReader
    @State private var fullComments = false
    @State private var active = true
    init(target: ClubPostDiscussionSelection, source: ClubCommunityViewModel, close: @escaping () -> Void) {
        self.target = target; self.source = source; self.close = close
        _reader = StateObject(wrappedValue: ClubPostDiscussionReader(target: target, context: source.context))
    }
    private var context: ClubPostDiscussionContext {
        .init(clubID: target.context.clubID, identity: target.context.identity, readScope: source.imageReadScope, viewerRevision: topics.viewerRevision)
    }
    private var current: Bool {
        active && (host?.isCurrent() ?? true) && (try? source.context.currentSession().identity) == target.context.identity &&
        target.isCurrent(acceptedPosts: source.snapshot?.posts, context: context)
    }
    var body: some View {
        Group {
            if current {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("club.community.comments").font(.headline)
                        Spacer()
                        Button("club.discussion.collapse") { trace("collapse"); active = false; reader.invalidate(); close() }
                            .accessibilityIdentifier("club.discussion.close.\(target.post.id)")
                    }
                    switch reader.phase {
                    case .idle, .loading:
                        ProgressView("club.discussion.loading")
                    case .failed:
                        Text("club.community.loadError")
                        Button("action.retry") { load(reader.page) }.accessibilityIdentifier("club.discussion.retry")
                    case .ready:
                        if reader.comments.isEmpty { Text("club.community.noComments") }
                        ForEach(reader.comments) { comment in
                            VStack(alignment: .leading, spacing: 4) {
                                if comment.nickname.isEmpty { Text("club.community.user").font(.subheadline.bold()) }
                                else { Text(verbatim: comment.nickname).font(.subheadline.bold()) }
                                Text(verbatim: comment.content).textSelection(.enabled)
                            }.accessibilityElement(children: .combine)
                                .accessibilityIdentifier("club.discussion.comment.\(comment.id)")
                        }
                    }
                    HStack {
                        Button("club.community.previous") { load(max(1, reader.page - 1)) }
                            .disabled(reader.page == 1 || reader.phase == .loading)
                        Spacer()
                        Text(reader.page, format: .number).accessibilityLabel(Text("club.discussion.page") + Text(" \(reader.page)"))
                        Spacer()
                        Button("club.community.next") { if reader.page < Int.max { load(reader.page + 1) } }
                            .disabled(!reader.hasNext || reader.phase == .loading)
                    }
                    Button("club.community.refresh") { load(reader.page) }.disabled(reader.phase == .loading)
                    Button("club.discussion.full") { trace("full"); if current { fullComments = true; trace("full-requested") } }
                        .accessibilityIdentifier("club.discussion.full.\(target.post.id)")
                }.padding(.vertical, 8)
                    .buttonStyle(.borderless)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("club.discussion.panel.\(target.post.id)")
            }
        }
        .onAppear { trace("panel-appear") }
        .task(id: target.id) { active = true; await reader.load(page: 1, isCurrent: { current }) }
        .onChange(of: current) { _, valid in trace(valid ? "current-true" : "current-false"); if !valid { fullComments = false; reader.invalidate() } }
        .onDisappear { trace("panel-disappear"); active = false; reader.invalidate() }
        .sheet(isPresented: $fullComments, onDismiss: { trace("sheet-dismiss"); load(reader.page) }) {
            ClubPostFullComments(target: target, source: source)
                .presentationDetents([.large]).presentationCompactAdaptation(.sheet)
                .onAppear { trace("sheet-appear") }
                .onDisappear { trace("sheet-disappear") }
        }
    }
    private func trace(_ event: String) {
        ClubPostDiscussionFixtureTrace.record(event, postID: target.post.id,
            active: active, current: current, fullComments: fullComments)
    }
    private func load(_ page: Int) {
        guard current else { return }
        Task { await reader.load(page: page, isCurrent: { current }) }
    }
}

@MainActor private struct ClubPostFullComments: View {
    let target: ClubPostDiscussionSelection
    @ObservedObject var source: ClubCommunityViewModel
    @Environment(\.clubCustomerTopics) private var topics
    @Environment(\.clubPostPlayHost) private var host
    @Environment(\.dismiss) private var dismiss
    private var current: Bool {
        (host?.isCurrent() ?? true) && (try? source.context.currentSession().identity) == target.context.identity &&
        target.isCurrent(acceptedPosts: source.snapshot?.posts, context: .init(clubID: target.context.clubID,
            identity: target.context.identity, readScope: source.imageReadScope, viewerRevision: topics.viewerRevision))
    }
    var body: some View {
        NavigationStack {
            if current {
                ClubCommunityCommentsView(context: source.context, identity: target.context.identity,
                                          clubID: target.context.clubID, post: target.post)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("action.close") { dismiss() } } }
            } else { Color.clear.onAppear { dismiss() } }
        }
        .onChange(of: current) { _, valid in if !valid { dismiss() } }
    }
}


/// Synthetic presentation evidence only; never records user content or production events.
#if DEBUG
@MainActor enum ClubPostDiscussionFixtureTrace {
    static let events = ClubPostDiscussionFixtureEvents()
    static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("--club-community-fixture") }
    static func record(_ event: String, postID: Int, active: Bool, current: Bool, fullComments: Bool) {
        guard enabled else { return }
        events.record("\(event):post=\(postID),active=\(active),current=\(current),full=\(fullComments)")
    }
}

@MainActor final class ClubPostDiscussionFixtureEvents: ObservableObject {
    @Published private(set) var value = "events=0"
    private var count = 0
    private var recent: [String] = []
    func record(_ event: String) {
        count += 1; recent.append("\(count):" + event)
        if recent.count > 16 { recent.removeFirst(recent.count - 16) }
        value = "events=\(count);" + recent.joined(separator: ";")
    }
}

@MainActor private struct ClubPostDiscussionFixtureTraceLabel: View {
    @ObservedObject private var events = ClubPostDiscussionFixtureTrace.events
    var body: some View {
        Text("Fixture discussion events").font(.system(size: 1)).frame(width: 1, height: 1).clipped()
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("club.discussion.fixtureTrace")
            .accessibilityLabel("Fixture discussion events").accessibilityValue(events.value)
            .allowsHitTesting(false)
    }
}

@MainActor struct ClubPostDiscussionFixtureTraceView: View {
    var body: some View {
        if ClubPostDiscussionFixtureTrace.enabled { ClubPostDiscussionFixtureTraceLabel() }
    }
}
#else
@MainActor enum ClubPostDiscussionFixtureTrace {
    static func record(_ event: String, postID: Int, active: Bool, current: Bool, fullComments: Bool) {}
}
@MainActor struct ClubPostDiscussionFixtureTraceView: View {
    var body: some View { EmptyView() }
}
#endif
