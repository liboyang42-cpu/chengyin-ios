import SwiftUI

/// Explicit read-only recovery in the existing create form, including a reopened form after restart.
/// Never passes the replacement draft, clears a lock, submits a writer or mints a return ticket.
@MainActor struct ClubSeriesOriginalResultSection: View {
    let scope: ClubGovernanceScope
    let identity: ClubReadIdentity?
    let access: any ClubGovernanceAccess
    let coordinator: ClubGovernanceCoordinator
    let formID: UUID
    @Environment(\.scenePhase) private var scenePhase
    @State private var visible = false
    @State private var refresh: UInt64 = 0
    @State private var generation: UInt64 = 0
    @State private var busy = false
    @State private var failed = false
    @State private var result: ClubSeriesOriginalResult?
    @State private var displayed: Context?
    private struct Context: Hashable {
        let form: UUID, scope: ClubGovernanceScope, identity: ClubReadIdentity?
        let access: ObjectIdentifier, authorization: UUID?
        let namespace: String, realm: String
    }
    private struct Trigger: Hashable { let context: Context; let visible: Bool; let active: Bool; let refresh: UInt64 }
    private var context: Context {
        .init(form: formID, scope: scope, identity: identity, access: ObjectIdentifier(access),
              authorization: access.authorizationGeneration, namespace: access.storageNamespace, realm: access.journalRealm)
    }
    private var readable: Bool {
        visible && scenePhase == .active && identity == access.identity
            && coordinator.canReadOriginalSeriesResult(scope: scope, identity: identity)
    }
    var body: some View {
        Section {
            Text("seriesOriginal.notice", tableName: "ClubSeriesOriginalResult").font(.footnote).foregroundStyle(.secondary)
            if readable {
                Button { refresh &+= 1 } label: { Text("seriesOriginal.read", tableName: "ClubSeriesOriginalResult") }
                    .disabled(busy).accessibilityIdentifier("club.series.original.read")
                if busy { ProgressView() }
                if failed { Text("seriesOriginal.failed", tableName: "ClubSeriesOriginalResult") }
                if displayed == context, let result {
                    switch result {
                    case .legacyUnknown:
                        Text("seriesOriginal.legacy", tableName: "ClubSeriesOriginalResult")
                    case .unknown:
                        Text("seriesOriginal.unknown", tableName: "ClubSeriesOriginalResult")
                    case .applied(let receipt):
                        Text("seriesOriginal.applied", tableName: "ClubSeriesOriginalResult")
                            .accessibilityIdentifier("club.series.original.applied")
                        Text(verbatim: receipt.requestID).font(.caption).textSelection(.enabled)
                        Text(verbatim: "#\(receipt.seriesID)").font(.headline)
                        ClubGovernanceFactRows(value: receipt.series,
                            fields: ["recurrenceType", "defaultLeadMemberId", "defaultCapacity", "waitlistEnabled", "offerMinutes"])
                        ForEach(Array(receipt.occurrences.enumerated()), id: \.offset) { _, row in
                            VStack(alignment: .leading) {
                                Text(verbatim: "#\(row["activityId"].int ?? 0)")
                                if let ms = row["occurrenceAtEpochMs"].int {
                                    Text(Date(timeIntervalSince1970: Double(ms) / 1000), style: .date)
                                    Text(Date(timeIntervalSince1970: Double(ms) / 1000), style: .time)
                                }
                            }
                        }
                        DisclosureGroup { Text(verbatim: completeJSON(receipt.value)).font(.caption).textSelection(.enabled) }
                            label: { Text("seriesOriginal.complete", tableName: "ClubSeriesOriginalResult") }
                    }
                }
            } else { Text("seriesOriginal.unavailable", tableName: "ClubSeriesOriginalResult").foregroundStyle(.secondary) }
        } header: { Text("seriesOriginal.title", tableName: "ClubSeriesOriginalResult") }
        .privacySensitive()
        .environment(\.timeZone, ClubSeriesScheduleDraft.timeZone)
        .onAppear { visible = true }
        .onDisappear { visible = false; invalidate() }
        .onChange(of: context) { _, _ in invalidate() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { invalidate() } }
        .task(id: Trigger(context: context, visible: visible, active: scenePhase == .active, refresh: refresh)) {
            guard refresh > 0 else { return }; await read()
        }
    }
    private func invalidate() { generation &+= 1; result = nil; displayed = nil; busy = false; failed = false }
    private func completeJSON(_ value: ClubGovernanceValue) -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(value)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }
    private func read() async {
        invalidate(); guard readable else { return }
        let captured = context, revision = generation; busy = true
        func check() throws {
            guard readable, context == captured, generation == revision, !Task.isCancelled else {
                throw ClubSeriesOriginalResultFailure.stale
            }
        }
        do {
            let value = try await coordinator.readOriginalSeriesResult(scope: scope, identity: identity, check: check)
            try check(); result = value; displayed = captured; busy = false
        } catch {
            guard readable, context == captured, generation == revision, !Task.isCancelled else { return }
            busy = false; failed = true; result = nil; displayed = nil
        }
    }
}
