import SwiftUI
import UIKit

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

@MainActor final class ClubSeriesOccurrenceHost: ObservableObject {
    struct Source: Equatable {
        let parent: ClubGovernanceSnapshot
        let context: ClubGovernanceReadContext
        let generation: UInt64
        let occurrences: ClubSeriesOccurrenceReadModel.Context
        let scope: ClubGovernanceScope
        @MainActor init?(snapshot: ClubGovernanceSnapshot, context: ClubGovernanceReadContext,
                         generation: UInt64, seriesID: Int, access: any ClubGovernanceAccess) {
            guard context.operation == .series, context.accepts(snapshot), context.identity?.isSignedIn == true,
                  access.identity == context.identity, access.isConfigured,
                  context.authorizationGeneration == access.authorizationGeneration,
                  context.accessIdentity == ObjectIdentifier(access),
                  snapshot.permissions?.allows(ClubGovernanceRead.series.permission, scope: context.scope) == true,
                  let rows = snapshot.value.array, rows.filter({ $0["id"].int == seriesID }).count == 1,
                  let row = rows.first(where: { $0["id"].int == seriesID }), seriesID > 0,
                  row["clubId"].int == context.scope.clubID, let topicID = row["topicId"].int, topicID > 0 else { return nil }
            let scope = ClubGovernanceScope(clubID: context.scope.clubID, topicID: topicID, seriesID: seriesID)
            parent = snapshot; self.context = context; self.generation = generation; self.scope = scope
            occurrences = ClubSeriesOccurrenceReadModel.context(scope: scope, identity: context.identity, access: access)
        }
    }
    struct Selection: Identifiable {
        let id = UUID()
        let attachment: UUID
        let source: Source
        let route: ClubSeriesOccurrenceRoute
    }
    let model = ClubSeriesOccurrenceReadModel()
    @Published private(set) var source: Source?
    @Published private(set) var selected: Selection?
    @Published private(set) var isPresented = false
    @Published private(set) var attachment: UUID?
    @Published private(set) var visible = false
    @Published private(set) var needsRefresh = false
    private var returning = false
    private var readID: UUID?
    var retainsDestination: Bool { selected != nil || returning }
    func appear() { visible = true; if attachment == nil { attachment = UUID() } }
    func hide() {
        visible = false
        if selected == nil, readID != nil, let source {
            model.leave(source.occurrences); readID = nil; needsRefresh = true
        }
    }
    @discardableResult func depart(_ expected: UUID) -> Bool {
        guard attachment == expected else { return false }
        retire(); attachment = nil; visible = false; return true
    }
    func retire() {
        if let source { model.leave(source.occurrences) }
        source = nil; selected = nil; isPresented = false; needsRefresh = false; returning = false; readID = nil
    }
    func background() {
        if let source { model.leave(source.occurrences); needsRefresh = true; returning = true }
        selected = nil; isPresented = false; readID = nil
    }
    func invalidateUnlessCurrent(_ current: Source?) { if source != current { retire() } }
    func toggle(_ source: Source, current: Source?, active: Bool) {
        guard visible, active, attachment != nil, selected == nil, source == current else { return }
        if self.source == source { retire(); return }
        retire(); self.source = source; needsRefresh = true
    }
    func requestReload(_ source: Source, current: Source?, active: Bool) -> Bool {
        guard visible, active, self.source == source, source == current, selected == nil, !model.loading else { return false }
        needsRefresh = true; return true
    }
    func loadIfNeeded(access: any ClubGovernanceAccess, current: @escaping () -> Source?, active: @escaping () -> Bool) async {
        guard visible, active(), let attachment, let source, source == current(), selected == nil,
              needsRefresh, readID == nil, !Task.isCancelled else { return }
        model.bind(source.occurrences)
        guard let permit = model.activate(source.occurrences) else { return }
        let run = UUID(), previousSnapshot = model.snapshotID; readID = run
        defer { if self.attachment == attachment, self.source == source, readID == run { readID = nil } }
        await model.load(permit, access: access, current: {
            self.attachment == attachment && self.source == source && source == current() && self.visible && active() &&
                self.readID == run && self.selected == nil
        })
        guard self.attachment == attachment, self.source == source, source == current(), readID == run,
              visible, active(), !Task.isCancelled, model.snapshotID != previousSnapshot else { return }
        if model.accepted(source.occurrences, access: access) != nil { needsRefresh = false; returning = false }
    }
    func open(_ route: ClubSeriesOccurrenceRoute, source: Source, current: Source?, access: any ClubGovernanceAccess, active: Bool) {
        guard visible, active, let attachment, self.source == source, source == current, selected == nil,
              !needsRefresh, model.canOpen(route, context: source.occurrences, access: access) else { return }
        selected = .init(attachment: attachment, source: source, route: route); isPresented = true
    }
    func isCurrent(_ item: Selection, current: Source?, access: any ClubGovernanceAccess) -> Bool {
        selected?.id == item.id && attachment == item.attachment && source == item.source && item.source == current &&
            model.canOpen(item.route, context: item.source.occurrences, access: access)
    }
    func binding(_ item: Selection, current: @escaping () -> Source?, access: any ClubGovernanceAccess) -> Binding<Bool> {
        Binding(get: { self.isPresented && self.isCurrent(item, current: current(), access: access) }, set: { shown in
            guard !shown, self.isCurrent(item, current: current(), access: access) else { return }
            self.isPresented = false
        })
    }
    @discardableResult func closed(_ item: Selection, current: Source?, access: any ClubGovernanceAccess) -> Bool {
        guard !isPresented, isCurrent(item, current: current, access: access) else { return false }
        selected = nil; needsRefresh = true; returning = true; return true
    }
    func retire(_ item: Selection) { if selected?.id == item.id { retire() } }
}

