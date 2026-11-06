import SwiftUI

/// Offline SwiftUI sheet presenting `WorkshopModUpgradePresentation` (W18.4 capability diff,
/// pinned existing runs notice, re-review requirement, buyer confirmation gate, M11-3
/// perpetual-purchased-version disclosure, and U08 H5 design-only rejection notice).
/// Fixed copy uses localized keys; texts produced by the presentation model are shown verbatim.
@MainActor
public struct WorkshopModUpgradeSheetView: View {
    public let presentation: WorkshopModUpgradePresentation
    public var onConfirmDraft: ((WorkshopUpgradeDraftRequest) throws -> Void)?

    @State private var confirmedByBuyer = false
    @State private var errorNotice: String?
    @State private var confirmedRequestId: String?

    public init(
        presentation: WorkshopModUpgradePresentation,
        onConfirmDraft: ((WorkshopUpgradeDraftRequest) throws -> Void)? = nil
    ) {
        self.presentation = presentation
        self.onConfirmDraft = onConfirmDraft
    }

    public var body: some View {
        List {
            if let manifestNotice = presentation.manifestIssueNotice {
                Section(header: Text("workshopUpgrade.manifestTitle")) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(verbatim: manifestNotice.titleText)
                            .font(.headline)
                            .foregroundStyle(.red)
                        Text(verbatim: manifestNotice.bodyText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityIdentifier("workshop.upgrade.manifestIssue")
                }
            }

            Section(header: Text(verbatim: presentation.useTermPresentation.titleText)) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: presentation.useTermPresentation.versionSummaryText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(verbatim: presentation.useTermPresentation.subscriptionSurvivalNotice)
                        .font(.subheadline)
                    Text(verbatim: presentation.useTermPresentation.redistributionNotice)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("workshop.upgrade.perpetualUseDisclosure")
            }

            Section(header: Text("workshopUpgrade.diffTitle")) {
                Text(verbatim: presentation.versionTransitionText)
                    .font(.subheadline.weight(.medium))
                    .accessibilityIdentifier("workshop.upgrade.versionTransition")

                if presentation.addedCapabilities.isEmpty && presentation.removedCapabilities.isEmpty {
                    Text("workshopUpgrade.noFeatureChange")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    if !presentation.addedCapabilities.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("workshopUpgrade.added")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.green)
                            ForEach(presentation.addedCapabilities, id: \.self) { cap in
                                Text(verbatim: "+ \(cap)")
                                    .font(.footnote.monospaced())
                            }
                        }
                        .accessibilityIdentifier("workshop.upgrade.addedCapabilities")
                    }

                    if !presentation.removedCapabilities.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("workshopUpgrade.removed")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.orange)
                            ForEach(presentation.removedCapabilities, id: \.self) { cap in
                                Text(verbatim: "- \(cap)")
                                    .font(.footnote.monospaced())
                            }
                        }
                        .accessibilityIdentifier("workshop.upgrade.removedCapabilities")
                    }
                }

                if !presentation.unchangedCapabilities.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("workshopUpgrade.unchanged")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(verbatim: presentation.unchangedCapabilities.joined(separator: ", "))
                            .font(.footnote.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityIdentifier("workshop.upgrade.unchangedCapabilities")
                }
            }

            Section(header: Text("workshopUpgrade.rulesTitle")) {
                Text(verbatim: presentation.pinnedExistingRunsNotice)
                    .font(.subheadline)
                    .accessibilityIdentifier("workshop.upgrade.pinnedRunsNotice")
                Text(verbatim: presentation.reReviewRequirementNotice)
                    .font(.subheadline)
                    .accessibilityIdentifier("workshop.upgrade.reReviewNotice")
                Text(verbatim: presentation.coverageNotice)
                    .font(.footnote)
                    .foregroundStyle(presentation.preview.coverage == .covered ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
                    .accessibilityIdentifier("workshop.upgrade.coverageNotice")
            }

            Section(header: Text("workshopUpgrade.confirmTitle")) {
                Toggle(isOn: $confirmedByBuyer) {
                    Text(verbatim: presentation.confirmationPromptText)
                        .font(.subheadline)
                }
                .accessibilityIdentifier("workshop.upgrade.confirmToggle")

                Button(action: submitUpgradeDraft) {
                    Text("workshopUpgrade.confirmButton")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.questifyPrimary)
                .disabled(confirmedRequestId != nil || !presentation.canConfirmUpgrade(confirmedByBuyer: confirmedByBuyer))
                .accessibilityIdentifier("workshop.upgrade.confirmButton")

                if confirmedRequestId != nil {
                    Text("workshopUpgrade.saved")
                        .font(.footnote)
                        .foregroundStyle(.green)
                        .accessibilityIdentifier("workshop.upgrade.confirmedReceipt")
                }

                if let errorNotice {
                    Text(LocalizedStringKey(errorNotice))
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("workshop.upgrade.errorNotice")
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func submitUpgradeDraft() {
        guard confirmedRequestId == nil else { return }
        let request: WorkshopUpgradeDraftRequest
        do {
            request = try presentation.makeUpgradeDraftRequest(confirmedByBuyer: confirmedByBuyer)
        } catch {
            confirmedRequestId = nil
            errorNotice = "workshopUpgrade.error.invalid"
            return
        }
        guard let onConfirmDraft else {
            confirmedRequestId = nil
            errorNotice = "workshopUpgrade.error.unavailable"
            return
        }
        do {
            try onConfirmDraft(request)
            errorNotice = nil
            confirmedRequestId = request.requestId
        } catch WorkshopUpgradeDraftIssue.unavailable {
            confirmedRequestId = nil
            errorNotice = "workshopUpgrade.error.unavailable"
        } catch {
            confirmedRequestId = nil
            errorNotice = "workshopUpgrade.error.failed"
        }
    }
}
