import SwiftUI

/// Issued by the live owned-CMS row. A later navigation appearance cannot revive an old action.
@MainActor struct WorkshopCreatorConsentSelection: Identifiable, Hashable {
    let id = UUID()
    let source: MemberPlayTemplateID
    let appearance = WorkshopCreatorConsentAppearance()
    let pendingAppearance = WorkshopCreatorPendingAppearance()
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    nonisolated func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
@MainActor struct SessionWorkshopCreatorConsentView: View {
    let selection: WorkshopCreatorConsentSelection
    @EnvironmentObject private var session: AppSession
    @Environment(\.locale) private var locale
    private func creatorString(_ key: String) -> String { workshopCreatorLocalized(key, locale: locale) }
    var body: some View {
        Group {
            if let controller = session.makeWorkshopCreatorPendingController(sourceTemplateId: Int64(selection.source.rawValue)) {
                WorkshopCreatorPendingView(controller: controller, appearance: selection.pendingAppearance)
                    .id(controller.identity)
            } else {
                List {
                    Text(creatorString("workshopCreator.unavailable"))
                    Text(creatorString("workshopCreator.boundary")).foregroundStyle(.secondary)
                }.navigationTitle(creatorString("workshopCreator.title")).accessibilityIdentifier("workshopCreator.unavailable")
            }
        }.privacySensitive()
    }
}
@MainActor struct WorkshopCreatorConsentView: View {
    let controller: WorkshopCreatorConsentController
    let appearance: WorkshopCreatorConsentAppearance
    var pendingDetail: WorkshopCreatorPendingDetail? = nil
    @State private var task: Task<Void, Never>?
    @Environment(\.locale) private var locale
    private func creatorString(_ key: String) -> String { workshopCreatorLocalized(key, locale: locale) }
    var body: some View {
        List {
            Section {
                Text(creatorString("workshopCreator.boundary")).foregroundStyle(.secondary)
                LabeledContent(creatorString("workshopCreator.source"), value: String(controller.sourceTemplateId))
            }
            if controller.phase == .loading || controller.phase == .submitting { ProgressView(creatorString("workshopCreator.loading")) }
            if let issue = controller.issue { Text(creatorString(issueKey(issue))).accessibilityIdentifier("workshopCreator.issue") }
            if let pending = controller.pending {
                Section(creatorString("workshopCreator.request")) { Text(verbatim: pending.requestId).font(.caption).textSelection(.enabled) }
            }
            if let preview = controller.preview {
                Section(creatorString("workshopCreator.exactSource")) {
                    Text(creatorString("workshopCreator.textOnly")).font(.footnote)
                    ForEach(WorkshopCreatorPreview.fieldOrder, id: \.self) { field in
                        if let value = preview.textFields[field] {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(creatorString("workshopCreator.field." + field)).font(.caption).foregroundStyle(.secondary)
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
                Section(creatorString("workshopCreator.selectVersion")) {
                    if controller.targets.isEmpty { Text(creatorString("workshopCreator.noTarget")) }
                    ForEach(controller.targets) { target in
                        Button {
                            controller.select(target, appearance: appearance)
                        } label: {
                            HStack {
                                VStack(alignment: .leading) { Text(verbatim: target.moduleId); Text(verbatim: target.versionId).font(.caption) }
                                Spacer()
                                if controller.selected?.id == target.id { Image(systemName: "checkmark.circle.fill") }
                            }
                        }.disabled(controller.phase != .reviewing).accessibilityIdentifier("workshopCreator.target.\(target.id.uuidString)")
                    }
                }
                if let target = controller.selected {
                    Section(creatorString("workshopCreator.fullTerms")) {
                        LabeledContent(creatorString("workshopCreator.offerVersion"), value: target.offerVersion)
                        LabeledContent(creatorString("workshopCreator.termsVersion"), value: target.termsVersion)
                        Text(verbatim: target.termsDocument).textSelection(.enabled)
                        Text(verbatim: target.termsDocumentHash).font(.caption).textSelection(.enabled)
                    }
                    if let detail = pendingDetail {
                        Section(creatorString("workshopPending.choices")) {
                            LabeledContent(creatorString("workshopPending.priceMinor"), value: String(detail.proposedOffer.priceMinor))
                            LabeledContent(creatorString("workshopPending.currency"), value: detail.proposedOffer.currency)
                            LabeledContent(creatorString("workshopPending.buyerKinds"), value: detail.proposedOffer.buyerKinds.joined(separator: ","))
                            LabeledContent(creatorString("workshopPending.allowedRegions"), value: detail.proposedOffer.terms.allowedRegions.joined(separator: ","))
                            LabeledContent(creatorString("workshopPending.commercialUse"), value: detail.proposedOffer.terms.commercialUse)
                            LabeledContent(creatorString("workshopPending.adaptation"), value: detail.proposedOffer.terms.adaptation)
                            LabeledContent(creatorString("workshopPending.translation"), value: detail.proposedOffer.terms.translation)
                            LabeledContent(creatorString("workshopPending.themeLimit"), value: limit(detail.proposedOffer.terms.themeLimit))
                            LabeledContent(creatorString("workshopPending.merchantLimit"), value: limit(detail.proposedOffer.terms.merchantLimit))
                            LabeledContent(creatorString("workshopPending.runLimit"), value: limit(detail.proposedOffer.terms.runLimit))
                            LabeledContent(creatorString("workshopPending.expiresAt"), value: detail.metadata.expiresAt)
                            Text(creatorString("workshopPending.fixedRestrictions"))
                            Text(creatorString("workshopPending.reviewRequired"))
                        }
                    }
                    Section(creatorString("workshopCreator.scope")) {
                        Text(verbatim: preview.disclosureText).textSelection(.enabled)
                        ForEach(0..<3) { index in
                            Toggle(creatorString("workshopCreator.confirm." + String(index)), isOn: Binding(
                                get: { controller.acknowledgments.contains(index) },
                                set: { controller.acknowledge(index, value: $0, appearance: appearance) }))
                                .disabled(controller.phase != .reviewing).accessibilityIdentifier("workshopCreator.confirm.\(index)")
                        }
                        Button(creatorString("workshopCreator.declare")) { run(controller.offerConfirm(appearance)) }
                            .disabled(!controller.canConfirm).accessibilityIdentifier("workshopCreator.declare")
                    }
                }
            }
            if let receipt = controller.receipt {
                Section(creatorString("workshopCreator.recorded")) {
                    Text(creatorString("workshopCreator.pendingReview"))
                    LabeledContent(creatorString("workshopCreator.package"), value: receipt.consentReference.moduleId)
                    LabeledContent(creatorString("workshopCreator.version"), value: receipt.consentReference.versionId)
                    LabeledContent(creatorString("workshopCreator.record"), value: receipt.consentReference.consentId)
                    Text(verbatim: receipt.declaredAt).font(.caption)
                    Button(creatorString("workshopCreator.another")) { run(controller.offerAnotherReview(appearance)) }
                        .accessibilityIdentifier("workshopCreator.another")
                }
            }
            if controller.phase != .submitting && controller.phase != .loading && controller.phase != .recorded {
                Button(creatorString(controller.pending == nil ? "workshopCreator.refresh" : "workshopCreator.checkStatus")) { run(controller.offerLoad(appearance)) }
                    .accessibilityIdentifier("workshopCreator.refresh")
            }
        }.navigationTitle(creatorString("workshopCreator.title")).navigationBarTitleDisplayMode(.inline)
            .privacySensitive().accessibilityIdentifier("workshopCreator.review")
            .onAppear { run(controller.appear(appearance)) }
            .onDisappear { controller.close(appearance); task?.cancel(); task = nil }
    }
    private func limit(_ value: WorkshopCreatorPendingOffer.Limit) -> String { value.unlimited ? "-1" : String(value.maximum) }
    private func run(_ action: WorkshopCreatorConsentController.Action?) {
        guard let action else { return }; task?.cancel(); task = Task { await action() }
    }
    private func issueKey(_ issue: WorkshopCreatorConsentIssue) -> String {
        switch issue {
        case .disabled: return "workshopCreator.unavailable"
        case .unknown, .pending: return "workshopCreator.unknown"
        case .storage: return "workshopCreator.storage"
        case .unauthorized, .stale: return "workshopCreator.changed"
        default: return "workshopCreator.failed"
        }
    }
}
