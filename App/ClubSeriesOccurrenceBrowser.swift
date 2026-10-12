import SwiftUI

@MainActor final class ClubSeriesOccurrenceReadModel: ObservableObject {
    struct Context: Hashable { let read: ClubGovernanceReadContext; let namespace: String }
    struct Permit: Equatable { let context: Context; let visibility: UUID }
    @Published private(set) var options: ClubSeriesOccurrencePresentation?
    @Published private(set) var loading = false
    @Published private(set) var failure: ClubGovernanceFailure?
    private var bound: Context?
    private var loaded: Context?
    private var visibility: UUID?
    private var generation = UUID()
    private(set) var snapshotID = UUID()
    static func context(scope: ClubGovernanceScope, identity: ClubReadIdentity?, access: any ClubGovernanceAccess) -> Context {
        .init(read: .init(operation: .occurrences, scope: scope, identity: identity, viewerRevision: 0,
                          authorizationGeneration: access.authorizationGeneration, accessIdentity: ObjectIdentifier(access)),
              namespace: access.storageNamespace)
    }
    func bind(_ context: Context) {
        guard bound != context else { return }
        bound = context; visibility = nil; generation = UUID()
    }
    func activate(_ context: Context) -> Permit? {
        guard bound == context, !Task.isCancelled else { return nil }
        if visibility == nil {
            visibility = UUID(); generation = UUID(); snapshotID = UUID()
            loaded = nil; options = nil; loading = false; failure = nil
        }
        return permit(in: context)
    }
    func permit(in context: Context) -> Permit? {
        guard bound == context, let visibility else { return nil }
        return .init(context: context, visibility: visibility)
    }
    private func accepts(_ permit: Permit) -> Bool { bound == permit.context && visibility == permit.visibility }
    private func live(_ context: Context, access: any ClubGovernanceAccess) -> Bool {
        let read = context.read
        return read.operation == .occurrences && (read.scope.clubID ?? 0) > 0 && (read.scope.seriesID ?? 0) > 0 &&
            read.identity?.isSignedIn == true && access.isConfigured && read.identity == access.identity &&
            read.authorizationGeneration == access.authorizationGeneration && read.accessIdentity == ObjectIdentifier(access) &&
            context.namespace == access.storageNamespace
    }
    func accepted(_ context: Context, access: any ClubGovernanceAccess) -> ClubSeriesOccurrencePresentation? {
        guard permit(in: context) != nil, loaded == context, !loading, live(context, access: access) else { return nil }
        return options
    }
    func canOpen(_ route: ClubSeriesOccurrenceRoute, context: Context, access: any ClubGovernanceAccess) -> Bool {
        route.isCurrent(presentation: accepted(context, access: access), context: context.read, snapshotID: snapshotID)
    }
    func leave(_ context: Context) {
        guard bound == context else { return }
        visibility = nil; generation = UUID(); snapshotID = UUID(); loaded = nil
        options = nil; loading = false; failure = nil
    }
    func load(_ permit: Permit, access: any ClubGovernanceAccess, current: @escaping () -> Bool) async {
        guard accepts(permit), current(), !Task.isCancelled else { return }
        guard live(permit.context, access: access) else {
            loaded = nil; options = nil; loading = false
            failure = access.identity?.isSignedIn == true ? .notConfigured : .signedOut; return
        }
        generation = UUID(); let request = generation
        loaded = nil; options = nil; snapshotID = UUID(); failure = nil; loading = true
        defer { if generation == request && accepts(permit) { loading = false } }
        func check() throws {
            guard accepts(permit), generation == request, live(permit.context, access: access), current(), !Task.isCancelled else { throw CancellationError() }
        }
        do {
            try check()
            let snapshot = try await access.read(.occurrences, scope: permit.context.read.scope, options: [:], check: check)
            try check()
            let projected = try ClubSeriesOccurrencePresentation(snapshot: snapshot, context: permit.context.read)
            loaded = permit.context; options = projected
        } catch {
            guard accepts(permit), generation == request, live(permit.context, access: access), current(), !Task.isCancelled else { return }
            failure = error as? ClubGovernanceFailure ?? .malformed
        }
    }
}

