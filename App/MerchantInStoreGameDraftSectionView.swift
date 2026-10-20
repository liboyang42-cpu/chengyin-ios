import SwiftUI

/// SwiftUI section presenting `InStoreGameDraft` required-field validation,
/// `MerchantProductDraft` canonical SKU validation, two-domain approval blockers,
/// and idempotent publish readiness while respecting `MerchantAICommerceGates`.
/// Uses `Text(verbatim:)` exclusively so no new `.xcstrings` keys are required.
public struct MerchantInStoreGameDraftSectionView: View {
    public let presentation: MerchantInStoreGameAuthoringPresentation

    public init(presentation: MerchantInStoreGameAuthoringPresentation) {
        self.presentation = presentation
    }

    public var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: presentation.statusHeadline)
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("merchantInStoreGame.statusHeadline")
                Text(verbatim: "修订版本 v\(presentation.revision.version) · 阶段 \(presentation.revision.stage.rawValue)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("merchantInStoreGame.revisionSummary")
            }

            ForEach(presentation.gameChecklist) { item in
                HStack {
                    Image(systemName: item.isSatisfied ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(item.isSatisfied ? .green : .orange)
                    Text(verbatim: item.title)
                    Spacer()
                    Text(verbatim: item.isSatisfied ? "已完备" : "待补充")
                        .font(.caption)
                        .foregroundStyle(item.isSatisfied ? .secondary : .orange)
                }
                .accessibilityIdentifier("merchantInStoreGame.field." + item.id)
            }

            ForEach(presentation.productIssues) { issue in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "xmark.octagon.fill")
                        .foregroundStyle(.red)
                    Text(verbatim: issue.message)
                        .font(.footnote)
                }
                .accessibilityIdentifier("merchantInStoreGame.productIssue." + issue.id)
            }

            ForEach(presentation.approvalBlockers) { blocker in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lock.shield.fill")
                        .foregroundStyle(.secondary)
                    Text(verbatim: blocker.message)
                        .font(.footnote)
                }
                .accessibilityIdentifier("merchantInStoreGame.blocker." + blocker.id)
            }

            if let command = presentation.publishCommand {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: "幂等发布指令就绪 · \(command.kind.rawValue)")
                        .font(.caption.weight(.medium))
                    Text(verbatim: "预期版本 v\(command.expectedVersion) · 摘要 \(command.reviewedHash ?? "-")")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("merchantInStoreGame.publishReady")
            } else {
                Text(verbatim: "暂不可发布：需满足全部必填字段、SKU 校验、双域审批及门控开关")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("merchantInStoreGame.publishBlocked")
            }
        } header: {
            Text(verbatim: "店内玩法与商品草稿双域审核")
        }
    }
}
