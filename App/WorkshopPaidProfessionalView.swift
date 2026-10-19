import SwiftUI

typealias WorkshopPaidProfessionalControllerFactory = @MainActor (WorkshopPaidInstalledTextReference) -> WorkshopPaidProfessionalController?

/// The installed receipt owns this entry, independent of whether protected text can still be read.
@MainActor struct WorkshopPaidProfessionalEntry: View {
    let makeReference: @MainActor () -> WorkshopPaidInstalledTextReference?
    let makeController: WorkshopPaidProfessionalControllerFactory
    @State private var presentation: WorkshopPaidProfessionalPresentation
    init(makeReference: @escaping @MainActor () -> WorkshopPaidInstalledTextReference?, makeController: @escaping WorkshopPaidProfessionalControllerFactory,
         presentation: WorkshopPaidProfessionalPresentation? = nil) {
        self.makeReference = makeReference; self.makeController = makeController
        _presentation = State(initialValue: presentation ?? WorkshopPaidProfessionalPresentation())
    }
    private var presented: Binding<WorkshopPaidProfessionalPresentation.Selection?> {
        let expected = presentation.selection?.id
        return Binding(get: { presentation.selection?.id == expected ? presentation.selection : nil }, set: { presentation.replace($0, expected: expected) })
    }
    var body: some View {
        Button { presentation.open(makeReference: makeReference, makeController: makeController) } label: {
            Label { professionalText("entry") } icon: { Image(systemName: "doc.badge.gearshape") }
        }.accessibilityIdentifier("workshopPaidProfessional.entry")
        if presentation.unavailable { professionalText("notConfigured").font(.footnote) }
        Color.clear.frame(height: 0).sheet(item: presented) { captured in
            WorkshopPaidProfessionalView(controller: captured.controller, appearance: captured.appearance) { presentation.dismiss(captured) }.id(captured.id)
        }
    }
}
@MainActor struct WorkshopPaidProfessionalView: View {
    let controller: WorkshopPaidProfessionalController
    let appearance: WorkshopPaidProfessionalAppearance
    let onClose: () -> Void
    @Environment(\.workshopGeneratedTemplateReaderFactory) private var makeGeneratedTemplateReader
    @Environment(\.scenePhase) private var scenePhase
    @State private var ownedTask: Task<Void, Never>?
    @State private var generatedDetail: WorkshopGeneratedDetailSelection?
    @State private var modeConfirmed = false
    @State private var cancelConfirmed = false
    @Environment(\.locale) private var locale
    private var generatedPresentation: Binding<WorkshopGeneratedDetailSelection?> {
        let expected = generatedDetail?.id
        return Binding(get: { generatedDetail?.id == expected ? generatedDetail : nil }, set: { value in
            guard generatedDetail?.id == expected else { return }
            generatedDetail?.retire(); generatedDetail = value
        })
    }
    var body: some View {
        let displayed = appearance
        NavigationStack {
            Form {
                Section { professionalText("scope").fixedSize(horizontal: false, vertical: true) }
                if let issue = controller.issue {
                    Section { professionalText(issue == .disabled ? "notConfigured" : issue == .storageUnavailable || issue == .pendingConflict ? "storageBlocked" : "unavailable") }
                }
                switch controller.phase {
                case .idle: EmptyView()
                case .invalidated: professionalText("sessionChanged")
                case .loading: ProgressView { professionalText("loading") }
                case .submitting:
                    ProgressView { professionalText("submitting") }
                    professionalText("unknownNote")
                case .history: history(displayed)
                case .targets: targets(displayed)
                case .review: review(displayed)
                case .operation: operation(displayed)
                case .unavailable:
                    Button { schedule(controller.offerRecovery(displayed)) } label: { professionalText("retry") }
                }
            }
            .privacySensitive()
            .navigationTitle(String(localized: LocalizedStringResource("workshopPaidProfessional.title", table: "WorkshopPaidProfessional", locale: locale)))
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button { controller.close(displayed); ownedTask?.cancel(); onClose() } label: { professionalText("close") }
                    .accessibilityIdentifier("workshopPaidProfessional.close")
            } }
        }
        .sheet(item: generatedPresentation) { selection in
            WorkshopGeneratedDetailSheet(selection: selection, controller: controller, appearance: displayed)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { generatedDetail?.retire(); generatedDetail = nil }
        }
        .onChange(of: controller.generatedDetailRevision) { _, _ in
            generatedDetail?.retire(); generatedDetail = nil
        }
        .onChange(of: controller.operation) { _, value in
            if value != generatedDetail?.operation { generatedDetail?.retire(); generatedDetail = nil }
        }
        .onChange(of: controller.phase) { _, phase in
            if phase != .operation { generatedDetail?.retire(); generatedDetail = nil }
        }
        .onAppear { schedule(controller.appear(displayed)) }
        .onDisappear { generatedDetail?.retire(); generatedDetail = nil; controller.close(displayed); ownedTask?.cancel() }
        .onChange(of: controller.selectedTarget?.ownerModeFingerprint) { _, _ in modeConfirmed = false }
        .onChange(of: controller.command?.requestId) { _, _ in cancelConfirmed = false }
    }
    @ViewBuilder private func history(_ displayed: WorkshopPaidProfessionalAppearance) -> some View {
        Section {
            professionalText("historyScope")
            if controller.operations.isEmpty { professionalText("emptyHistory") }
            ForEach(controller.operations) { record in
                Button { schedule(controller.offerInspect(record, displayed: displayed)) } label: {
                    VStack(alignment: .leading) {
                        Text(verbatim: record.command.requestId)
                        Text(verbatim: "#\(record.command.targetTopicId) · \(record.command.purchasedVersionId)").font(.caption)
                        professionalText("mode." + record.command.confirmedMode.rawValue)
                    }
                }.accessibilityIdentifier("workshopPaidProfessional.history." + record.command.requestId)
            }
            if controller.nextOperationCursor != nil {
                Button { schedule(controller.offerMoreOperations(displayed)) } label: { professionalText("moreHistory") }
            }
        } header: { professionalText("history") }
        Section {
            Button { schedule(controller.offerNewReview(displayed)) } label: { professionalText("startReview") }
                .accessibilityIdentifier("workshopPaidProfessional.startReview")
            professionalText("reviewRequirements").font(.footnote)
        }
    }
    @ViewBuilder private func targets(_ displayed: WorkshopPaidProfessionalAppearance) -> some View {
        Section {
            if controller.targets.isEmpty { professionalText("noTargets") }
            ForEach(controller.targets) { target in
                Button { schedule(controller.offerSelect(target, displayed: displayed)) } label: {
                    VStack(alignment: .leading) {
                        Text(verbatim: target.name)
                        Text(verbatim: "#\(target.topicId)").font(.caption)
                        professionalText("mode." + target.mode.rawValue)
                    }
                }.disabled(target.mode == .unresolved)
                    .accessibilityIdentifier("workshopPaidProfessional.target.\(target.topicId)")
            }
            if controller.nextTargetCursor != nil {
                Button { schedule(controller.offerMoreTargets(displayed)) } label: { professionalText("moreTargets") }
            }
            professionalText("targetScope").font(.footnote)
            Button { schedule(controller.offerRecovery(displayed)) } label: { professionalText("cancelReview") }
        } header: { professionalText("chooseTarget") }
    }
    @ViewBuilder private func review(_ displayed: WorkshopPaidProfessionalAppearance) -> some View {
        if let target = controller.selectedTarget, let body = controller.body, let draft = controller.currentDraft {
            Section {
                fact("targetName", target.name); fact("targetID", String(target.topicId))
                professionalText("mode." + target.mode.rawValue)
                fact("fingerprint", target.ownerModeFingerprint)
                fact("draftRevision", String(draft.targetRevision)); fact("draftHash", draft.targetPayloadHash)
            } header: { professionalText("targetReview") }
            Section {
                fact("version", body.purchasedVersionID); fact("sourceHash", body.contentHash)
                fact("termsVersion", body.termsVersion); fact("termsHash", body.termsHash)
                ForEach(WorkshopPaidInstalledTextFields.names, id: \.self) { name in
                    if let value = body.sourceFields[name] {
                        DisclosureGroup { Text(verbatim: value).fixedSize(horizontal: false, vertical: true) } label: {
                            Text(LocalizedStringKey("workshopPaidInstalledText.field." + name), tableName: "WorkshopPaidInstalledText")
                        }
                    }
                }
                professionalText("verbatimFields").font(.footnote)
            } header: { professionalText("original") }
            Section {
                professionalText("creationLimits")
                Toggle(isOn: $modeConfirmed) { professionalText("confirmMode") }
                Button { schedule(controller.offerSubmit(displayed, confirmedMode: target.mode)) } label: { professionalText("confirmCreate") }
                    .disabled(!modeConfirmed)
                    .accessibilityIdentifier("workshopPaidProfessional.confirmCreate")
                Button { schedule(controller.offerRecovery(displayed)) } label: { professionalText("cancelReview") }
            }
        }
    }
    @ViewBuilder private func operation(_ displayed: WorkshopPaidProfessionalAppearance) -> some View {
        if let command = controller.command {
            Section {
                fact("request", command.requestId); fact("targetID", String(command.targetTopicId))
                professionalText("mode." + command.confirmedMode.rawValue)
                fact("version", command.purchasedVersionId)
                if let result = controller.operation {
                    professionalText("state." + result.state.rawValue)
                    if let reason = result.rejectionCode { fact("rejection", reason) }
                    if let creation = result.creation, let id = creation.templateId {
                        fact("templateID", String(id)); professionalText("historicalCreation")
                        if let hash = creation.templateContentHash { fact("templateHash", hash) }
                        Button {
                            guard let rawID = controller.generatedTemplateID(displayed, expected: result),
                                  let integerID = Int(exactly: rawID),
                                  let id = MemberPlayTemplateID(rawValue: integerID) else { return }
                            generatedDetail?.retire()
                            generatedDetail = WorkshopGeneratedDetailSelection(templateID: id, operation: result, reader: makeGeneratedTemplateReader?(), revision: controller.generatedDetailRevision)
                        } label: { Text("memberTemplate.title") }
                        .accessibilityIdentifier("workshopPaidProfessional.viewGeneratedTemplate")
                    }
                } else { professionalText("unknownNote") }
                Button { schedule(controller.offerRefreshStatus(displayed)) } label: { professionalText("checkStatus") }
                    .accessibilityIdentifier("workshopPaidProfessional.checkStatus")
                if controller.operation?.state.terminal == true {
                    Button { schedule(controller.offerAcknowledge(displayed)) } label: { professionalText("acknowledge") }
                } else {
                    professionalText("cancelMeaning")
                    Toggle(isOn: $cancelConfirmed) { professionalText("confirmCancel") }
                    Button { schedule(controller.offerCancelPending(displayed)) } label: { professionalText("cancelPending") }
                        .disabled(!cancelConfirmed)
                        .accessibilityIdentifier("workshopPaidProfessional.cancelPending")
                }
            } header: { professionalText("operation") }
        }
    }
    private func fact(_ key: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) { professionalText(key).font(.caption).foregroundStyle(.secondary); Text(verbatim: value) }.fixedSize(horizontal: false, vertical: true)
    }
    private func schedule(_ action: WorkshopPaidProfessionalController.Action?) {
        guard let action else { return }; ownedTask?.cancel(); ownedTask = Task { await action() }
    }
}
private func professionalText(_ key: String) -> Text { Text(LocalizedStringKey("workshopPaidProfessional." + key), tableName: "WorkshopPaidProfessional") }


