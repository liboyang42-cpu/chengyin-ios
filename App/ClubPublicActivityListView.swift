import SwiftUI

/// Separate public-topic list. It does not reuse governance authority, sessions,
/// reporting, group codes or management destinations from the calendar.
@MainActor struct ClubPublicActivityListView: View {
    let clubID: Int
    @ObservedObject var session: AppSession
    var onSignIn: (() -> Void)? = nil
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = ClubPublicActivityListModel()
    @State private var visible = false
    @State private var destination: ClubPublicTopicDestination?
    @State private var opening: UUID?
    @State private var selectedUnavailable = false
    /// Dedicated injected source; absence never borrows membership or governance approval.
    var source: ClubPublicTopicsReader? = nil
    private var scope: ClubPublicTopicsScope? { source?.scope(clubID: clubID) }
    private struct ReadKey: Hashable {
        let clubID: Int
        let sourceID: ObjectIdentifier?
        let scope: ClubPublicTopicsScope?
        let visible: Bool
        let foreground: Bool
    }
    private var readKey: ReadKey {
        .init(clubID: clubID, sourceID: source.map { ObjectIdentifier($0) }, scope: scope,
              visible: visible, foreground: scenePhase == .active)
    }
    private var accepted: ClubPublicTopicsSnapshot? {
        guard let source, let snapshot = model.snapshot, snapshot.scope == scope,
              source.isCurrent(snapshot), snapshot.scope.approval.clubID == clubID else { return nil }
        return snapshot
    }
    var body: some View {
        List {
            Section {
                Text("publicTopics.scope", tableName: "ClubPublicTopics").font(.footnote).foregroundStyle(.secondary)
                if !session.clubIdentity.isSignedIn {
                    Text("publicTopics.guestHandoff", tableName: "ClubPublicTopics").font(.footnote).foregroundStyle(.secondary)
                }
            }
            if selectedUnavailable {
                Text("publicTopics.removed", tableName: "ClubPublicTopics")
                    .accessibilityIdentifier("club.publicTopics.selectionRevoked")
            }
            if scope == nil {
                Section {
                    Text("publicTopics.unavailable", tableName: "ClubPublicTopics")
                        .accessibilityIdentifier("club.publicTopics.unavailable")
                }
            } else if model.loading {
                ProgressView("club.loading").accessibilityIdentifier("club.publicTopics.loading")
            } else if let snapshot = accepted {
                let renderedSnapshotID = model.snapshotID
                ClubActivityListContent(rows: snapshot.rows, canOpen: visible && scenePhase == .active && opening == nil, open: { row in
                    select(row, from: snapshot, snapshotID: renderedSnapshotID)
                })
            } else if model.issueScope == scope, let issue = model.issue {
                Section {
                    Text(LocalizedStringKey(issue.titleKey)).accessibilityIdentifier("club.publicTopics.error")
                    if let message = issue.message { Text(verbatim: message) }
                    else { Text(LocalizedStringKey(issue.hintKey)) }
                    if issue.needsSignIn, let onSignIn { Button("club.signIn", action: onSignIn) }
                    Button("action.retry") { Task { await refresh() } }
                        .accessibilityIdentifier("club.publicTopics.retry")
                }
            }
        }
        .navigationTitle(Text("publicTopics.title", tableName: "ClubPublicTopics"))
        .refreshable { await refresh() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("club.refresh", systemImage: "arrow.clockwise") { Task { await refresh() } }
                    .disabled(model.loading || scope == nil || !visible || scenePhase != .active)
                    .accessibilityIdentifier("club.publicTopics.refresh")
            }
        }
        .navigationDestination(item: $destination) { target in
            if current(target) {
                VStack(spacing: 0) {
                    // The existing ordinary detail owns its own auth/content gates.
                    // A list response is not a content-read or purchase entitlement.
                    SessionTopicDetailView(id: target.topicID, session: session)
                    if !session.clubIdentity.isSignedIn, let onSignIn {
                        Button("club.signIn", action: onSignIn).padding()
                            .accessibilityIdentifier("club.publicTopics.detail.signIn")
                    }
                }.id(target.id)
            } else {
                Color.clear.onAppear { if destination?.id == target.id { destination = nil } }
            }
        }
        .task(id: readKey) {
            guard visible, scenePhase == .active else { return }
            await refresh()
        }
        .onAppear { visible = true }
        .onDisappear {
            visible = false; opening = nil
            // Pushing an ordinary detail must not remove its source route. Back
            // triggers a new read; outstanding callbacks are still cancelled now.
            model.suspend(keepingSnapshot: destination != nil)
        }
        .onChange(of: scope) { _, _ in destination = nil; opening = nil; selectedUnavailable = false; model.retire() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { destination = nil; opening = nil; selectedUnavailable = false; model.retire() }
        }
    }
    private func refresh() async {
        guard visible, scenePhase == .active, let source, let scope else { return }
        destination = nil; opening = nil; selectedUnavailable = false
        _ = await model.load(source: source, clubID: clubID, scope: scope)
    }
    private func select(_ row: ClubActivityRow, from snapshot: ClubPublicTopicsSnapshot, snapshotID: UUID) {
        guard visible, scenePhase == .active, destination == nil, opening == nil, !model.loading,
              snapshotID == model.snapshotID, accepted == snapshot, snapshot.rows.contains(row),
              let source, scope == snapshot.scope else { return }
        let ticket = UUID(); opening = ticket; selectedUnavailable = false
        Task {
            defer { if opening == ticket { opening = nil } }
            // A fresh original list validates that the real ID is still visible.
            // Never reopen a removed/hidden topic from an old card after revocation.
            guard let fresh = await model.load(source: source, clubID: clubID, scope: snapshot.scope),
                  opening == ticket, visible, scenePhase == .active, destination == nil, accepted == fresh else { return }
            guard fresh.rows.contains(where: { $0.id == row.id }) else { selectedUnavailable = true; return }
            destination = .init(topicID: row.id, scope: fresh.scope, snapshotID: model.snapshotID)
        }
    }
    private func current(_ target: ClubPublicTopicDestination) -> Bool {
        guard scenePhase == .active, target.snapshotID == model.snapshotID,
              let snapshot = accepted, snapshot.scope == target.scope else { return false }
        return snapshot.rows.contains { $0.id == target.topicID }
    }
}

