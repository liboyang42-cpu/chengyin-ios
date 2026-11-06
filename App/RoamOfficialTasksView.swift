import SwiftUI

/// Ordinary composition obtains the existing concrete session reader. An unrelated or stale Roam
/// reader cannot be used to open another account's official participation. No writer is constructed.
@MainActor struct RoamOfficialTasksDestination: View {
    let roamReader: any RoamExperienceReading
    var body: some View {
        if roamReader.isOfflineExample {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--uitesting-roam-experience") {
                RoamOfficialTasksFixtureDestination(roamReader: roamReader)
            } else { ContentUnavailableView("roam.tasks.changed", systemImage: "person.crop.circle.badge.exclamationmark") }
            #else
            ContentUnavailableView("roam.tasks.changed", systemImage: "person.crop.circle.badge.exclamationmark")
            #endif
        } else { SessionRoamOfficialTasksDestination(roamReader: roamReader) }
    }
}
@MainActor private struct SessionRoamOfficialTasksDestination: View {
    @EnvironmentObject private var session: AppSession
    let roamReader: any RoamExperienceReading
    var body: some View {
        if ObjectIdentifier(roamReader) == ObjectIdentifier(session.roamExperienceReader), roamReader.identity != nil {
            RoamOfficialTasksView(roamReader: roamReader, reader: session.officialEventReader)
                .id(session.sessionRevision)
        } else { ContentUnavailableView("roam.tasks.changed", systemImage: "person.crop.circle.badge.exclamationmark") }
    }
}
/// Foreground visit admission only; the original Core model owns the two-list snapshot.
@MainActor final class RoamOfficialTasksViewModel: ObservableObject {
    let model: RoamOfficialTasksModel
    @Published private var revision = 0
    private var mounted = false
    private var foreground = false
    private var visit = UUID()
    private var work: Task<Void, Never>?
    var isVisible: Bool { mounted && foreground }
    init(roam: any RoamExperienceReading, official: any OfficialEventReading) {
        model = .init(roam: roam, official: official)
        model.onChange = { [weak self] in self?.revision &+= 1 }
    }
    func appear(foreground: Bool) {
        mounted = true; self.foreground = foreground
        retire(preservingSnapshot: false)
        if foreground { model.appear(); readAction()() }
    }
    func disappear(preservingSnapshot: Bool) {
        mounted = false; retire(preservingSnapshot: preservingSnapshot)
    }
    func setForeground(_ value: Bool, preservingSnapshot: Bool) {
        guard foreground != value else { return }
        foreground = value; retire(preservingSnapshot: preservingSnapshot)
        // The pushed detail keeps its original snapshot. Foreground cannot remount
        // or reload this hidden list and revoke the accepted detail target.
        if value && mounted { model.appear(); readAction()() }
    }
    func ownerChanged() {
        retire(preservingSnapshot: false)
        // Preserve the original keyed task's current-owner recovery, but only on
        // the mounted foreground list. A source notification cannot remount it.
        if isVisible { model.appear(); readAction()() }
    }
    private func retire(preservingSnapshot: Bool) {
        visit = UUID(); work?.cancel(); work = nil
        if preservingSnapshot { model.cancelPending() } else { model.invalidate() }
        revision &+= 1
    }
    private func accepts(_ offered: UUID, owner: RoamOfficialTasksOwner) -> Bool {
        isVisible && offered == visit && owner == model.owner && !Task.isCancelled
    }
    func readAction() -> () -> Void {
        let offered = visit, owner = model.owner
        return { [weak self] in
            guard let self, self.accepts(offered, owner: owner) else { return }
            self.work?.cancel()
            self.work = Task { [weak self] in
                guard let self else { return }
                await self.read(offered: offered, owner: owner)
            }
        }
    }
    func refreshAction() -> () async -> Void {
        let offered = visit, owner = model.owner
        return { [weak self] in
            guard let self else { return }
            await self.read(offered: offered, owner: owner)
        }
    }
    private func read(offered: UUID, owner: RoamOfficialTasksOwner) async {
        guard accepts(offered, owner: owner) else { return }
        await model.load()
    }
}
@MainActor struct RoamOfficialTasksView: View {
    let roamReader: any RoamExperienceReading
    let reader: any OfficialEventReading
    var body: some View {
        RoamOfficialTasksContent(roamReader: roamReader, reader: reader)
            .id(RoamOfficialTasksOwner(roam: roamReader, official: reader))
    }
}
@MainActor private struct RoamOfficialTasksContent: View {
    @Environment(\.scenePhase) private var scenePhase
    let reader: any OfficialEventReading
    @StateObject private var viewModel: RoamOfficialTasksViewModel
    @State private var bucket: OfficialEventBucket = .live
    @State private var keyword = ""
    @State private var target: RoamOfficialTaskTarget?
    init(roamReader: any RoamExperienceReading, reader: any OfficialEventReading) {
        self.reader = reader; _viewModel = StateObject(wrappedValue: .init(roam: roamReader, official: reader))
    }
    private var model: RoamOfficialTasksModel { viewModel.model }
    private var query: OfficialEventBrowseQuery { .init(bucket: bucket, keyword: keyword) }
    var body: some View {
        let retry = viewModel.readAction(), refresh = viewModel.refreshAction()
        List {
            if viewModel.isVisible {
            Section {
                TextField("official.search", text: $keyword).textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("roam.tasks.search")
                Picker("official.filter", selection: $bucket) {
                    ForEach(OfficialEventBucket.allCases) { value in Text(LocalizedStringKey(value.titleKey)).tag(value) }
                }.pickerStyle(.menu).accessibilityIdentifier("roam.tasks.filter")
                OfficialReadOnlyNotice(offline: reader.isOfflineExample)
            }
            if let snapshot = model.snapshot {
                if let error = model.error {
                    Section {
                        Text("roam.tasks.stale").font(.caption).foregroundStyle(.secondary)
                        OfficialIssueView(issue: .init(error), retry: retry)
                    }.accessibilityIdentifier("roam.tasks.stale")
                }
                let rows = snapshot.visible(query)
                Section {
                    LabeledContent("official.results", value: String(rows.count))
                        .accessibilityIdentifier("roam.tasks.results")
                    if rows.isEmpty {
                        Text(LocalizedStringKey(query.emptyKey)).accessibilityIdentifier("roam.tasks.empty")
                    }
                    ForEach(rows) { event in
                        Button {
                            guard viewModel.isVisible, target == nil else { return }
                            target = model.select(eventID: event.id, query: query, renderedSnapshotID: snapshot.id)
                        } label: { OfficialEventCard(event: event) }
                            .buttonStyle(QuestifyCardButtonStyle()).questifyCardListRow()
                            .disabled(model.isLoading)
                            .accessibilityIdentifier("roam.tasks.event.\(event.id)")
                    }
                }
            } else if let error = model.error {
                Section { OfficialIssueView(issue: .init(error), retry: retry) }
                    .accessibilityIdentifier("roam.tasks.error")
            }
            if model.isLoading || (model.snapshot == nil && model.error == nil) {
                ProgressView("official.loading").accessibilityIdentifier("roam.tasks.loading")
            }
            } else { ProgressView("official.loading").accessibilityIdentifier("roam.tasks.loading") }
        }.navigationTitle("roam.tasks.title").navigationBarTitleDisplayMode(.inline)
            .onAppear { viewModel.appear(foreground: scenePhase == .active) }
            .onDisappear { viewModel.disappear(preservingSnapshot: target != nil) }
            .onChange(of: scenePhase) { _, phase in
                viewModel.setForeground(phase == .active, preservingSnapshot: target != nil)
            }
            .refreshable { await refresh() }
            .onChange(of: model.owner) { _, _ in bucket = .live; keyword = ""; target = nil; viewModel.ownerChanged() }
            .navigationDestination(item: $target) { selection in
                if model.mayRemainOpen(selection) {
                    OfficialEventDetailView(id: selection.eventID, reader: reader)
                } else { ContentUnavailableView("roam.tasks.changed", systemImage: "person.crop.circle.badge.exclamationmark") }
            }
            .accessibilityIdentifier("roam.tasks.browser")
            .privacySensitive()
    }
}
#if DEBUG
/// Synthetic fixture stays in the already selected offline Roam harness; flags never enable a
/// production reader, endpoint, writer, account or capability.
@MainActor private struct RoamOfficialTasksFixtureDestination: View {
    let roamReader: any RoamExperienceReading
    @State private var official: OfficialFixtureReader
    init(roamReader: any RoamExperienceReading) {
        self.roamReader = roamReader
        let args = ProcessInfo.processInfo.arguments, index = args.firstIndex(of: "--uitesting-roam-tasks-scenario")
        let raw = index.flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
        _official = State(initialValue: OfficialFixtureReader(scenario: raw.flatMap(OfficialFixtureReader.Scenario.init(rawValue:)) ?? .content))
    }
    var body: some View { RoamOfficialTasksView(roamReader: roamReader, reader: official) }
}
#endif