/// A visit owns only a historical identifier; current ownership is always fetched separately.
@MainActor final class WorkshopGeneratedDetailSelection: Identifiable {
    let id = UUID()
    let templateID: MemberPlayTemplateID
    let operation: WorkshopPaidProfessionalOperation
    let reader: OwnedMemberTemplateReader?
    let revision: UUID
    private(set) var live = true
    init(templateID: MemberPlayTemplateID, operation: WorkshopPaidProfessionalOperation, reader: OwnedMemberTemplateReader? = nil, revision: UUID = UUID()) {
        self.templateID = templateID; self.operation = operation; self.reader = reader; self.revision = revision
    }
    func retire() { live = false }
}
@MainActor struct WorkshopGeneratedDetailSheet: View {
    let selection: WorkshopGeneratedDetailSelection
    let controller: WorkshopPaidProfessionalController
    let appearance: WorkshopPaidProfessionalAppearance
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Group {
            if let reader = selection.reader {
            MemberTemplateDetailView(id: selection.templateID,
                reader: WorkshopGeneratedTemplateReader(base: reader) {
                    selection.live && selection.revision == controller.generatedDetailRevision && controller.generatedTemplateID(appearance, expected: selection.operation) == Int64(selection.templateID.rawValue)
                })
                .id(selection.id)
                .toolbar { ToolbarItem(placement: .primaryAction) {
                    NavigationLink {
                        OwnedTemplateConfigurationView(
                            host: reader.configurationHost(id: selection.templateID, acceptsResult: isCurrentReceipt),
                            id: selection.templateID)
                            .id(selection.id)
                    } label: { Text("templateOwnerConfig.open") }
                        .disabled(!isCurrentReceipt() || !reader.isConfigured)
                        .accessibilityIdentifier("workshopPaidProfessional.generatedDetail.configuration")
                } }
            } else { Text("memberTemplate.notConfigured") }
            }
                .toolbar { ToolbarItem(placement: .cancellationAction) {
                    Button("action.close") { selection.retire(); dismiss() }
                        .accessibilityIdentifier("workshopPaidProfessional.generatedDetail.close")
                } }
        }.onDisappear { selection.retire() }
    }
    private func isCurrentReceipt() -> Bool {
        selection.live && selection.revision == controller.generatedDetailRevision
            && controller.generatedTemplateID(appearance, expected: selection.operation) == Int64(selection.templateID.rawValue)
    }
}
/// Read-only adapter: the base owns the independent read approval and verifies both template ID
/// and member ID. The extra fence prevents a stale receipt or dismissed visit from disclosing it.
@MainActor final class WorkshopGeneratedTemplateReader: MemberTemplateReading {
    let base: OwnedMemberTemplateReader
    let current: () -> Bool
    init(base: OwnedMemberTemplateReader, current: @escaping () -> Bool) { self.base = base; self.current = current }
    var scope: UUID { base.scope }
    var isAuthenticated: Bool { base.isAuthenticated }
    var isConfigured: Bool { current() && base.isConfigured }
    func memberTemplate(id: MemberPlayTemplateID) async throws -> MemberTemplateDetail {
        guard current() else { throw APIError.notConfigured }
        let value = try await base.memberTemplate(id: id, acceptsResult: current)
        guard !Task.isCancelled, current(), value.id == id else { throw CancellationError() }
        return value
    }
}

/// Optional injection keeps standalone screens and fixtures safe and unconfigured by default.
/// The normal account entry supplies only the independently authorized owned-template reader.
typealias WorkshopGeneratedTemplateReaderFactory = @MainActor @Sendable () -> OwnedMemberTemplateReader?
private struct WorkshopGeneratedTemplateReaderFactoryKey: EnvironmentKey {
    static let defaultValue: WorkshopGeneratedTemplateReaderFactory? = nil
}
extension EnvironmentValues {
    var workshopGeneratedTemplateReaderFactory: WorkshopGeneratedTemplateReaderFactory? {
        get { self[WorkshopGeneratedTemplateReaderFactoryKey.self] }
        set { self[WorkshopGeneratedTemplateReaderFactoryKey.self] = newValue }
    }
}
