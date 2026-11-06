import SwiftUI

/// A presentation of the original journal only. No preparation or publication API is exposed.
@MainActor final class ApprovedReleaseOriginalRecovery: ObservableObject {
    struct Opening {
        let session: ProjectEditSession
        let incarnation: UUID
        let identity: ProjectEditDraftIdentity
        let snapshot: ProjectEditSnapshot
        let acknowledged: ProjectEditPending?
        let topicID: Int
        fileprivate let source: any ApprovedTopicReleasePublishing
        fileprivate let journal: ApprovedTopicReleasePublicationJournal
        init(session: ProjectEditSession, incarnation: UUID, identity: ProjectEditDraftIdentity, snapshot: ProjectEditSnapshot,
             acknowledged: ProjectEditPending?, topicID: Int, source: any ApprovedTopicReleasePublishing,
             journal: ApprovedTopicReleasePublicationJournal) {
            self.session = session; self.incarnation = incarnation; self.identity = identity; self.snapshot = snapshot
            self.acknowledged = acknowledged; self.topicID = topicID; self.source = source; self.journal = journal
        }
    }
    struct Presentation: Identifiable {
        let id = UUID()
        let opening: Opening
        let reader: Reader
        fileprivate let readerToken: UUID
    }
    /// Keep the Core flow private so a recovery consumer cannot obtain write controls.
    @MainActor final class Reader: ObservableObject {
        enum StorageIssue: Equatable { case unreadable, damaged, changed }
        private let flow: ApprovedTopicReleasePublishFlow
        private let opening: Opening
        @Published private(set) var loaded = false
        @Published private(set) var checking = false
        @Published private(set) var storageIssue: StorageIssue?
        @Published private(set) var revision = 0
        fileprivate init(opening: Opening, current: @escaping () -> Bool) {
            self.opening = opening
            flow = .init(session: opening.session, topicID: opening.topicID, source: opening.source,
                         journal: opening.journal, stillCurrent: current)
        }
        var isCurrent: Bool { flow.isCurrent }
        var state: ApprovedTopicReleasePublishFlow.State { flow.state }
        var snapshot: ApprovedTopicReleasePublicationJournal.Snapshot? { isCurrent ? flow.snapshot : nil }
        var lastStatusCheckFailed: Bool { flow.lastStatusCheckFailed }
        var canCheckStatus: Bool { !checking && flow.state != .unavailable && flow.canCheckStatus }
        var inspectedResult: ApprovedTopicReleasePublishFlow.ResultInspection? { flow.inspectedResult }
        func reload() {
            guard flow.isCurrent, !checking, flow.inspectedResult == nil else { return }
            flow.reload(); loaded = true; storageIssue = nil
            if flow.state == .unavailable, flow.isCurrent {
                // Core intentionally folds storage errors into unavailable. This local-only diagnostic
                // uses the existing journal decoder, without copying its schema or clearing bytes.
                do { _ = try opening.journal.read(session: opening.session, topicID: opening.topicID); storageIssue = .changed }
                catch {
                    guard flow.isCurrent else { close(); return }
                    storageIssue = error is DecodingError || error as? ApprovedTopicReleaseError == .invalidResponse ? .damaged : .unreadable
                }
            }
            revision += 1
        }
        func checkStatus(_ original: ApprovedTopicReleasePublicationJournal.Snapshot) async {
            guard canCheckStatus else { return }
            checking = true
            defer { checking = false; revision += 1 }
            await flow.checkStatus(original)
        }
        func inspect(_ record: ApprovedTopicReleasePublicationJournal.Record) { _ = flow.inspect(record); revision += 1 }
        func isInspecting(_ original: ApprovedTopicReleasePublishFlow.ResultInspection) -> Bool { flow.isInspecting(original) }
        func dismiss(_ original: ApprovedTopicReleasePublishFlow.ResultInspection) { flow.dismiss(original); revision += 1 }
        func resultBinding(_ original: ApprovedTopicReleasePublishFlow.ResultInspection?) -> Binding<ApprovedTopicReleasePublishFlow.ResultInspection?> {
            Binding(get: { guard let original, self.isInspecting(original) else { return nil }; return original },
                    set: { value in guard value == nil, let original else { return }; self.dismiss(original) })
        }
        func close() { flow.close(); checking = false; revision += 1 }
    }
    private let model: ProjectEditModel
    private var active = true
    @Published private(set) var presentation: Presentation?
    init(model: ProjectEditModel) { self.model = model }
    private func target() -> (ProjectEditSession, ProjectEditDraftIdentity, ProjectEditSnapshot, ProjectEditPending?, Int)? {
        let coordinator = model.coordinator
        guard active, model.ownsVisit, !model.busy, !coordinator.isBusy,
              coordinator.state != .blocked, coordinator.state != .simulated,
              let session = coordinator.session, let identity = coordinator.identity,
              let snapshot = coordinator.snapshot, snapshot.draft.owner == .personal else { return nil }
        if let topicID = snapshot.topicID {
            guard topicID > 0, identity.topicID == topicID else { return nil }
            return (session, identity, snapshot, nil, topicID)
        }
        // A newly created topic has no accepted remote snapshot yet. Use only the original strict ACK.
        guard let pending = coordinator.pending, model.submissionEvidence?.operationID == pending.operationID,
              pending.ownerKey == session.ownerKey, pending.identity == identity, pending.hasConsistentAcknowledgment,
              pending.serverAcknowledged == true, let topicID = pending.completedTopicID, topicID > 0,
              identity.topicID == nil || identity.topicID == topicID,
              pending.baseline?.draft.owner == .personal else { return nil }
        return (session, identity, snapshot, pending, topicID)
    }
    func capture() -> Opening? {
        guard presentation == nil, let (session, identity, snapshot, acknowledged, topicID) = target(),
              let source = model.coordinator.releasePublicationSource,
              let journal = model.coordinator.releasePublicationJournal,
              source.isCurrent(session: session), source.canCheckStatus(session: session) else { return nil }
        return .init(session: session, incarnation: model.editorIncarnation, identity: identity, snapshot: snapshot,
                     acknowledged: acknowledged, topicID: topicID, source: source, journal: journal)
    }
    func isCurrent(_ opening: Opening) -> Bool {
        guard model.editorIncarnation == opening.incarnation,
              let (session, identity, snapshot, acknowledged, topicID) = target(),
              session == opening.session, session.storageNamespace.utf8.elementsEqual(opening.session.storageNamespace.utf8),
              identity == opening.identity, snapshot == opening.snapshot, topicID == opening.topicID,
              let source = model.coordinator.releasePublicationSource, source === opening.source,
              model.coordinator.releasePublicationJournal === opening.journal,
              source.isCurrent(session: session), source.canCheckStatus(session: session) else { return false }
        switch (acknowledged, opening.acknowledged) {
        case (nil, nil): return true
        case (let current?, let original?): return ProjectEditLocalStore.exactPending(current, original)
        default: return false
        }
    }
    func open(_ opening: Opening) {
        guard presentation == nil, isCurrent(opening) else { return }
        let id = UUID()
        let reader = Reader(opening: opening, current: { [weak self] in
            self?.presentation?.readerToken == id && self?.isCurrent(opening) == true
        })
        presentation = Presentation(opening: opening, reader: reader, readerToken: id)
    }
    func isPresented(_ original: Presentation) -> Bool {
        presentation?.id == original.id && isCurrent(original.opening) && original.reader.isCurrent
    }
    func close(_ original: Presentation) {
        original.reader.close()
        guard presentation?.id == original.id else { return }; presentation = nil
    }
    func setActive(_ value: Bool) { active = value; if !value { retire() } }
    func retire() { if let original = presentation { close(original) } }
    func binding(_ original: Presentation?) -> Binding<Presentation?> {
        Binding(get: { guard let original, self.isPresented(original) else { return nil }; return original },
                set: { value in guard value == nil, let original else { return }; self.close(original) })
    }
}

