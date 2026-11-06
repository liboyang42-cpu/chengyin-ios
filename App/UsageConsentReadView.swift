import SwiftUI

private func usageEvidenceText(_ key: String) -> Text {
    Text(LocalizedStringKey(key), tableName: "UsageConsentEvidence")
}
private func usageEvidenceButton(_ key: String, action: @escaping () -> Void) -> some View {
    Button(action: action) { usageEvidenceText(key) }
}

@MainActor struct UsageConsentReadSettingsEntry: View {
    @ObservedObject var session: AppSession
    var body: some View {
        Section {
            NavigationLink {
                UsageConsentReadHost(session: session)
            } label: { Label { usageEvidenceText("usageEvidence.title") } icon: { Image(systemName: "doc.text.magnifyingglass") } }
                .accessibilityIdentifier("settings.usageConsentEvidence")
        }
    }
}
@MainActor private struct UsageConsentReadHost: View {
    @ObservedObject var session: AppSession
    @Environment(\.scenePhase) private var scenePhase
    @State private var coordinator: UsageConsentReadCoordinator?
    @State private var requestId = ""
    @State private var isVisible = false
    @State private var presentation: UsageConsentReadPresentation?
    var body: some View {
        let read = readIntent()
        List {
            Section { usageEvidenceText("usageEvidence.boundary").font(.footnote) }
            if let coordinator {
                Section {
                    TextField(text: $requestId) { usageEvidenceText("usageEvidence.request") }.textInputAutocapitalization(.never).autocorrectionDisabled()
                    usageEvidenceButton("usageEvidence.readOriginal") { requestOriginal(requestId, read: read) }
                        .disabled(coordinator.busy || !UsageConsentReadRoute.validKey(requestId))
                }
                if coordinator.busy { ProgressView() }
                if let failure = coordinator.failure { usageEvidenceText("usageEvidence.error.\(failure)") }
                if let detail = coordinator.detail {
                    UsageConsentOriginalSection(detail: detail)
                }
                Section(header: usageEvidenceText("usageEvidence.history")) {
                    if coordinator.loaded && coordinator.items.isEmpty { usageEvidenceText("usageEvidence.empty") }
                    ForEach(coordinator.items) { record in
                        Button {
                            requestOriginal(record.requestId, read: read)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(verbatim: "\(record.docType) · \(record.docVersion)")
                                usageEvidenceText("usageEvidence.event.\(record.eventType)")
                                Text(verbatim: record.requestId).font(.caption)
                            }
                        }.disabled(coordinator.busy)
                    }
                    if coordinator.nextBeforeId != nil {
                        usageEvidenceButton("usageEvidence.more") { requestReload(more: true, read: read) }.disabled(coordinator.busy)
                    }
                }
                usageEvidenceButton("usageEvidence.refresh") { requestReload(read: read) }.disabled(coordinator.busy)
            } else { usageEvidenceText("usageEvidence.unavailable") }
        }
        .navigationTitle(usageEvidenceText("usageEvidence.title"))
        .privacySensitive()
        .onAppear { isVisible = true; start() }
        .onDisappear { isVisible = false; retire() }
        .onChange(of: session.usageConsentReadIdentity) { _, _ in retire(); start() }
        .onChange(of: scenePhase) { _, phase in
            retire()
            if phase == .active { start() }
        }
        .refreshable {
            guard let (flow, intent) = read else { return }
            await flow.reload(intent: intent)
        }
    }
    private func start() {
        guard isVisible, scenePhase == .active else { return }
        retire()
        guard let value = session.makeUsageConsentReadCoordinator() else { return }
        coordinator = value; presentation = value.beginPresentation()
        requestReload(read: readIntent())
    }
    private func readIntent() -> (UsageConsentReadCoordinator, UsageConsentReadIntent)? {
        guard isVisible, scenePhase == .active, let coordinator, let presentation,
              let intent = coordinator.captureRead(presentation) else { return nil }
        return (coordinator, intent)
    }
    private func requestReload(more: Bool = false, read: (UsageConsentReadCoordinator, UsageConsentReadIntent)?) {
        guard let (flow, intent) = read, flow.isCurrent(intent) else { return }
        Task { await flow.reload(more: more, intent: intent) }
    }
    private func requestOriginal(_ key: String, read: (UsageConsentReadCoordinator, UsageConsentReadIntent)?) {
        guard let (flow, intent) = read, flow.isCurrent(intent) else { return }
        requestId = key
        // Use the rendered owner, then capture the exact key before the Task is queued.
        Task { await flow.read(key, intent: intent) }
    }
    private func retire() {
        if let presentation { coordinator?.endPresentation(presentation) }
        coordinator = nil; presentation = nil; requestId = ""
    }
}
private struct UsageConsentOriginalSection: View {
    let detail: UsageConsentOriginalEvidence
    var body: some View {
        Section(header: usageEvidenceText("usageEvidence.original")) {
            Text(verbatim: "\(detail.record.docType) · \(detail.record.docVersion)")
            Text(verbatim: detail.record.requestId).textSelection(.enabled)
            usageEvidenceText("usageEvidence.event.\(detail.record.eventType)")
            if let date = detail.record.displayDate {
                Text(date, format: .dateTime)
            } else { usageEvidenceText("usageEvidence.timeUnavailable") }
            usageEvidenceText(detail.latestRecordId == detail.record.id ? "usageEvidence.latest" : "usageEvidence.historical")
            usageEvidenceText("usageEvidence.source.\(detail.document.availability)")
            if let title = detail.document.title, let content = detail.document.content {
                Text(verbatim: title).font(.headline)
                Text(verbatim: content).textSelection(.enabled)
            }
            usageEvidenceText("usageEvidence.nativeBindingUnavailable").font(.footnote).foregroundStyle(.secondary)
        }
    }
}
