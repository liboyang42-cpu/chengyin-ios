import SwiftUI

func memberScoreText(_ key: String) -> Text { Text(LocalizedStringKey(key), tableName: "MemberScoreAppealList") }
@MainActor struct MemberScoreAppealSettingsEntry: View {
    @ObservedObject var session: AppSession
    var body: some View {
        Section {
            NavigationLink { MemberScoreAppealListView(session: session) } label: {
                Label { memberScoreText("score.mine.title") } icon: { Image(systemName: "text.bubble") }
            }.accessibilityIdentifier("settings.scoreAppeals")
        }
    }
}
@MainActor struct MemberScoreAppealListView: View {
    @ObservedObject var session: AppSession
    @Environment(\.scenePhase) private var scene
    @State private var flow: MemberScoreAppealReadCoordinator?
    @State private var owner: MemberScoreReadPresentation?
    @State private var filter: MemberScoreAppealFilter = .all
    @State private var visible = false
    @State private var selection: MemberScoreAppealSelection?
    var body: some View {
        let rendered = readIntent()
        List {
            memberScoreText("score.mine.boundary").font(.footnote)
            Picker(selection: $filter) {
                ForEach(MemberScoreAppealFilter.allCases) { memberScoreText("score.filter.\($0.rawValue)").tag($0) }
            } label: { memberScoreText("score.filter.title") }.pickerStyle(.segmented)
            if let flow, flow.isCurrent {
                if let reputation = flow.reputation { memberScoreText("score.reputation.\(reputation.rawValue)") }
                else if flow.reputationUnavailable { memberScoreText("score.reputation.unavailable") }
                ForEach(flow.rows) { row in
                    Button {
                        guard let (original, intent) = rendered,
                              let selected = original.select(row, intent: intent) else { return }
                        selection = selected
                    } label: {
                        VStack(alignment: .leading) {
                            memberScoreText("score.kind.\(row.kind.rawValue)")
                            if let title = row.title, !title.isEmpty { Text(verbatim: title) }
                            memberScoreText("score.status.\(row.status.rawValue)").font(.caption)
                            if let time = row.createTime, !time.isEmpty { Text(verbatim: time).font(.caption) }
                            if !row.canReadSession { memberScoreText("score.detail.missingContext").font(.caption) }
                        }
                    }.disabled(flow.busy || !row.canReadSession || !flow.client.allows(.sessionDetail))
                }
                if flow.loaded && flow.rows.isEmpty { memberScoreText("score.mine.empty") }
                if flow.hasMore {
                    Button { load(rendered, more: true) } label: { memberScoreText("score.mine.more") }.disabled(flow.busy)
                }
                if flow.busy { ProgressView() }
                if let failure = flow.failure { memberScoreText("score.error.\(failure)").accessibilityIdentifier("score.mine.status") }
                memberScoreText("score.time.source").font(.footnote)
            } else { memberScoreText("score.error.disabled") }
            Button { load(rendered) } label: { memberScoreText("score.mine.refresh") }.disabled(rendered == nil || flow?.busy == true)
        }
        .navigationTitle(memberScoreText("score.mine.title")).privacySensitive()
        .accessibilityIdentifier("score.mine.list")
        .navigationDestination(item: $selection) { MemberScoreAppealDetailView(selection: $0, session: session) }
        .onAppear { visible = true; start() }
        .onDisappear { visible = false; retire() }
        .onChange(of: filter) { _, _ in start() }
        .onChange(of: scene) { _, phase in retire(); if phase == .active { start() } }
        .onChange(of: session.memberScoreReadIdentity) { _, _ in selection = nil; retire(); start() }
        .refreshable { guard let (original, intent) = rendered else { return }; await original.loadList(intent: intent) }
    }
    private func start() {
        guard visible, scene == .active else { return }; retire()
        guard let client = session.makeMemberScoreAppealListClient() else { return }
        let value = client.makeCoordinator(); flow = value; owner = value.beginList(filter: filter)
        load(readIntent())
    }
    private func readIntent() -> (MemberScoreAppealReadCoordinator, MemberScoreReadIntent)? {
        guard visible, scene == .active, let flow, let owner, let intent = flow.capture(owner) else { return nil }
        return (flow, intent)
    }
    private func load(_ read: (MemberScoreAppealReadCoordinator, MemberScoreReadIntent)?, more: Bool = false) {
        guard let (original, intent) = read, original.accepts(intent) else { return }
        Task { await original.loadList(more: more, intent: intent) }
    }
    private func retire() { if let owner { flow?.end(owner) }; flow = nil; owner = nil }
}
