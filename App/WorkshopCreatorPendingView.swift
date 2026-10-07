import SwiftUI

@MainActor struct WorkshopCreatorPendingView: View {
    @Bindable var controller: WorkshopCreatorPendingController
    let appearance: WorkshopCreatorPendingAppearance
    @State private var task: Task<Void, Never>?
    @Environment(\.locale) private var locale
    private func creatorString(_ key: String) -> String { workshopCreatorLocalized(key, locale: locale) }
    @State private var declarationAppearance = WorkshopCreatorConsentAppearance()
    var body: some View {
        // Stable screen identity: an internal author → review branch switch is not Back.
        VStack(spacing: 0) {
            if controller.phase == .reviewing, let declaration = controller.declaration {
                VStack(spacing: 0) {
                    Button(creatorString("workshopPending.back")) {
                        declaration.close(declarationAppearance)
                        run(controller.offerBackToProposals(appearance))
                    }.accessibilityIdentifier("workshopPending.back")
                    WorkshopCreatorConsentView(controller: declaration, appearance: declarationAppearance, pendingDetail: controller.selectedDetail)
                        .id(declaration.identity)
                }
            } else {
                List {
                    Section {
                        Text(creatorString("workshopPending.boundary")).foregroundStyle(.secondary)
                        LabeledContent(creatorString("workshopCreator.source"), value: String(controller.sourceTemplateId))
                    }
                    if let receipt = controller.declarationReceipt {
                        Section(creatorString("workshopPending.priorDeclaration")) {
                            Text(creatorString("workshopPending.priorDeclarationScope"))
                            LabeledContent(creatorString("workshopCreator.package"), value: receipt.consentReference.moduleId)
                            LabeledContent(creatorString("workshopCreator.version"), value: receipt.consentReference.versionId)
                            LabeledContent(creatorString("workshopCreator.record"), value: receipt.consentReference.consentId)
                            Text(verbatim: receipt.declaredAt).font(.caption)
                        }.accessibilityIdentifier("workshopPending.declarationReceipt")
                    } else if let requestId = controller.declarationRequestId {
                        Section(creatorString("workshopPending.priorDeclaration")) {
                            Text(verbatim: requestId).textSelection(.enabled)
                            Text(creatorString("workshopCreator.unknown"))
                        }
                    }
                    if controller.phase == .loading || controller.phase == .submitting { ProgressView(creatorString("workshopCreator.loading")) }
                    if let issue = controller.issue { Text(creatorString(issueKey(issue))).accessibilityIdentifier("workshopPending.issue") }
                    if let pending = controller.pending {
                        Section(creatorString("workshopPending.saved")) {
                            Text(verbatim: pending.requestId).textSelection(.enabled)
                            Text(creatorString("workshopPending.recovery"))
                            // The exact saved text remains reviewable; edits cannot replace this attempt.
                            Text(verbatim: pending.termsDocument).textSelection(.enabled)
                            Button(creatorString("workshopPending.retry")) { run(controller.offerRetry(appearance)) }
                                .disabled(!controller.canRetry).accessibilityIdentifier("workshopPending.retry")
                        }
                    }
                    if let receipt = controller.receipt {
                        Section(creatorString("workshopPending.recorded")) {
                            Text(verbatim: receipt.targetId).textSelection(.enabled)
                            Text(creatorString("workshopPending.historic"))
                            Button(creatorString("workshopPending.another")) { run(controller.offerAnotherProposal(appearance)) }
                                .disabled(controller.phase == .submitting || controller.phase == .loading)
                                .accessibilityIdentifier("workshopPending.another")
                        }
                    }
                    if let preview = controller.preview {
                        Section(creatorString("workshopCreator.exactSource")) {
                            ForEach(WorkshopCreatorPreview.fieldOrder, id: \.self) { name in
                                if let value = preview.textFields[name] {
                                    VStack(alignment: .leading) {
                                        Text(creatorString("workshopCreator.field." + name)).font(.caption)
                                        Text(verbatim: value).textSelection(.enabled)
                                    }
                                }
                            }
                            Text(verbatim: preview.packageContentHash).font(.caption).textSelection(.enabled)
                        }
                        if !preview.omittedPlanningMetadata.isEmpty {
                            Section(creatorString("workshopCreator.omitted")) {
                                ForEach(preview.omittedPlanningMetadata, id: \.self) { field in Text(creatorString("workshopCreator.omitted." + field)) }
                            }
                        }
                        if controller.pending == nil { authorForm }
                        Section(creatorString("workshopPending.proposals")) {
                            if controller.items.isEmpty { Text(creatorString("workshopPending.empty")) }
                            ForEach(controller.items, id: \.targetId) { item in
                                Button {
                                    declarationAppearance = WorkshopCreatorConsentAppearance()
                                    run(controller.offerReview(item, appearance))
                                } label: {
                                    VStack(alignment: .leading) {
                                        Text(verbatim: item.versionId)
                                        Text(verbatim: item.termsDocumentHash).font(.caption)
                                        Text(verbatim: item.expiresAt).font(.caption)
                                    }
                                }.disabled(controller.phase != .editing)
                                    .accessibilityIdentifier("workshopPending.target." + item.targetId)
                            }
                            if controller.hasMore {
                                Button(creatorString("workshopPending.more")) { run(controller.offerMore(appearance)) }
                                    .disabled(controller.phase != .editing).accessibilityIdentifier("workshopPending.more")
                            }
                        }
                    }
                    Button(creatorString("workshopPending.refresh")) { run(controller.offerLoad(appearance)) }
                        .disabled(controller.phase == .loading || controller.phase == .submitting)
                        .accessibilityIdentifier("workshopPending.refresh")
                }
            }
        }.navigationTitle(creatorString("workshopPending.title")).navigationBarTitleDisplayMode(.inline)
            .privacySensitive().accessibilityIdentifier("workshopPending.form")
            .onAppear { run(controller.appear(appearance)) }
            .onDisappear { controller.close(appearance); task?.cancel(); task = nil }
    }
    @ViewBuilder private var authorForm: some View {
        Section(creatorString("workshopPending.terms")) {
            Text(creatorString("workshopPending.termsHelp"))
            TextEditor(text: $controller.form.termsDocument).frame(minHeight: 180)
                .accessibilityIdentifier("workshopPending.termsDocument")
        }.disabled(controller.phase != .editing)
        Section(creatorString("workshopPending.choices")) {
            option("commercialUse", value: $controller.form.commercialUse, values: ["ALLOWED", "PROHIBITED"])
            option("adaptation", value: $controller.form.adaptation, values: ["BIND_RESOURCES_ONLY", "LOCAL_ADAPTATION"])
            option("translation", value: $controller.form.translation, values: ["ALLOWED", "PROHIBITED"])
            field("allowedRegions", value: $controller.form.allowedRegions)
            field("buyerKinds", value: $controller.form.buyerKinds)
            Text(creatorString("workshopPending.regionsHelp")).font(.footnote)
            field("themeLimit", value: $controller.form.themeLimit)
            field("merchantLimit", value: $controller.form.merchantLimit)
            field("runLimit", value: $controller.form.runLimit)
            Text(creatorString("workshopPending.limitsHelp")).font(.footnote)
            field("priceMinor", value: $controller.form.priceMinor)
            field("currency", value: $controller.form.currency)
            Text(creatorString("workshopPending.priceHelp")).font(.footnote)
            field("expiresAt", value: $controller.form.expiresAt)
            Text(creatorString("workshopPending.expiryHelp")).font(.footnote)
        }.disabled(controller.phase != .editing)
        Section(creatorString("workshopPending.required")) {
            Text(creatorString("workshopPending.fixedRestrictions"))
            Text(creatorString("workshopPending.reviewRequired")).foregroundStyle(.secondary)
            Button(creatorString("workshopPending.author")) { run(controller.offerAuthor(appearance)) }
                .disabled(!controller.canSubmit).accessibilityIdentifier("workshopPending.author")
        }
    }
    private func field(_ key: String, value: Binding<String>) -> some View {
        TextField(creatorString("workshopPending." + key), text: value, axis: .vertical)
            .textInputAutocapitalization(.never).autocorrectionDisabled()
            .accessibilityIdentifier("workshopPending." + key)
    }
    private func option(_ key: String, value: Binding<String>, values: [String]) -> some View {
        Picker(creatorString("workshopPending." + key), selection: value) {
            Text(creatorString("workshopPending.choose")).tag("")
            ForEach(values, id: \.self) { value in Text(creatorString("workshopPending.option." + value)).tag(value) }
        }.accessibilityIdentifier("workshopPending." + key)
    }
    private func run(_ action: WorkshopCreatorPendingController.Action?) {
        guard let action else { return }; task?.cancel(); task = Task { await action() }
    }
    private func issueKey(_ issue: WorkshopCreatorConsentIssue) -> String {
        switch issue {
        case .storage: return "workshopCreator.storage"
        case .disabled: return "workshopCreator.unavailable"
        case .stale, .unauthorized: return "workshopCreator.changed"
        case .unknown, .pending: return "workshopPending.unknown"
        case .invalid: return "workshopPending.invalid"
        default: return "workshopCreator.failed"
        }
    }
}
