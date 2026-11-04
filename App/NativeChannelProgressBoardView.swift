import SwiftUI

public struct NativeChannelProgressTeamOption: Identifiable, Equatable {
    public let id: Int64
    public let name: String
    public init(id: Int64, name: String) throws { guard id > 0, !name.isEmpty else { throw NativeChannelProgressError.invalid }; self.id = id; self.name = name }
}
/// Coalesces selection changes while Core is busy. Resume is event-driven, not a
/// polling/retry loop, and only the last pending user intent is dispatched.
@MainActor final class NativeChannelProgressSelectionQueue: ObservableObject {
    @Published private(set) var pending: NativeChannelProgressQuery?
    @Published private(set) var running = false
    var hasPendingSelection: Bool { running || pending != nil }
    private var active = false
    private var visit = UUID()
    private var task: Task<Void, Never>?

    func activate() { if !active { active = true; visit = UUID() } }
    func retire() {
        active = false; visit = UUID(); task?.cancel(); task = nil
        pending = nil; running = false
    }
    @discardableResult func enqueue(_ query: NativeChannelProgressQuery, isCurrent: @escaping @MainActor () -> Bool,
                 isBusy: @escaping @MainActor () -> Bool,
                 select: @escaping @MainActor (NativeChannelProgressQuery) async -> Void) -> Task<Void, Never>? {
        guard active, isCurrent() else { return nil }
        pending = query
        return resume(isCurrent: isCurrent, isBusy: isBusy, select: select)
    }
    @discardableResult func resume(isCurrent: @escaping @MainActor () -> Bool, isBusy: @escaping @MainActor () -> Bool,
                select: @escaping @MainActor (NativeChannelProgressQuery) async -> Void) -> Task<Void, Never>? {
        guard active, !running, isCurrent(), !isBusy(), pending != nil else { return task }
        running = true
        let stamp = visit
        task = Task { @MainActor [weak self] in
            guard let self, self.active, self.visit == stamp else { return }
            guard !Task.isCancelled, isCurrent() else { self.retire(); return }
            guard !isBusy(), let query = self.pending else {
                self.running = false; self.task = nil; return
            }
            self.pending = nil
            // No suspension between this check and Core's select/begin gate.
            await select(query)
            guard self.active, self.visit == stamp else { return }
            self.running = false; self.task = nil
            guard !Task.isCancelled, isCurrent() else { self.pending = nil; return }
            self.resume(isCurrent: isCurrent, isBusy: isBusy, select: select)
        }
        return task
    }
}

