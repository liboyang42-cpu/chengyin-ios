import SwiftUI

@MainActor struct MemberScoreAppealDetailView: View {
    let selection: MemberScoreAppealSelection
    @ObservedObject var session: AppSession
    @Environment(\.scenePhase) private var scene
    @State private var flow: MemberScoreAppealReadCoordinator?
    @State private var owner: MemberScoreReadPresentation?
    @State private var visible = false
    var body: some View {
        let rendered = readIntent()
        List {
            if let flow, let row = flow.detailRow {
                if let title = row.title { Text(verbatim: title) }
                memberScoreText("score.kind.\(row.kind.rawValue)")
                if let session = row.sessionID { Text(verbatim: "#\(session) · #\(row.recordID)").font(.caption) }
                if let value = flow.detail {
                    memberScoreText("score.status.\(value.status.rawValue)")
                    if let note = value.resolutionNote, !note.isEmpty { Text(verbatim: note) }
                    LabeledContent { Text(verbatim: String(value.totalCenti)) } label: { memberScoreText("score.detail.centi") }
                }
                if flow.busy { ProgressView() }
                if let failure = flow.failure { memberScoreText("score.error.\(failure)") }
            } else { memberScoreText("score.error.disabled") }
            memberScoreText("score.detail.boundary").font(.footnote)
            Button { load(rendered) } label: { memberScoreText("score.detail.refresh") }.disabled(rendered == nil || flow?.busy == true)
        }
        .navigationTitle(memberScoreText("score.detail.title")).privacySensitive()
        .accessibilityIdentifier("score.mine.detail")
        .onAppear { visible = true; start() }
        .onDisappear { visible = false; retire() }
        .onChange(of: scene) { _, phase in retire(); if phase == .active { start() } }
        .onChange(of: session.memberScoreReadIdentity) { _, _ in retire() }
        .onChange(of: selection.client.isCurrent) { _, valid in if !valid { retire() } }
    }
    private func start() {
        guard visible, scene == .active else { return }; retire()
        guard selection.client.isCurrent else { return }
        let value = selection.client.makeCoordinator(); flow = value; owner = value.beginDetail(selection.row)
        load(readIntent())
    }
    private func readIntent() -> (MemberScoreAppealReadCoordinator, MemberScoreReadIntent)? {
        guard visible, scene == .active, let flow, let owner, let intent = flow.capture(owner) else { return nil }
        return (flow, intent)
    }
    private func load(_ read: (MemberScoreAppealReadCoordinator, MemberScoreReadIntent)?) {
        guard let (original, intent) = read, original.accepts(intent) else { return }
        Task { await original.loadDetail(intent: intent) }
    }
    private func retire() { if let owner { flow?.end(owner) }; flow = nil; owner = nil }
}