/// One catalog and the App locale for every recovery-only string.
enum ApprovedReleaseOriginalRecoveryText: String, CaseIterable {
    case title, open, unavailable, loading, empty, storageUnavailable, storageUnreadable, storageDamaged, scope, unknown, known, approved, changed
    case failed, check, checking, inspect, latest, history, reload, close, releaseID, requestID, manifest
    func value(locale: Locale) -> String {
        String(localized: LocalizedStringResource(String.LocalizationValue(stringLiteral: "recovery." + rawValue),
            table: "ApprovedReleaseOriginalRecovery", locale: locale))
    }
}

@MainActor struct ApprovedReleaseOriginalRecoverySection: View {
    @ObservedObject var model: ProjectEditModel
    @StateObject private var controller: ApprovedReleaseOriginalRecovery
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    init(model: ProjectEditModel) { self.model = model; _controller = StateObject(wrappedValue: .init(model: model)) }
    var body: some View {
        let opening = controller.capture()
        let original = controller.presentation
        Section {
            Button(ApprovedReleaseOriginalRecoveryText.open.value(locale: locale)) {
                guard scenePhase == .active, let opening else { return }; controller.open(opening)
            }.buttonStyle(.borderless).disabled(opening == nil || scenePhase != .active)
                .accessibilityIdentifier("approvedRelease.recovery.open")
            if opening == nil, original.map({ controller.isPresented($0) }) != true {
                Text(ApprovedReleaseOriginalRecoveryText.unavailable.value(locale: locale))
                    .font(.footnote).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("approvedRelease.recovery.unavailable")
            }
        }
        .sheet(item: controller.binding(original)) { captured in
            ApprovedReleaseOriginalRecoveryView(original: captured, close: { controller.close(captured) })
        }
        .onChange(of: original.map { controller.isPresented($0) }) { _, current in
            if current == false, let original { controller.close(original) }
        }
        .onChange(of: model.editorIncarnation) { _, _ in controller.retire() }
        .onChange(of: model.coordinator.session) { _, _ in controller.retire() }
        .onChange(of: scenePhase) { _, phase in controller.setActive(phase == .active) }
        .onAppear { controller.setActive(scenePhase == .active) }
        // Covering this section with its own sheet does not retire the hosting reader.
    }
}

