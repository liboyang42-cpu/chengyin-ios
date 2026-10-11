import SwiftUI

/// A local read owner. Old retry/refresh callbacks are fenced before they can clear
/// a newer snapshot; the existing access layer still performs OWNER preflight.
@MainActor final class ClubStatsOverviewReadModel: ObservableObject {
    struct Permit: Equatable {
        let context: ClubGovernanceReadContext
        let visibility: UUID
    }
    @Published private(set) var snapshot: ClubStatsOverview?
    @Published private(set) var failure: ClubGovernanceFailure?
    @Published private(set) var loading = false
    private var loadedContext: ClubGovernanceReadContext?
    private var boundContext: ClubGovernanceReadContext?
    private var visibility: UUID?
    private var generation = UUID()

    /// No published mutation during body evaluation. Old callbacks are retired
    /// immediately, before SwiftUI runs the replacement task.
    func bind(_ context: ClubGovernanceReadContext) {
        guard boundContext != context else { return }
        boundContext = context; visibility = nil; generation = UUID()
    }
    func activate(_ context: ClubGovernanceReadContext) -> Permit? {
        guard !Task.isCancelled, boundContext == context else { return nil }
        if visibility == nil {
            visibility = UUID(); generation = UUID()
            snapshot = nil; loadedContext = nil; failure = nil; loading = false
        }
        return permit(in: context)
    }
    func permit(in context: ClubGovernanceReadContext) -> Permit? {
        guard boundContext == context, let visibility else { return nil }
        return .init(context: context, visibility: visibility)
    }
    func leave(_ context: ClubGovernanceReadContext) {
        guard boundContext == context else { return }
        visibility = nil; generation = UUID(); snapshot = nil; loadedContext = nil; failure = nil; loading = false
    }
    private func accepts(_ permit: Permit) -> Bool {
        boundContext == permit.context && visibility == permit.visibility
    }
    private func live(_ expected: ClubGovernanceReadContext, access: any ClubGovernanceAccess) -> Bool {
        expected.operation == .stats && (expected.scope.clubID ?? 0) > 0 &&
            (expected.identity?.accountID ?? 0) > 0 && access.isConfigured &&
            expected.identity == access.identity && expected.authorizationGeneration == access.authorizationGeneration &&
            expected.accessIdentity == ObjectIdentifier(access)
    }
    func accepted(_ context: ClubGovernanceReadContext, access: any ClubGovernanceAccess) -> ClubStatsOverview? {
        guard permit(in: context) != nil, loadedContext == context, live(context, access: access) else { return nil }
        return snapshot
    }
    func load(_ permit: Permit, access: any ClubGovernanceAccess) async {
        guard accepts(permit), !Task.isCancelled else { return }
        // Check mutable identity before touching current state as well as dispatch.
        guard live(permit.context, access: access) else {
            snapshot = nil; loadedContext = nil; loading = false
            failure = access.identity?.isSignedIn == true ? .notConfigured : .signedOut
            return
        }
        generation = UUID(); let request = generation
        snapshot = nil; loadedContext = nil; failure = nil; loading = true
        defer { if generation == request && accepts(permit) { loading = false } }
        func check() throws {
            guard accepts(permit), generation == request, live(permit.context, access: access), !Task.isCancelled else {
                throw CancellationError()
            }
        }
        do {
            try check()
            let source = try await access.read(.stats, scope: permit.context.scope, options: [:], check: check)
            try check()
            let overview = try ClubStatsOverview(snapshot: source, context: permit.context)
            loadedContext = permit.context; snapshot = overview
        } catch {
            guard accepts(permit), generation == request, live(permit.context, access: access), !Task.isCancelled else { return }
            failure = error as? ClubGovernanceFailure ?? .malformed
        }
    }
}