@MainActor struct ClubSeriesOccurrenceBrowser: View {
    let scope: ClubGovernanceScope
    let identity: ClubReadIdentity?
    let access: any ClubGovernanceAccess
    let coordinator: ClubGovernanceCoordinator
    @Binding var expanded: Bool
    let sourceIsCurrent: () -> Bool
    @StateObject private var model = ClubSeriesOccurrenceReadModel()
    @State private var selected: ClubSeriesOccurrenceRoute?
    private var context: ClubSeriesOccurrenceReadModel.Context { ClubSeriesOccurrenceReadModel.context(scope: scope, identity: identity, access: access) }
    private struct LoadKey: Hashable { let context: ClubSeriesOccurrenceReadModel.Context; let expanded: Bool }
    var body: some View {
        let expected = context
        let _ = model.bind(expected)
        VStack(alignment: .leading, spacing: 12) {
            Button {
                guard sourceIsCurrent() else { return }; expanded.toggle()
            } label: {
                Label(LocalizedStringKey(expanded ? "club.occurrences.collapse" : "club.occurrences.expand"), systemImage: expanded ? "chevron.up" : "chevron.down")
            }.accessibilityIdentifier("club.occurrences.toggle.\(scope.seriesID ?? 0)")
            if expanded {
                Text("club.occurrences.scopeNote").font(.footnote).foregroundStyle(.secondary)
                if model.loading { ProgressView("club.loading").accessibilityIdentifier("club.occurrences.loading") }
                if let failure = model.failure { Text(LocalizedStringKey(failure.localizationKey)).accessibilityIdentifier("club.occurrences.error") }
                if let value = model.accepted(expected, access: access), sourceIsCurrent() {
                    if value.rows.isEmpty { Text("club.occurrences.empty").accessibilityIdentifier("club.occurrences.empty") }
                    ForEach(value.rows) { row in
                        VStack(alignment: .leading, spacing: 6) {
                            if let date = row.dateText { Text(verbatim: date).font(.headline) }
                            else { Text("club.occurrences.dateUnknown").font(.headline) }
                            if !row.dateIsParsed, row.dateText != nil { Text("club.occurrences.dateUnparsed").font(.caption) }
                            if row.cancelled { Text("club.occurrences.cancelled") }
                            else if row.editable == true { Text("club.occurrences.editable") }
                            else if row.editable == false { Text("club.occurrences.locked") }
                            else { Text("club.occurrences.editabilityUnknown") }
                            if let reason = row.lockReason { Text(verbatim: reason).font(.footnote) }
                            if row.cancelled {
                                if let count = row.refundedCount { LabeledContent("club.occurrences.refunded", value: String(count)) }
                                else { Text("club.occurrences.refundsUnknown") }
                            } else {
                                if let count = row.signupCount { LabeledContent("club.occurrences.signups", value: String(count)) }
                                else { Text("club.occurrences.signupsUnknown") }
                            }
                            if let route = value.route(rowID: row.id, context: expected.read, snapshotID: model.snapshotID) {
                                Button("club.occurrences.openEvent") { guard selected == nil, current(route) else { return }; selected = route }
                                    .accessibilityIdentifier("club.occurrences.event.\(row.activityID ?? 0)")
                            }
                        }.accessibilityIdentifier("club.occurrences.row.\(row.id)")
                        Divider()
                    }
                }
                if model.failure != .forbidden {
                    Button(LocalizedStringKey(model.failure == nil ? "club.gov.refresh" : "action.retry")) {
                        guard expanded, sourceIsCurrent(), let permit = model.permit(in: expected) else { return }
                        Task { await model.load(permit, access: access, current: { expanded && sourceIsCurrent() }) }
                    }.disabled(model.loading || model.permit(in: expected) == nil).accessibilityIdentifier("club.occurrences.reload")
                }
            }
        }
        .buttonStyle(.borderless)
        .task(id: LoadKey(context: expected, expanded: expanded)) {
            guard expanded, sourceIsCurrent() else { selected = nil; model.leave(expected); return }
            guard let permit = model.activate(expected) else { return }
            await model.load(permit, access: access, current: { expanded && sourceIsCurrent() })
        }
        .onChange(of: expanded) { _, value in if !value { selected = nil; model.leave(expected) } }
        .onChange(of: expected) { _, _ in selected = nil }
        .onDisappear { selected = nil; model.leave(expected) }
        .sheet(item: $selected, onDismiss: {
            guard expanded, sourceIsCurrent(), let permit = model.permit(in: expected) else { return }
            Task { await model.load(permit, access: access, current: { expanded && sourceIsCurrent() }) }
        }) { route in
            NavigationStack {
                Group {
                    if current(route) { ClubGovernanceEventView(scope: route.scope, identity: identity, access: access, coordinator: coordinator) }
                    else { Color.clear }
                }
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("club.gov.close") { selected = nil } } }
                .onChange(of: current(route), initial: true) { _, valid in if !valid { selected = nil } }
            }
        }
    }
    private func current(_ route: ClubSeriesOccurrenceRoute) -> Bool {
        expanded && sourceIsCurrent() && model.canOpen(route, context: context, access: access)
    }
}