@MainActor private struct ApprovedReleaseOriginalRecoveryView: View {
    let original: ApprovedReleaseOriginalRecovery.Presentation
    let close: () -> Void
    @ObservedObject private var reader: ApprovedReleaseOriginalRecovery.Reader
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    init(original: ApprovedReleaseOriginalRecovery.Presentation, close: @escaping () -> Void) {
        self.original = original; self.close = close; _reader = ObservedObject(wrappedValue: original.reader)
    }
    private func text(_ key: ApprovedReleaseOriginalRecoveryText) -> String { key.value(locale: locale) }
    var body: some View {
        let inspection = reader.inspectedResult
        NavigationStack {
            Form {
                Section { Text(text(.scope)).fixedSize(horizontal: false, vertical: true) }
                if !reader.isCurrent {
                    Section { Text(text(.unavailable)).accessibilityIdentifier("approvedRelease.recovery.denied") }
                } else if !reader.loaded {
                    Section { ProgressView(text(.loading)).accessibilityIdentifier("approvedRelease.recovery.loading") }
                } else if reader.state == .unavailable {
                    Section {
                        Text(text(reader.storageIssue == .damaged ? .storageDamaged : reader.storageIssue == .unreadable ? .storageUnreadable : .storageUnavailable))
                            .accessibilityIdentifier("approvedRelease.recovery.storageUnavailable")
                        Button(text(.reload)) { reader.reload() }.buttonStyle(.borderless)
                    }
                } else {
                    records
                }
            }
            .navigationTitle(text(.title))
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button(text(.close), action: close).accessibilityIdentifier("approvedRelease.recovery.close")
            } }
        }
        .task(id: original.id) { reader.reload() }
        .sheet(item: reader.resultBinding(inspection)) { captured in
            // The existing result view uses the saved summary and never loads current preparation/media.
            if reader.isInspecting(captured) {
                ApprovedReleaseSummaryResultView(original: captured, close: reader.dismiss)
            }
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { close() } }
        // No onDisappear close: inspecting a saved result may cover this sheet.
    }
    @ViewBuilder private var records: some View {
        if let snapshot = reader.snapshot, let current = snapshot.current {
            Section(text(.latest)) {
                if reader.checking { ProgressView(text(.checking)) }
                if let receipt = current.receipt {
                    Text(text(.known)).accessibilityIdentifier("approvedRelease.recovery.known")
                    field(.releaseID, String(receipt.releaseID))
                    field(.manifest, receipt.manifestHash)
                    Text(text(receipt.currentlyApproved ? .approved : .changed))
                } else {
                    Text(text(.unknown)).accessibilityIdentifier("approvedRelease.recovery.unknown")
                }
                if reader.lastStatusCheckFailed {
                    Text(text(.failed)).accessibilityIdentifier("approvedRelease.recovery.refreshFailed")
                }
                field(.requestID, current.command.requestID)
                Button(text(.check)) { Task { await reader.checkStatus(snapshot) } }
                    .buttonStyle(.borderless).disabled(!reader.canCheckStatus || scenePhase != .active)
                    .accessibilityIdentifier("approvedRelease.recovery.check")
            }
            Section(text(.history)) {
                ForEach(snapshot.records.reversed(), id: \.command.requestID) { record in
                    Button { reader.inspect(record) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(verbatim: record.prepared.name ?? String(record.prepared.topicID))
                            Text(verbatim: record.command.requestID).font(.caption)
                            Text(text(record.receipt == nil ? .unknown : .known)).font(.footnote)
                            Text(text(.inspect)).font(.footnote)
                        }.fixedSize(horizontal: false, vertical: true)
                    }.buttonStyle(.borderless).disabled(reader.checking || scenePhase != .active)
                        .accessibilityIdentifier("approvedRelease.recovery.inspect.\(record.command.requestID)")
                }
            }
        } else {
            Section { Text(text(.empty)).accessibilityIdentifier("approvedRelease.recovery.empty") }
        }
    }
    private func field(_ key: ApprovedReleaseOriginalRecoveryText, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(text(key)).font(.caption).foregroundStyle(.secondary)
            Text(verbatim: value).textSelection(.enabled)
        }.fixedSize(horizontal: false, vertical: true)
    }
}
