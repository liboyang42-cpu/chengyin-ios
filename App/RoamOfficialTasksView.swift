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
@MainActor private final class RoamOfficialTasksViewModel: ObservableObject {
    let model: RoamOfficialTasksModel
    @Published private var revision = 0
    init(roam: any RoamExperienceReading, official: any OfficialEventReading) {
        model = .init(roam: roam, official: official)
        model.onChange = { [weak self] in self?.revision &+= 1 }
    }
}
@MainActor struct RoamOfficialTasksView: View {
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
        List {
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
                        OfficialIssueView(issue: .init(error), retry: { Task { await model.load() } })
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
                            guard target == nil else { return }
                            target = model.select(eventID: event.id, query: query, renderedSnapshotID: snapshot.id)
                        } label: { OfficialEventCard(event: event) }
                            .buttonStyle(QuestifyCardButtonStyle()).questifyCardListRow()
                            .disabled(model.isLoading)
                            .accessibilityIdentifier("roam.tasks.event.\(event.id)")
                    }
                }
            } else if let error = model.error {
                Section { OfficialIssueView(issue: .init(error), retry: { Task { await model.load() } }) }
                    .accessibilityIdentifier("roam.tasks.error")
            }
            if model.isLoading || (model.snapshot == nil && model.error == nil) {
                ProgressView("official.loading").accessibilityIdentifier("roam.tasks.loading")
            }
        }.navigationTitle("roam.tasks.title")
            .task(id: model.owner) { await model.load() }
            .onAppear { model.appear() }
            .onDisappear { if target == nil { model.invalidate() } else { model.cancelPending() } }
            .refreshable { await model.load() }
            .onChange(of: model.owner) { _, _ in bucket = .live; keyword = ""; target = nil }
            .navigationDestination(item: $target) { selection in
                if model.mayRemainOpen(selection) {
                    OfficialEventDetailView(id: selection.eventID, reader: reader)
                } else { ContentUnavailableView("roam.tasks.changed", systemImage: "person.crop.circle.badge.exclamationmark") }
            }
            .accessibilityIdentifier("roam.tasks.browser")
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
