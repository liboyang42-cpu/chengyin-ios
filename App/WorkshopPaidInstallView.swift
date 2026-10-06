import SwiftUI

typealias WorkshopPaidInstallControllerFactory = @MainActor (WorkshopPurchasedItem) -> WorkshopPaidInstallController?

/// Real purchased-detail entry. A separate nil-by-default factory cannot borrow metadata approval.
@MainActor struct WorkshopPaidInstallEntry: View {
    let item: WorkshopPurchasedItem
    let makeController: WorkshopPaidInstallControllerFactory
    var makeProfessional: WorkshopPaidProfessionalControllerFactory = { _ in nil }
    var makeText: WorkshopPaidInstalledTextControllerFactory = { _ in nil }
    @State private var unavailable = false
    @State private var selection: Selection?
    @MainActor private struct Selection: Identifiable {
        let id = UUID()
        let controller: WorkshopPaidInstallController
        let appearance = WorkshopPaidInstallAppearance()
    }
    private var presented: Binding<Selection?> {
        let expected = selection?.id
        return Binding(get: { selection?.id == expected ? selection : nil }, set: { replacement in
            guard selection?.id == expected else { return }
            if let previous = selection, previous.id != replacement?.id { previous.controller.close(previous.appearance) }
            selection = replacement
        })
    }
    var body: some View {
        Section {
            Button {
                guard selection == nil else { return }
                guard let controller = makeController(item) else { unavailable = true; return }
                unavailable = false; selection = Selection(controller: controller)
            } label: { Label { installText("entry") } icon: { Image(systemName: "square.and.arrow.down") } }
                .accessibilityIdentifier("workshopPaidInstall.entry")
            installText(unavailable ? "notConfigured" : "entryScope").font(.footnote).fixedSize(horizontal: false, vertical: true)
        }
        .sheet(item: presented) { captured in
            WorkshopPaidInstallView(controller: captured.controller, appearance: captured.appearance, makeProfessional: makeProfessional, makeText: makeText) {
                guard selection?.id == captured.id else { return }; presented.wrappedValue = nil
            }.id(captured.id)
        }
    }
}
@MainActor struct WorkshopPaidInstallView: View {
    let controller: WorkshopPaidInstallController
    let appearance: WorkshopPaidInstallAppearance
    var makeProfessional: WorkshopPaidProfessionalControllerFactory = { _ in nil }
    var makeText: WorkshopPaidInstalledTextControllerFactory = { _ in nil }
    let onClose: () -> Void
    @State private var ownedTask: Task<Void, Never>?
    @Environment(\.locale) private var locale
    var body: some View {
        let displayed = appearance
        NavigationStack {
            Form {
                Section { installText("scope").fixedSize(horizontal: false, vertical: true) }
                if controller.phase == .invalidated {
                    installText("sessionChanged")
                } else if controller.phase == .submitting {
                    ProgressView { installText("submitting") }
                    installText("unknownNote").fixedSize(horizontal: false, vertical: true)
                } else if controller.phase == .loading {
                    ProgressView { installText("loading") }
                } else if controller.phase == .confirming, let command = controller.confirmation {
                    commandFacts(command)
                    Section {
                        installText("confirmNote").fixedSize(horizontal: false, vertical: true)
                        Button { schedule(controller.offerSubmit(displayed, command: command)) } label: { installText("confirm") }
                            .accessibilityIdentifier("workshopPaidInstall.confirm")
                        Button(role: .cancel) { controller.cancelReview(appearance: displayed) } label: { installText("cancelReview") }
                    }
                } else {
                    if let issue = controller.issue {
                        Section {
                            installText(issue == .storageUnavailable || issue == .pendingConflict ? "storageBlocked" : issue == .disabled ? "notConfigured" : "readOrOutcomeUnavailable")
                                .fixedSize(horizontal: false, vertical: true)
                            Button { schedule(controller.offerLoad(displayed)) } label: { installText("refresh") }
                        }
                    }
                    if let pending = controller.pending {
                        Section {
                            InstallFact("request", pending.requestId)
                            installText("unknownNote").fixedSize(horizontal: false, vertical: true)
                            if let outcome = controller.outcome { installText("state." + outcome.state.rawValue) }
                            Button { schedule(controller.offerStatus(displayed)) } label: { installText("checkOutcome") }
                            Button { controller.reviewRecovery(appearance: displayed) } label: { installText("reviewSameRequest") }
                        } header: { installText("pending") }
                    } else if controller.phase != .failed {
                        targetSelection(displayed)
                    }
                    if let outcome = controller.outcome, outcome.state == .installed {
                        Section {
                            installText("installed").font(.headline)
                            if let id = outcome.ownedDraftId { InstallFact("ownedDraft", String(id)) }
                            if let at = outcome.installedAt { InstallFact("installedAt", at) }
                            installText("materializationRequired").fixedSize(horizontal: false, vertical: true)
                            WorkshopPaidInstalledTextEntry(makeReference: { controller.installedTextReference(outcome, appearance: displayed) }, makeController: makeText)
                            WorkshopPaidProfessionalEntry(makeReference: { controller.installedTextReference(outcome, appearance: displayed) }, makeController: makeProfessional)
                        } header: { installText("result") }
                    }
                    Section {
                        if controller.history.isEmpty { installText("noHistory") }
                        ForEach(controller.history) { receipt in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(verbatim: receipt.requestId).font(.caption)
                                installText("state." + receipt.state.rawValue)
                                if let command = receipt.command {
                                    Text(verbatim: command.purchasedVersionId)
                                    InstallFact("target", String(command.targetDraftId))
                                }
                                if receipt.state == .installed {
                                    WorkshopPaidInstalledTextEntry(makeReference: { controller.installedTextReference(receipt, appearance: displayed) }, makeController: makeText)
                                    WorkshopPaidProfessionalEntry(makeReference: { controller.installedTextReference(receipt, appearance: displayed) }, makeController: makeProfessional)
                                }
                                if !receipt.state.terminal {
                                    Button { controller.reviewRecovery(receipt, appearance: displayed) } label: { installText("reviewSameRequest") }
                                        .disabled(controller.pending != nil && controller.pending?.id != receipt.id)
                                }
                            }
                        }
                        if let cursor = controller.nextHistoryCursor {
                            Button { schedule(controller.offerLoad(displayed, beforeHistory: cursor)) } label: { installText("moreHistory") }
                        }
                    } header: { installText("history") }
                }
            }
            .privacySensitive()
            .navigationTitle(String(localized: LocalizedStringResource("workshopPaidInstall.title", table: "WorkshopPaidInstall", locale: locale)))
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button { controller.close(displayed); ownedTask?.cancel(); onClose() } label: { installText("close") }
                    .accessibilityIdentifier("workshopPaidInstall.close")
            } }
        }
        .onAppear { schedule(controller.appear(displayed)) }
        .onDisappear { controller.close(displayed); ownedTask?.cancel() }
    }
    @ViewBuilder private func targetSelection(_ displayed: WorkshopPaidInstallAppearance) -> some View {
        Section {
            if controller.item.status != .active { installText("inactive") }
            else if controller.targetIssue != nil { installText("targetsUnavailable") }
            else if controller.targets.isEmpty { installText("noTargets") }
            else {
                Picker(selection: Binding<Int64?>(get: { controller.target?.id }, set: { id in
                    controller.select(controller.targets.first(where: { $0.id == id }), appearance: displayed)
                })) {
                    installText("chooseTarget").tag(Int64?.none)
                    ForEach(controller.targets) { target in
                        Text(verbatim: "\(target.businessType) #\(target.id) · v\(target.targetRevision)").tag(Optional(target.id))
                    }
                } label: { installText("target") }
                if let target = controller.target {
                    InstallFact("targetHash", target.targetPayloadHash)
                    installText("unresolvedMode").fixedSize(horizontal: false, vertical: true)
                    Picker(selection: Binding<String?>(get: { controller.region }, set: { controller.chooseRegion($0, appearance: displayed) })) {
                        installText("chooseRegion").tag(String?.none)
                        ForEach(controller.item.allowedRegions, id: \.self) { region in Text(verbatim: region).tag(Optional(region)) }
                    } label: { installText("region") }
                    installText("regionPlanningOnly").font(.footnote)
                    Toggle(isOn: Binding(get: { controller.commercialUse }, set: { controller.chooseCommercialUse($0, appearance: displayed) })) { installText("commercial") }
                        .disabled(controller.item.commercialUse != .allowed)
                    Button { controller.review(appearance: displayed) } label: { installText("review") }
                        .disabled(controller.region == nil)
                        .accessibilityIdentifier("workshopPaidInstall.review")
                }
                if let cursor = controller.nextTargetCursor {
                    Button { schedule(controller.offerLoad(displayed, beforeTarget: cursor)) } label: { installText("moreTargets") }
                }
            }
        } header: { installText("targets") }
    }
    @ViewBuilder private func commandFacts(_ command: WorkshopPaidInstallCommand) -> some View {
        Section {
            InstallFact("request", command.requestId); InstallFact("license", command.licenseId)
            InstallFact("version", command.purchasedVersionId); InstallFact("sourceHash", command.contentHash)
            InstallFact("termsHash", command.termsHash); InstallFact("target", String(command.targetDraftId))
            InstallFact("targetRevision", String(command.targetRevision)); InstallFact("businessType", command.businessType)
            InstallFact("targetHash", command.targetPayloadHash); InstallFact("region", command.planningRegion)
            installText(command.commercialUse ? "commercialYes" : "commercialNo")
            installText("unresolvedMode").fixedSize(horizontal: false, vertical: true)
        } header: { installText("confirmation") }
    }
    private func schedule(_ action: WorkshopPaidInstallController.Action?) {
        guard let action else { return }; ownedTask?.cancel(); ownedTask = Task { await action() }
    }
}
private struct InstallFact: View {
    let key: String, value: String
    init(_ key: String, _ value: String) { self.key = key; self.value = value }
    var body: some View { VStack(alignment: .leading, spacing: 4) { installText(key).font(.caption).foregroundStyle(.secondary); Text(verbatim: value) }.fixedSize(horizontal: false, vertical: true) }
}
private func installText(_ key: String) -> Text { Text(LocalizedStringKey("workshopPaidInstall." + key), tableName: "WorkshopPaidInstall") }