@MainActor struct ClubSeriesOccurrencePresentationOwner: View {
    let item: ClubSeriesOccurrenceHost.Selection
    @ObservedObject var host: ClubSeriesOccurrenceHost
    let access: any ClubGovernanceAccess
    let coordinator: ClubGovernanceCoordinator
    let current: () -> ClubSeriesOccurrenceHost.Source?
    let active: () -> Bool
    let returned: () -> Void
    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .sheet(isPresented: host.binding(item, current: current, access: access), onDismiss: {
                if host.closed(item, current: current(), access: access) { returned() }
            }) {
                NavigationStack {
                    Group {
                        if active(), host.isCurrent(item, current: current(), access: access) {
                            ClubGovernanceEventView(scope: item.route.scope, identity: item.source.context.identity, access: access, coordinator: coordinator)
                        } else { Color.clear }
                    }
                    .toolbar { ToolbarItem(placement: .cancellationAction) {
                        Button("club.gov.close") { host.binding(item, current: current, access: access).wrappedValue = false }
                    } }
                    .onChange(of: active() && host.isCurrent(item, current: current(), access: access), initial: true) { _, valid in
                        if !valid { host.retire(item) }
                    }
                }
            }
    }
}

@MainActor struct ClubSeriesOccurrenceLifetime: UIViewControllerRepresentable {
    let leave: () -> Void
    func makeUIViewController(context: Context) -> Controller { Controller(leave: leave) }
    func updateUIViewController(_ controller: Controller, context: Context) { controller.leave = leave }
    static func dismantleUIViewController(_ controller: Controller, coordinator: ()) { controller.leave() }
    @MainActor final class Controller: UIViewController {
        var leave: () -> Void
        private var attached = false
        init(leave: @escaping () -> Void) { self.leave = leave; super.init(nibName: nil, bundle: nil) }
        required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            if parent != nil { attached = true } else if attached { leave() }
        }
        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            var node: UIViewController? = self
            while let current = node {
                if current.isMovingFromParent || current.isBeingDismissed { leave(); return }
                node = current.parent
            }
        }
    }
}

