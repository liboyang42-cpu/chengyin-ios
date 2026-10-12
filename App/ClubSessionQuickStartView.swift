import SwiftUI

@MainActor final class ClubSessionQuickStartModel: ObservableObject {
    struct Permit: Equatable { let context: ClubSessionQuickStartContext; let visibility: UUID }
    enum Phase: Equatable { case idle, loading, ready, failed, denied, topicUnavailable }
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var topics: ClubSessionQuickStartTopics?
    @Published private(set) var target: ClubSessionQuickStartTarget?
    private var bound: ClubSessionQuickStartContext?
    private var loaded: ClubSessionQuickStartContext?
    private var visibility: UUID?
    private var generation = UUID()
    private var snapshotID = UUID()
    func bind(_ context: ClubSessionQuickStartContext) {
        guard bound != context else { return }; bound = context; visibility = nil; generation = UUID()
    }
    func activate(_ context: ClubSessionQuickStartContext) -> Permit? {
        guard bound == context, context.canRead, !Task.isCancelled else { return nil }
        if visibility == nil { visibility = UUID(); generation = UUID(); clear(); phase = .idle }
        return permit(in: context)
    }
    func permit(in context: ClubSessionQuickStartContext) -> Permit? {
        guard bound == context, context.canRead, let visibility else { return nil }; return .init(context: context, visibility: visibility)
    }
    private func accepts(_ p: Permit) -> Bool { bound == p.context && visibility == p.visibility && p.context.canRead }
    private func clear() { loaded = nil; topics = nil; target = nil; snapshotID = UUID() }
    func leave(_ context: ClubSessionQuickStartContext) {
        guard bound == context else { return }; visibility = nil; generation = UUID(); clear(); phase = .idle
    }
    func accepted(_ context: ClubSessionQuickStartContext, reader: any ClubReading, access: any ClubGovernanceAccess, viewerRevision: UInt64) -> ClubSessionQuickStartTopics? {
        guard permit(in: context) != nil, loaded == context, [.ready, .topicUnavailable].contains(phase),
              context.matches(reader: reader, access: access, viewerRevision: viewerRevision) else { return nil }; return topics
    }
    func isCurrent(_ value: ClubSessionQuickStartTarget, context: ClubSessionQuickStartContext, reader: any ClubReading, access: any ClubGovernanceAccess, viewerRevision: UInt64) -> Bool {
        target == value && value.isCurrent(topics: accepted(context, reader: reader, access: access, viewerRevision: viewerRevision), context: context, snapshotID: snapshotID)
    }
    /// Selecting re-reads both ownership and manageable topics. Nothing here prepares or sends a command.
    @discardableResult func read(_ p: Permit, selecting topicID: Int? = nil, reader: any ClubReading, access: any ClubGovernanceAccess, viewerRevision: @escaping () -> UInt64) async -> ClubSessionQuickStartTarget? {
        guard accepts(p), p.context.matches(reader: reader, access: access, viewerRevision: viewerRevision()), !Task.isCancelled else { return nil }
        generation = UUID(); let request = generation
        clear(); phase = .loading
        let current = { [self] in accepts(p) && generation == request && !Task.isCancelled && p.context.matches(reader: reader, access: access, viewerRevision: viewerRevision()) }
        defer { if accepts(p), generation == request, phase == .loading { phase = .idle } }
        do {
            let club = try await reader.clubDetail(id: p.context.clubID, isCurrent: current)
            guard current() else { return nil }
            guard club.id == p.context.clubID, club.isOwner else { phase = .denied; return nil }
            let snapshot = try await access.read(.eventTopics, scope: .init(clubID: p.context.clubID), options: [:]) {
                guard current() else { throw CancellationError() }
            }
            guard current() else { return nil }
            let rows = try ClubSessionQuickStartTopics(context: p.context, snapshot: snapshot)
            guard current() else { return nil }
            loaded = p.context; topics = rows
            if let topicID {
                guard let selected = rows.target(topicID: topicID, context: p.context, snapshotID: snapshotID) else { phase = .topicUnavailable; return nil }
                target = selected
            }
            phase = .ready; return target
        } catch {
            guard current() else { return nil }; clear(); phase = .failed; return nil
        }
    }
}

@MainActor struct ClubSessionQuickStartEntry<Reader: ClubReading & ObservableObject>: View {
    let club: ClubRecord
    @ObservedObject var reader: Reader
    let governance: ClubGovernanceContext
    var body: some View {
        let scope = ClubSessionQuickStartContext(club: club, reader: reader, access: governance.access, viewerRevision: governance.viewerRevision)
        if scope.canRead {
            NavigationLink {
                ClubSessionQuickStartView(club: club, reader: reader, governance: governance)
            } label: { Label("club.sessionStart.title", systemImage: "calendar.badge.plus") }
                .accessibilityIdentifier("club.sessionStart.entry")
        }
    }
}