private struct ClubPublicTopicDestination: Hashable, Identifiable {
    let topicID: Int
    let scope: ClubPublicTopicsScope
    let snapshotID: UUID
    var id: String { "\(snapshotID.uuidString):\(topicID)" }
}

@MainActor private final class ClubPublicActivityListModel: ObservableObject {
    @Published private(set) var snapshot: ClubPublicTopicsSnapshot?
    @Published private(set) var snapshotID = UUID()
    @Published private(set) var issue: ClubLoadIssue?
    @Published private(set) var issueScope: ClubPublicTopicsScope?
    @Published private(set) var loading = false
    private var generation: UInt64 = 0
    private var active = false
    private var task: Task<ClubPublicTopicsSnapshot, Error>?
    func suspend(keepingSnapshot: Bool) {
        active = false; generation &+= 1; task?.cancel(); task = nil; loading = false
        if !keepingSnapshot { snapshot = nil; snapshotID = UUID(); issue = nil; issueScope = nil }
    }
    func retire() { suspend(keepingSnapshot: false) }
    func load(source: ClubPublicTopicsReader, clubID: Int, scope: ClubPublicTopicsScope) async -> ClubPublicTopicsSnapshot? {
        guard source.scope(clubID: clubID) == scope, !Task.isCancelled else { return nil }
        task?.cancel(); generation &+= 1
        let revision = generation
        active = true; snapshot = nil; snapshotID = UUID(); issue = nil; issueScope = nil; loading = true
        func isCurrent() -> Bool {
            active && generation == revision && source.scope(clubID: clubID) == scope
        }
        let work = Task { try await source.read(clubID: clubID, isCurrent: isCurrent) }
        task = work
        defer { if generation == revision { loading = false; task = nil } }
        do {
            let result = try await withTaskCancellationHandler(operation: { try await work.value }, onCancel: { work.cancel() })
            guard !Task.isCancelled, isCurrent(), source.isCurrent(result), result.scope == scope else { return nil }
            snapshot = result
            return result
        } catch is CancellationError { return nil }
        catch {
            guard !Task.isCancelled, isCurrent() else { return nil }
            snapshot = nil; issue = ClubLoadIssue(error); issueScope = scope
            return nil
        }
    }
}