@MainActor struct NativeChannelProgressBoardView: View {
    @Bindable var model: NativeChannelProgressCoordinator
    let board: NativeChannelProgressBoard
    /// Nil means the real team index has not been supplied; IDs are never typed into this screen.
    let teamOptions: [NativeChannelProgressTeamOption]?
    @State private var period = ""
    @State private var completed = "all"
    @State private var teamID: Int64?
    @State private var section = "top"
    @StateObject private var selections = NativeChannelProgressSelectionQueue()
    @StateObject private var actions = NativeChannelProgressActionLifetime()
    var body: some View {
        List {
            Section {
                Picker(selection: $section) {
                    Text("top", tableName: "NativeChannelProgress").tag("top")
                    Text("detail", tableName: "NativeChannelProgress").tag("detail")
                } label: { Text("boardView", tableName: "NativeChannelProgress") }.pickerStyle(.segmented)
                Picker(selection: $period) {
                    ForEach(["ALL","TOPIC","WEEK","MONTH"], id: \.self) { Text(LocalizedStringKey($0), tableName: "NativeChannelProgress").tag($0) }
                } label: { Text("period", tableName: "NativeChannelProgress") }
                if section == "detail" && board.filterSchemaJson["completed"] == "boolean" {
                    Picker(selection: $completed) {
                        Text("all", tableName: "NativeChannelProgress").tag("all")
                        Text("completed", tableName: "NativeChannelProgress").tag("true")
                        Text("inProgress", tableName: "NativeChannelProgress").tag("false")
                    } label: { Text("completionFilter", tableName: "NativeChannelProgress") }
                }
                if section == "detail" && board.filterSchemaJson["team_id"] == "int" {
                    if model.isCurrent, let teamOptions {
                        Picker(selection: $teamID) {
                            Text("allTeams", tableName: "NativeChannelProgress").tag(Int64?.none)
                            ForEach(teamOptions) { team in Text(verbatim: team.name).tag(Optional(team.id)) }
                        } label: { Text("team", tableName: "NativeChannelProgress") }
                    } else { Text("teamIndexUnavailable", tableName: "NativeChannelProgress").font(.caption) }
                }
                Text(verbatim: "\(board.metric) · \(board.scope) · \(board.subjectType)").font(.caption)
                if let rollup = board.teamRollup { Text(verbatim: rollup).font(.caption) }
            }.disabled(!model.isCurrent)
            if model.busy { ProgressView() }
            NativeChannelProgressIssueView(model: model, part: section)
            let buffer = section == "detail" ? model.detail : model.top
            if !selections.hasPendingSelection, let page = buffer.page {
                if !page.visible { Text("hidden", tableName: "NativeChannelProgress").nativeChannelNotice(systemImage: "eye.slash").accessibilityIdentifier("channelProgress.hidden") }
                else {
                    if buffer.rows.isEmpty { Text("empty", tableName: "NativeChannelProgress").nativeChannelNotice(systemImage: "list.number").accessibilityIdentifier("channelProgress.empty") }
                    ForEach(Array(buffer.rows.enumerated()), id: \.offset) { _, row in NativeChannelProgressRowView(row: row) }
                    if page.nextCursor != nil { Button { let detail = section == "detail"; actions.run { await model.loadMore(detail: detail) } } label: { Text("more", tableName: "NativeChannelProgress") }.disabled(model.busy) }
                }
                if let me = page.me { Section { NativeChannelProgressRowView(row: me) } header: { Text("me", tableName: "NativeChannelProgress") } }
                if let asOf = page.asOf { Text(verbatim: asOf).font(.caption).foregroundStyle(.secondary) }
            }
            if !selections.hasPendingSelection, let meter = model.meter {
                Section {
                    if meter.visible, let done = meter.done, let required = meter.required {
                        Text(verbatim: "\(done)/\(required)")
                        if let percent = meter.percent { Text(verbatim: "\(percent)%") }
                    } else { Text("hidden", tableName: "NativeChannelProgress") }
                } header: { Text("ownProgress", tableName: "NativeChannelProgress") }
            }
            NativeChannelProgressIssueView(model: model, part: "meter")
            NavigationLink { NativeChannelProgressOwnHistoryView(model: model) } label: { Text("ownHistory", tableName: "NativeChannelProgress") }
                .disabled(model.busy || selections.hasPendingSelection).accessibilityIdentifier("channelProgress.historyEntry")
        }.nativeChannelScreen().navigationTitle(board.title).privacySensitive()
        .onAppear {
            actions.activate(); selections.activate()
            if period.isEmpty { period = board.period }
            reload()
        }
        .onDisappear { selections.retire(); actions.retire() }
        .onChange(of: period) { old, new in if !old.isEmpty && old != new { reload() } }
        .onChange(of: completed) { _, _ in reload() }
        .onChange(of: teamID) { _, _ in reload() }
        .onChange(of: model.busy) { _, busy in if !busy { resumeSelection() } }
        .onChange(of: model.isCurrent) { _, current in if !current { selections.retire(); actions.retire() } }
        .refreshable { reload() }
        .toolbar { Button { actions.run { await model.checkVersion() } } label: { Image(systemName: "arrow.clockwise") }.disabled(model.busy || selections.hasPendingSelection).accessibilityLabel(Text("refresh", tableName: "NativeChannelProgress")) }
    }
    private func reload() {
        guard let query = try? NativeChannelProgressQuery(board: board, period: period, completed: completed == "all" ? nil : completed == "true", teamID: teamID) else { return }
        let model = model, board = board
        selections.enqueue(query, isCurrent: { model.isCurrent }, isBusy: { model.busy }) { query in
            await model.select(board, query: query)
        }
    }
    private func resumeSelection() {
        let model = model, board = board
        selections.resume(isCurrent: { model.isCurrent }, isBusy: { model.busy }) { query in
            await model.select(board, query: query)
        }
    }
}
struct NativeChannelProgressRowView: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let row: NativeChannelProgressRow
    var body: some View {
        let header = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Space.s1))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Theme.Space.s2))
        VStack(alignment: .leading, spacing: Theme.Space.s1) {
            header {
                Group {
                    if let name = row.displayName { Text(verbatim: name) } else { Text("anonymous", tableName: "NativeChannelProgress") }
                }.fixedSize(horizontal: false, vertical: true)
                if !typeSize.isAccessibilitySize { Spacer() }
                switch NativeChannelProgressRank(row) {
                case .known(let rank): Text(verbatim: "#\(rank)").font(Theme.Font.label).monospacedDigit()
                case .unranked: Text("unranked", tableName: "NativeChannelProgress")
                case .unknown: Text("unconfirmed", tableName: "NativeChannelProgress")
                }
            }
            if row.state == "UNCONFIRMED" { Text("unconfirmed", tableName: "NativeChannelProgress") }
            else if row.state == "NO_COMPLETED_EFFORT" { Text("noCompletedEffort", tableName: "NativeChannelProgress") }
            else if row.state == "NOT_APPLICABLE" { Text("notApplicable", tableName: "NativeChannelProgress") }
            else {
                if let metric = row.metric, let value = row.metricValue { Text(verbatim: "\(metric) · \(value)") }
                if let done = row.done, let required = row.required { Text(verbatim: "\(done)/\(required)") }
                if let percent = row.percent { Text(verbatim: "\(percent)%") }
                if let asOf = row.asOf { Text(verbatim: asOf).font(.caption).foregroundStyle(.secondary) }
            }
        }.accessibilityElement(children: .combine)
    }
}
