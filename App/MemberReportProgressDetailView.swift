import SwiftUI

@MainActor struct MemberReportProgressDetailView: View {
    let selection: MemberReportProgressSelection
    @ObservedObject var session: AppSession
    @Environment(\.scenePhase) private var scene
    @State private var flow: MemberReportProgressCoordinator?
    @State private var owner: MemberReportProgressPresentation?
    @State private var visible = false
    var body: some View {
        let rendered = readIntent()
        List {
            if let flow, let original = flow.detailRecord {
                Text(verbatim: "#\(original.id)").font(.caption)
                if let record = flow.detail {
                    memberReportProgressText("report.target.\(record.targetKey)")
                    LabeledContent { Text(verbatim: String(record.targetId)) } label: { memberReportProgressText("report.target.id") }
                    memberReportProgressText("report.stage.\(record.stageKey)")
                    if let label = flow.reasonLabel(for: record) { Text(verbatim: label) }
                    else { memberReportProgressText("report.reason.fallback") }
                    if let version = record.policyVersion { LabeledContent { Text(verbatim: version) } label: { memberReportProgressText("report.policy") } }
                    LabeledContent { Text(verbatim: String(record.version)) } label: { memberReportProgressText("report.version") }
                    if let description = record.description, !description.isEmpty { Text(verbatim: description) }
                    if let summary = record.decisionSummary, !summary.isEmpty {
                        Section { Text(verbatim: summary) } header: { memberReportProgressText("report.decision") }
                    }
                    LabeledContent { MemberReportProgressTimeView(value: record.createTime) } label: { memberReportProgressText("report.created") }
                    if !record.isDecided, record.estimatedResolveAt != nil {
                        LabeledContent { MemberReportProgressTimeView(value: record.estimatedResolveAt) } label: { memberReportProgressText("report.estimated") }
                    }
                    if record.anonymityPolicy == "SUBJECT_HIDDEN" { memberReportProgressText("report.privacy.source").font(.footnote) }
                    if let evidence = record.evidenceAssetIds {
                        LabeledContent { Text(verbatim: String(evidence.count)) } label: { memberReportProgressText("report.evidence.count") }
                    }
                    Section {
                        if let timeline = record.timeline, !timeline.isEmpty {
                            ForEach(Array(timeline.enumerated()), id: \.offset) { _, event in
                                VStack(alignment: .leading, spacing: 4) {
                                    memberReportProgressText(event.titleKey)
                                    if let stageKey = event.stageKey { memberReportProgressText("report.stage.\(stageKey)").font(.caption) }
                                    if let note = event.publicNote, !note.isEmpty { Text(verbatim: note) }
                                    MemberReportProgressTimeView(value: event.createTime).font(.caption)
                                }
                            }
                        } else { memberReportProgressText("report.timeline.empty") }
                    } header: { memberReportProgressText("report.timeline.title") }
                }
                if flow.busy { ProgressView() }
                if let failure = flow.failure { memberReportProgressText("report.error.\(failure)") }
            } else { memberReportProgressText("report.error.disabled") }
            memberReportProgressText("report.detail.boundary").font(.footnote)
            Button { load(rendered) } label: { memberReportProgressText("report.refresh") }.disabled(rendered == nil || flow?.busy == true)
        }
        .navigationTitle(memberReportProgressText("report.detail.title")).privacySensitive()
        .accessibilityIdentifier("report.progress.detail")
        .onAppear { visible = true; start() }
        .onDisappear { visible = false; retire() }
        .onChange(of: scene) { _, phase in retire(); if phase == .active { start() } }
        .onChange(of: session.memberReportProgressIdentity) { _, _ in retire() }
        .onChange(of: selection.reader.isCurrent) { _, valid in if !valid { retire() } }
    }
    private func start() {
        guard visible, scene == .active else { return }; retire()
        guard selection.reader.isCurrent else { return }
        let value = selection.reader.makeCoordinator(); flow = value; owner = value.beginDetail(selection.record); load(readIntent())
    }
    private func readIntent() -> (MemberReportProgressCoordinator, MemberReportProgressIntent)? {
        guard visible, scene == .active, let flow, let owner, let intent = flow.capture(owner) else { return nil }
        return (flow, intent)
    }
    private func load(_ read: (MemberReportProgressCoordinator, MemberReportProgressIntent)?) {
        guard let (original, intent) = read, original.accepts(intent) else { return }
        Task { await original.loadDetail(intent: intent) }
    }
    private func retire() { if let owner { flow?.end(owner) }; flow = nil; owner = nil }
}
