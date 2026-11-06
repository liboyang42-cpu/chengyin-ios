import SwiftUI

@MainActor final class ClubCalendarSessionsModel: ObservableObject {
    @Published private(set) var snapshot: ClubCalendarSessionsSnapshot?
    @Published private(set) var snapshotKey: ClubCalendarSessionsReadKey?
    @Published private(set) var failure: ClubGovernanceFailure?
    @Published private(set) var failureKey: ClubCalendarSessionsReadKey?
    @Published private(set) var loading = false
    private(set) var snapshotID = UUID()
    private var boundKey: ClubCalendarSessionsReadKey?
    private var revision: UInt64 = 0
    private var active = true
    func bind(_ key: ClubCalendarSessionsReadKey) {
        if boundKey != key { boundKey = key; revision &+= 1 }
    }
    func invalidate() {
        revision &+= 1; snapshotID = UUID(); snapshot = nil; snapshotKey = nil
        failure = nil; failureKey = nil; loading = false
    }
    func suspend() { active = false; revision &+= 1; loading = false }
    func resume() { active = true }
    func accepted(_ key: ClubCalendarSessionsReadKey, access: any ClubGovernanceAccess) -> ClubCalendarSessionsSnapshot? {
        guard boundKey == key, snapshotKey == key, ClubCalendarSessionsReader.live(key, access: access) else { return nil }
        return snapshot
    }
    func canSelect(_ key: ClubCalendarSessionsReadKey, access: any ClubGovernanceAccess) -> Bool {
        active && !loading && accepted(key, access: access) != nil
    }
    func load(_ key: ClubCalendarSessionsReadKey, access: any ClubGovernanceAccess) async {
        guard active, boundKey == key else { return }
        invalidate(); let expected = revision; loading = true
        defer { if revision == expected { loading = false } }
        func check() throws {
            guard active, boundKey == key, revision == expected, !Task.isCancelled else { throw CancellationError() }
        }
        do {
            let value = try await ClubCalendarSessionsReader.read(key, access: access, check: check)
            try check(); snapshotID = UUID(); snapshotKey = key; snapshot = value
        } catch {
            guard active, boundKey == key, revision == expected, !Task.isCancelled else { return }
            failureKey = key; failure = error as? ClubGovernanceFailure ?? .malformed
        }
    }
}

/// A separately scoped month read; no topic ID is ever treated as an activity ID.
@MainActor struct ClubCalendarSessionsView: View {
    let context: ClubGovernanceReadContext
    let access: any ClubGovernanceAccess
    @State private var month = ClubEventMonth()
    @StateObject private var model = ClubCalendarSessionsModel()
    @State private var visible = false
    @Environment(\.scenePhase) private var scenePhase
    private var key: ClubCalendarSessionsReadKey { .init(context: context, month: month) }
    private struct LoadKey: Hashable {
        let request: ClubCalendarSessionsReadKey
        let active: Bool
    }
    private var loadKey: LoadKey { .init(request: key, active: visible && scenePhase == .active) }
    var body: some View {
        List {
            HStack {
                Button { if let previous = month.shifted(by: -1) { month = previous } }
                    label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("club.calendar.previous").disabled(month.shifted(by: -1) == nil)
                Spacer(); Text(verbatim: month.key); Spacer()
                Button { if let next = month.shifted(by: 1) { month = next } }
                    label: { Image(systemName: "chevron.right") }
                    .accessibilityLabel("club.calendar.next").disabled(month.shifted(by: 1) == nil)
            }
            if model.loading { ProgressView() }
            if model.failureKey == key, let failure = model.failure {
                Text(LocalizedStringKey(failure.localizationKey))
            }
            if loadKey.active, let snapshot = model.accepted(key, access: access) {
                Text(LocalizedStringKey(snapshot.visibility == .governor ? "sessions.governor" : "sessions.public"), tableName: "ClubCalendarSessions")
                if snapshot.truncated { Text("sessions.truncated", tableName: "ClubCalendarSessions") }
                if let updated = snapshot.updatedAt { LabeledContent { Text(verbatim: updated) } label: { Text("sessions.updated", tableName: "ClubCalendarSessions") } }
                if snapshot.sessions.isEmpty { Text(LocalizedStringKey(snapshot.truncated ? "sessions.emptyPartial" : "sessions.empty"), tableName: "ClubCalendarSessions") }
                ForEach(snapshot.sessions) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        if let name = row.name, !name.isEmpty { Text(verbatim: name) }
                        else { Text("sessions.unnamed", tableName: "ClubCalendarSessions") }
                        Text(verbatim: row.startDate)
                        if let end = row.endDate { Text(verbatim: end) }
                        Text(LocalizedStringKey("sessions.state." + row.state.rawValue), tableName: "ClubCalendarSessions")
                    }.accessibilityIdentifier("club.calendar.session.\(row.activityID)")
                }
            }
            Button("club.gov.refresh") { Task { await reload() } }.disabled(!loadKey.active || model.loading)
        }
        .navigationTitle(Text("sessions.title", tableName: "ClubCalendarSessions"))
        .task(id: loadKey) {
            model.invalidate(); model.bind(key)
            if loadKey.active { model.resume(); await model.load(key, access: access) }
            else { model.suspend() }
        }
        .onAppear { visible = true }
        .onDisappear { visible = false; model.suspend(); model.invalidate() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { model.suspend(); model.invalidate() } }
    }
    private func reload() async {
        guard loadKey.active else { return }
        model.bind(key); model.resume(); await model.load(key, access: access)
    }
}
