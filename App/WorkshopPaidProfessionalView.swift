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
    @State private var ownedTask: Task<Void, Never>?
    @State private var modeConfirmed = false
    @State private var cancelConfirmed = false
    @Environment(\.locale) private var locale
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
        .onAppear { schedule(controller.appear(displayed)) }
        .onDisappear { controller.close(displayed); ownedTask?.cancel() }
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