@MainActor struct ClubSeriesOccurrenceBrowser: View {
    let source: ClubSeriesOccurrenceHost.Source
    let access: any ClubGovernanceAccess
    @ObservedObject var host: ClubSeriesOccurrenceHost
    @ObservedObject var model: ClubSeriesOccurrenceReadModel
    let currentSource: () -> ClubSeriesOccurrenceHost.Source?
    let active: () -> Bool
    let reload: () -> Void
    @Environment(\.locale) private var locale
    private var scope: ClubGovernanceScope { source.scope }
    private var context: ClubSeriesOccurrenceReadModel.Context { source.occurrences }
    private var expanded: Bool { host.source == source }
    private func sourceIsCurrent() -> Bool { currentSource() == source }
    var body: some View {
        let expected = context
        VStack(alignment: .leading, spacing: 12) {
            Button {
                host.toggle(source, current: currentSource(), active: active())
            } label: {
                Label { Text("clubOpsEvent.occurrences.toggle", tableName: "ClubOpsEvent") } icon: { Image(systemName: expanded ? "chevron.up" : "chevron.down") }
                    .accessibilityHint(Text(LocalizedStringKey(expanded ? "club.occurrences.collapse" : "club.occurrences.expand")))
            }.accessibilityIdentifier("club.occurrences.toggle.\(scope.seriesID ?? 0)")
            if expanded {
                Text("club.occurrences.scopeNote").font(.footnote).foregroundStyle(.secondary)
                if model.loading { ProgressView("club.loading").accessibilityIdentifier("club.occurrences.loading") }
                if let failure = model.failure { Text(LocalizedStringKey(failure.localizationKey)).accessibilityIdentifier("club.occurrences.error") }
                if let value = model.accepted(expected, access: access), sourceIsCurrent() {
                    if value.rows.isEmpty { Text("clubOpsEvent.occurrences.empty", tableName: "ClubOpsEvent").accessibilityIdentifier("club.occurrences.empty") }
                    ForEach(value.rows) { row in
                        VStack(alignment: .leading, spacing: 6) {
                            // Mini occurrenceRow: Shanghai "M月d日 周X HH:mm", one badge and one meta line.
                            if let date = row.dateText {
                                Text(verbatim: row.dateIsParsed ? (ClubOpsEventClock.occurrenceText(.string(date), locale: locale) ?? date) : date).font(.headline)
                            } else { Text("clubOpsEvent.occurrences.datePending", tableName: "ClubOpsEvent").font(.headline) }
                            if !row.dateIsParsed, row.dateText != nil { Text("club.occurrences.dateUnparsed").font(.caption) }
                            let copy = ClubOpsEventOccurrenceCopy(row: row)
                            ClubOpsEventOccurrenceBadgeText(badge: copy.badge)
                            ClubOpsEventOccurrenceMetaText(meta: copy.meta).font(.footnote).foregroundStyle(.secondary)
                            if let route = value.route(rowID: row.id, context: expected.read, snapshotID: model.snapshotID) {
                                Button("club.occurrences.openEvent") { host.open(route, source: source, current: currentSource(), access: access, active: active()) }
                                    .accessibilityIdentifier("club.occurrences.event.\(row.activityID ?? 0)")
                            }
                        }.accessibilityIdentifier("club.occurrences.row.\(row.id)")
                        Divider()
                    }
                }
                if model.failure != .forbidden {
                    Button(LocalizedStringKey(model.failure == nil ? "club.gov.refresh" : "action.retry")) {
                        guard host.requestReload(source, current: currentSource(), active: active()) else { return }
                        reload()
                    }.disabled(model.loading || model.permit(in: expected) == nil).accessibilityIdentifier("club.occurrences.reload")
                }
            }
        }
        .buttonStyle(.borderless)
    }
}
