import SwiftUI

func memberReportProgressText(_ key: String) -> Text { Text(LocalizedStringKey(key), tableName: "MemberReportProgress") }
struct MemberReportProgressTimeView: View {
    let value: MemberReportProgressTime?
    var body: some View {
        if let text = value?.display() { Text(verbatim: text) }
        else { memberReportProgressText("report.time.unknown") }
    }
}
@MainActor struct SquareReportProgressView: View {
    @ObservedObject var session: AppSession
    @Environment(\.scenePhase) private var scene
    @State private var flow: MemberReportProgressCoordinator?
    @State private var owner: MemberReportProgressPresentation?
    @State private var visible = false
    @State private var selection: MemberReportProgressSelection?
    var body: some View {
        let rendered = readIntent()
        List {
            memberReportProgressText("report.read.boundary").font(.footnote)
            if let flow, flow.isCurrent {
                Picker(selection: Binding(get: { flow.filter }, set: { value in
                    guard let (original, intent) = rendered else { return }; original.changeFilter(value, intent: intent)
                })) {
                    ForEach(MemberReportProgressFilter.allCases) { memberReportProgressText("report.filter.\($0.rawValue)").tag($0) }
                } label: { memberReportProgressText("report.filter.title") }.pickerStyle(.segmented).disabled(flow.busy)
                ForEach(flow.records) { record in
                    Button {
                        guard let (original, intent) = rendered, let selected = original.select(record, intent: intent) else { return }
                        selection = selected
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            memberReportProgressText("report.target.\(record.targetKey)")
                            if let label = flow.reasonLabel(for: record) { Text(verbatim: label) }
                            else { memberReportProgressText("report.reason.fallback") }
                            memberReportProgressText("report.stage.\(record.stageKey)").font(.caption)
                            Text(verbatim: "#\(record.id)").font(.caption)
                            MemberReportProgressTimeView(value: record.createTime).font(.caption)
                        }
                    }.disabled(flow.busy || !flow.reader.allows(.detail))
                    .accessibilityIdentifier("report.progress.row.\(record.id)")
                }
                if flow.loaded && flow.records.isEmpty { memberReportProgressText("report.history.empty") }
                if flow.hasMore {
                    Button {
                        guard let (original, intent) = rendered else { return }; original.showMore(intent: intent)
                    } label: { memberReportProgressText("report.history.more") }.disabled(flow.busy)
                }
                if flow.busy { ProgressView() }
                if let failure = flow.failure { memberReportProgressText("report.error.\(failure)").accessibilityIdentifier("report.progress.error") }
            } else { memberReportProgressText("report.error.disabled") }
            Button { load(rendered) } label: { memberReportProgressText("report.refresh") }.disabled(rendered == nil || flow?.busy == true)
        }
        .navigationTitle(memberReportProgressText("report.history.title")).privacySensitive()
        .accessibilityIdentifier("report.progress.history")
        .navigationDestination(item: $selection) { MemberReportProgressDetailView(selection: $0, session: session) }
        .onAppear { visible = true; start() }
        .onDisappear { visible = false; retire() }
        .onChange(of: scene) { _, phase in retire(); if phase == .active { start() } }
        .onChange(of: session.memberReportProgressIdentity) { _, _ in selection = nil; retire(); start() }
        .refreshable { guard let (original, intent) = rendered else { return }; await original.loadHistory(intent: intent) }
    }
    private func start() {
        guard visible, scene == .active else { return }; retire()
        guard let reader = session.makeMemberReportProgressReader() else { return }
        let value = reader.makeCoordinator(); flow = value; owner = value.beginHistory(); load(readIntent())
    }
    private func readIntent() -> (MemberReportProgressCoordinator, MemberReportProgressIntent)? {
        guard visible, scene == .active, let flow, let owner, let intent = flow.capture(owner) else { return nil }
        return (flow, intent)
    }
    private func load(_ read: (MemberReportProgressCoordinator, MemberReportProgressIntent)?) {
        guard let (original, intent) = read, original.accepts(intent) else { return }
        Task { await original.loadHistory(intent: intent) }
    }
    private func retire() { if let owner { flow?.end(owner) }; flow = nil; owner = nil }
}
