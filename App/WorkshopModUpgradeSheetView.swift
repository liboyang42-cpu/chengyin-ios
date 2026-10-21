import SwiftUI

/// Offline SwiftUI sheet presenting `WorkshopModUpgradePresentation` (W18.4 capability diff,
/// pinned existing runs notice, re-review requirement, buyer confirmation gate, M11-3
/// perpetual-purchased-version disclosure, and U08 H5 design-only rejection notice).
/// Uses `Text(verbatim:)` throughout so no new `.xcstrings` keys are required.
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
                Section(header: Text(verbatim: "模组包校验提示")) {
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

            Section(header: Text(verbatim: "版本与能力差异对比")) {
                Text(verbatim: presentation.versionTransitionText)
                    .font(.subheadline.weight(.medium))
                    .accessibilityIdentifier("workshop.upgrade.versionTransition")

                if presentation.addedCapabilities.isEmpty && presentation.removedCapabilities.isEmpty {
                    Text(verbatim: "能力声明无增减（仅内容哈希与版本号更新）")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    if !presentation.addedCapabilities.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(verbatim: "新增能力")
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
                            Text(verbatim: "移除能力")
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
                        Text(verbatim: "保持不变能力")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(verbatim: presentation.unchangedCapabilities.joined(separator: ", "))
                            .font(.footnote.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityIdentifier("workshop.upgrade.unchangedCapabilities")
                }
            }

            Section(header: Text(verbatim: "升级保障与重审规则")) {
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

            Section(header: Text(verbatim: "买方显式确认")) {
                Toggle(isOn: $confirmedByBuyer) {
                    Text(verbatim: presentation.confirmationPromptText)
                        .font(.subheadline)
                }
                .accessibilityIdentifier("workshop.upgrade.confirmToggle")

                Button(action: submitUpgradeDraft) {
                    Text(verbatim: "生成新版本本地升级草稿")
                        .frame(maxWidth: .infinity)
                }
                .disabled(!presentation.canConfirmUpgrade(confirmedByBuyer: confirmedByBuyer))
                .accessibilityIdentifier("workshop.upgrade.confirmButton")

                if let confirmedRequestId {
                    Text(verbatim: "已生成本地升级草稿请求：\(confirmedRequestId)")
                        .font(.footnote)
                        .foregroundStyle(.green)
                        .accessibilityIdentifier("workshop.upgrade.confirmedReceipt")
                }

                if let errorNotice {
                    Text(verbatim: errorNotice)
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
            errorNotice = "升级草稿请求未通过校验，请核对授权与确认状态。"
            return
        }
        guard let onConfirmDraft else {
            confirmedRequestId = nil
            errorNotice = "本机保存未接通，未保存升级草稿。"
            return
        }
        do {
            try onConfirmDraft(request)
            errorNotice = nil
            confirmedRequestId = request.requestId
        } catch {
            confirmedRequestId = nil
            errorNotice = "升级草稿未能保存，现有版本与场次保持不变。"
        }
    }
}