@MainActor struct ClubSessionQuickStartView<Reader: ClubReading & ObservableObject>: View {
    let club: ClubRecord
    @ObservedObject var reader: Reader
    let governance: ClubGovernanceContext
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = ClubSessionQuickStartModel()
    @State private var presented: ClubSessionQuickStartTarget?
    @State private var pendingSelection: UUID?
    private var context: ClubSessionQuickStartContext { .init(club: club, reader: reader, access: governance.access, viewerRevision: governance.viewerRevision) }
    private func accepted(_ scope: ClubSessionQuickStartContext) -> ClubSessionQuickStartTopics? {
        model.accepted(scope, reader: reader, access: governance.access, viewerRevision: governance.viewerRevision)
    }
    var body: some View {
        let scope = context
        let _ = model.bind(scope)
        List {
            Section {
                Text(verbatim: club.name).font(.headline)
                LabeledContent("club.ops.clubID", value: String(scope.clubID))
                Text("club.sessionStart.hint").font(.footnote)
            }
            if !scope.canRead || model.phase == .denied { Text("club.sessionStart.ownerRequired").accessibilityIdentifier("club.sessionStart.denied") }
            else {
                if model.phase == .loading { ProgressView("club.loading").accessibilityIdentifier("club.sessionStart.loading") }
                if model.phase == .failed { Text("club.sessionStart.failed").accessibilityIdentifier("club.sessionStart.failed") }
                if model.phase == .topicUnavailable { Text("club.sessionStart.topicUnavailable") }
                if let topics = accepted(scope) {
                    Section("club.sessionStart.chooseTopic") {
                        if topics.rows.isEmpty { Text("club.sessionStart.empty").accessibilityIdentifier("club.sessionStart.empty") }
                        ForEach(topics.rows) { topic in
                            Button { choose(topic.id, scope: scope) } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    if let name = topic.name { Text(verbatim: name).font(.headline) }
                                    else { Text("club.sessionStart.unnamedTopic").font(.headline) }
                                    LabeledContent("club.gov.field.topicId", value: String(topic.id))
                                    Text(LocalizedStringKey(topic.originKey(currentClubID: scope.clubID)))
                                    if let date = topic.startDate { LabeledContent("club.sessionStart.startDate") { Text(verbatim: date) } }
                                    if let date = topic.endDate { LabeledContent("club.sessionStart.endDate") { Text(verbatim: date) } }
                                }
                            }.disabled(pendingSelection != nil || presented != nil)
                                .accessibilityIdentifier("club.sessionStart.topic.\(topic.id)")
                        }
                    }
                }
                Button(LocalizedStringKey(model.phase == .failed ? "action.retry" : "club.refresh")) { reload(scope) }
                    .disabled(model.phase == .loading || pendingSelection != nil || presented != nil || model.permit(in: scope) == nil)
                    .accessibilityIdentifier("club.sessionStart.reload")
            }
        }
        .navigationTitle("club.sessionStart.title")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("action.cancel") { pendingSelection = nil; model.leave(scope); dismiss() }.accessibilityIdentifier("club.sessionStart.cancel") } }
        .task(id: scope) {
            presented = nil; pendingSelection = nil
            guard let permit = model.activate(scope) else { return }
            await model.read(permit, reader: reader, access: governance.access, viewerRevision: { governance.viewerRevision })
        }
        .onChange(of: scope) { _, _ in presented = nil; pendingSelection = nil }
        .onDisappear { presented = nil; pendingSelection = nil; model.leave(scope) }
        .sheet(item: $presented, onDismiss: { reload(scope) }) { selected in
            NavigationStack {
                Group {
                    if current(selected) {
                        // The existing form owns dirty-discard, schedule/lead choice, review and authorized dispatch.
                        ClubGovernanceCommandForm(route: .init(operation: .createSeries, scope: selected.scope, seed: selected.seed),
                            identity: selected.context.identity, access: governance.access, coordinator: governance.coordinator)
                            .id(selected.id)
                    } else { Color.clear }
                }
                .onChange(of: current(selected), initial: true) { _, valid in if !valid { presented = nil } }
            }
        }
    }
    private func current(_ value: ClubSessionQuickStartTarget) -> Bool {
        model.isCurrent(value, context: context, reader: reader, access: governance.access, viewerRevision: governance.viewerRevision)
    }
    private func reload(_ scope: ClubSessionQuickStartContext) {
        guard context == scope, scope.matches(reader: reader, access: governance.access, viewerRevision: governance.viewerRevision), let permit = model.permit(in: scope) else { return }
        Task { await model.read(permit, reader: reader, access: governance.access, viewerRevision: { governance.viewerRevision }) }
    }
    private func choose(_ topicID: Int, scope: ClubSessionQuickStartContext) {
        guard presented == nil, pendingSelection == nil, context == scope, accepted(scope)?.rows.contains(where: { $0.id == topicID }) == true,
              let permit = model.permit(in: scope) else { return }
        let ticket = UUID(); pendingSelection = ticket
        Task {
            let selected = await model.read(permit, selecting: topicID, reader: reader, access: governance.access, viewerRevision: { governance.viewerRevision })
            guard pendingSelection == ticket else { return }; pendingSelection = nil
            guard let selected, presented == nil, current(selected) else { return }; presented = selected
        }
    }
}
