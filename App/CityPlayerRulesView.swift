import SwiftUI

@MainActor struct CityPlayerRulesPresentation: Identifiable {
    let id = UUID()
    let readID: UUID
    let read: CityReadSnapshot
    let flow: CityPlayerRulesFlow
}

/// Full published public rule text and allowlisted policies, never a server-plan dump.
@MainActor struct CityPlayerRulesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State var flow: CityPlayerRulesFlow
    @State private var visible = false
    let selectionIsCurrent: () -> Bool
    private let table = "CityPlayerRules"
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("cityRules.boundary", tableName: table).fixedSize(horizontal: false, vertical: true)
                    if flow.phase == .loading { ProgressView { Text("cityRules.loading", tableName: table) } }
                    else if flow.phase != .ready {
                        Text(LocalizedStringKey("cityRules.phase." + flow.phase.rawValue), tableName: table)
                            .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("cityRules.state")
                    }
                    Button { Task { await flow.load() } } label: { Text("cityRules.refresh", tableName: table) }
                        .disabled(flow.phase == .loading || !visible || scenePhase != .active || !flow.current)
                        .accessibilityIdentifier("cityRules.refresh")
                }
                if let snapshot = flow.snapshot {
                    Section {
                        Text(verbatim: snapshot.board.title).font(.headline)
                        row("boardId", snapshot.board.boardId); row("seasonId", snapshot.board.seasonId)
                        row("rulesReleaseId", snapshot.board.rulesReleaseId); row("revision", String(snapshot.board.revision))
                        row("rulesHash", snapshot.board.rulesHash)
                    } header: { Text("cityRules.identity", tableName: table) }
                    Section {
                        Text(LocalizedStringKey("cityRules.eligibility." + snapshot.eligibility.status), tableName: table)
                            .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("cityRules.eligibility")
                        if let id = snapshot.eligibility.teamId { row("teamId", id) }
                        if let version = snapshot.eligibility.teamVersion { row("teamVersion", String(version)) }
                        if let id = snapshot.eligibility.sessionId { row("sessionId", id) }
                        if let count = snapshot.eligibility.memberCount { row("memberCount", String(count)) }
                        if let count = snapshot.eligibility.presentCount { row("presentCount", String(count)) }
                        if let count = snapshot.eligibility.confirmedCount { row("confirmedCount", String(count)) }
                        Text("cityRules.noActionGrant", tableName: table).font(.footnote)
                    } header: { Text("cityRules.eligibility.title", tableName: table) }
                    ForEach(snapshot.sections) { section in
                        Section {
                            if section.status != "PUBLISHED" {
                                Text(LocalizedStringKey("cityRules.disclosure." + section.status), tableName: table)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            ForEach(section.rows) { item in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(LocalizedStringKey("cityRules.field." + item.key), tableName: table).font(.caption).foregroundStyle(.secondary)
                                    value(item, sectionID: section.id).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                                }.accessibilityIdentifier("cityRules.field.\(section.id).\(item.key)")
                            }
                        } header: { Text(LocalizedStringKey("cityRules.section." + section.id), tableName: table) }
                    }
                    Section { Text("cityRules.excluded", tableName: table).font(.footnote) }
                }
            }
            .navigationTitle(Text("cityRules.title", tableName: table))
            .accessibilityIdentifier("cityRules.screen")
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button { flow.cancel(); dismiss() } label: { Text("cityRules.back", tableName: table) }
                    .accessibilityIdentifier("cityRules.back")
            } }
            .task {
                visible = true
                flow.bindSelection { visible && scenePhase == .active && selectionIsCurrent() }
                guard scenePhase == .active else { return }
                await flow.load()
            }
            .onChange(of: scenePhase) { _, phase in
                flow.cancel()
                if visible && phase == .active { Task { await flow.load() } }
            }
            .onDisappear { visible = false; flow.cancel() }
        }
    }
    private func row(_ key: String, _ value: String) -> some View {
        LabeledContent { Text(verbatim: value).textSelection(.enabled) } label: { Text(LocalizedStringKey("cityRules.field." + key), tableName: table) }
    }
    private func value(_ row: CityPlayerRulesRow, sectionID: String) -> Text {
        if let key = row.localizationKey(sectionID: sectionID) {
            return Text(LocalizedStringKey(key), tableName: table)
        }
        return Text(verbatim: row.value)
    }
}