@MainActor struct ClubStatsOverviewView: View {
    let clubID: Int
    let identity: ClubReadIdentity
    let governance: ClubGovernanceContext
    @StateObject private var model = ClubStatsOverviewReadModel()
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var context: ClubGovernanceReadContext {
        .init(operation: .stats, scope: .init(clubID: clubID), identity: identity,
              viewerRevision: governance.viewerRevision, authorizationGeneration: governance.access.authorizationGeneration,
              accessIdentity: ObjectIdentifier(governance.access))
    }
    var body: some View {
        let expected = context
        let _ = model.bind(expected)
        let permit = model.permit(in: expected)
        List {
            if model.loading || permit == nil {
                ProgressView("club.loading").accessibilityIdentifier("club.statsOverview.loading")
            }
            if permit != nil, let failure = model.failure {
                Text(LocalizedStringKey(failure.localizationKey)).accessibilityIdentifier("club.statsOverview.error")
            }
            if let overview = model.accepted(expected, access: governance.access) {
                summary(overview)
                Section("club.statsOverview.projects") {
                    if overview.projects.isEmpty {
                        Text("club.statsOverview.empty").accessibilityIdentifier("club.statsOverview.empty")
                    }
                    ForEach(overview.projects) { project in
                        VStack(alignment: .leading, spacing: 8) {
                            if let name = project.name { Text(verbatim: name).font(.headline) }
                            else { Text("club.statsOverview.unnamed").font(.headline) }
                            LabeledContent("club.statsOverview.participants") { count(project.participants) }
                            LabeledContent("club.statsOverview.completed") { count(project.completed) }
                            LabeledContent("club.statsOverview.rate") { rate(project.completion) }
                        }.padding(.vertical, 4).accessibilityIdentifier("club.statsOverview.project.\(project.id)")
                    }
                    if overview.hasMoreProjects { Text("club.statsOverview.firstFive").font(.footnote).foregroundStyle(.secondary) }
                }
            }
            Button(LocalizedStringKey(model.failure == nil ? "club.gov.refresh" : "action.retry")) {
                guard let permit else { return }
                Task { await model.load(permit, access: governance.access) }
            }.disabled(model.loading || permit == nil).accessibilityIdentifier("club.statsOverview.reload")
        }
        .navigationTitle("club.statsOverview.title")
        .task(id: expected) {
            guard let permit = model.activate(expected) else { return }
            await model.load(permit, access: governance.access)
        }
        .refreshable {
            guard let permit else { return }
            await model.load(permit, access: governance.access)
        }
        .onDisappear { model.leave(expected) }
    }
    private func summary(_ overview: ClubStatsOverview) -> some View {
        Section {
            let columns = Array(repeating: GridItem(.flexible(), alignment: .leading), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                metric("club.statsOverview.topicCount") { count(overview.topicCount) }
                metric("club.statsOverview.participants") { count(overview.participants) }
                metric("club.statsOverview.completed") { count(overview.completed) }
                metric("club.statsOverview.rate") { rate(overview.completion) }
            }.accessibilityIdentifier("club.statsOverview.summary")
            Text("club.statsOverview.scope").font(.footnote).foregroundStyle(.secondary)
            Text("club.statsOverview.rateScope").font(.footnote).foregroundStyle(.secondary)
        }
    }
    private func metric<Value: View>(_ title: LocalizedStringKey, @ViewBuilder value: () -> Value) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            value().font(.title2.bold())
            Text(title).font(.subheadline)
        }.fixedSize(horizontal: false, vertical: true).accessibilityElement(children: .combine)
    }
    @ViewBuilder private func count(_ value: Int?) -> some View {
        if let value { Text(value, format: .number) }
        else { Text("club.statsOverview.unknown") }
    }
    @ViewBuilder private func rate(_ value: ClubStatsCompletion) -> some View {
        switch value {
        case .percentage(let sourcePercentage):
            // Unit conversion for the standard percent formatter, not a new denominator.
            Text(sourcePercentage / 100, format: .percent.precision(.fractionLength(1)))
        case .noParticipants:
            Text(verbatim: "—").accessibilityLabel("club.statsOverview.noParticipants")
        case .unknown:
            Text("club.statsOverview.unknown")
        }
    }
}
