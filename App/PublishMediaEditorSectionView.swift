import SwiftUI

/// Reform plan v9 H-W02 / U01 SwiftUI section view for `PublishMediaEditorBridge`.
/// Renders content ownership status, release status, publishable readiness, and
/// per-item media stage progression (`select -> process -> upload -> review -> save -> read -> play`)
/// using `Text(verbatim:)` throughout without adding localization catalog keys.
@MainActor
public struct PublishMediaEditorSectionView: View {
    public let bridge: PublishMediaEditorBridge
    public let actor: PublishMediaEditorActor?

    public init(bridge: PublishMediaEditorBridge, actor: PublishMediaEditorActor? = nil) {
        self.bridge = bridge
        self.actor = actor
    }

    public var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: "内容归属与媒体发布链")
                    .font(.headline)

                Text(verbatim: "归属方：\(Self.ownerKindLabel(bridge.ownership.ownerKind))（\(bridge.ownership.ownerId)） · 世界：\(bridge.ownership.worldId)")
                    .font(.subheadline)
                    .accessibilityIdentifier("publishMediaEditor.ownership")

                if let actor {
                    let permitted = (try? bridge.ownership.permitsEdit(
                        actorKind: actor.kind,
                        actorId: actor.actorId,
                        worldId: actor.worldId
                    )) != nil
                    Text(verbatim: permitted ? "编辑权限：当前归属方允许编辑" : "编辑权限：跨归属方或跨世界编辑已拒绝")
                        .font(.footnote)
                        .foregroundStyle(permitted ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
                        .accessibilityIdentifier("publishMediaEditor.permission")
                }

                HStack(spacing: 12) {
                    Text(verbatim: "版本状态：\(Self.releaseStatusLabel(bridge.releaseStatus))")
                        .font(.subheadline)
                        .accessibilityIdentifier("publishMediaEditor.releaseStatus")

                    Text(verbatim: bridge.selection.publishable ? "发布就绪：已满足" : "发布就绪：未满足")
                        .font(.subheadline)
                        .foregroundStyle(bridge.selection.publishable ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                        .accessibilityIdentifier("publishMediaEditor.publishable")
                }

                Text(verbatim: "配置版本：\(bridge.selection.profile.profileVersion) · 已选 \(bridge.selection.items.count)/\(bridge.selection.profile.maxItems) · 可回读恢复 \(bridge.selection.restorable().count) 项")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("publishMediaEditor.profileSummary")
            }
            .padding(.vertical, 4)

            if bridge.selection.items.isEmpty {
                Text(verbatim: "暂无媒体条目（select -> process -> upload -> review -> save -> read -> play）")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("publishMediaEditor.empty")
            } else {
                ForEach(bridge.selection.items) { item in
                    PublishMediaEditorItemRow(item: item)
                }
            }
        }
        .accessibilityIdentifier("publishMediaEditor.section")
    }

    public static func ownerKindLabel(_ kind: ContentOwnership.OwnerKind) -> String {
        switch kind {
        case .platform: return "平台"
        case .merchant: return "商家"
        case .club: return "俱乐部"
        case .creator: return "创作者"
        }
    }

    public static func releaseStatusLabel(_ status: ThemeReleaseStatus) -> String {
        switch status {
        case .draft: return "草稿(DRAFT)"
        case .review: return "审核中(REVIEW)"
        case .approved: return "已通过(APPROVED)"
        case .published: return "已发布(PUBLISHED)"
        case .retired: return "已下架(RETIRED)"
        }
    }

    public static func stageLabel(_ stage: PublishMediaStage) -> String {
        switch stage {
        case .selected: return "select"
        case .processed: return "process"
        case .uploaded: return "upload"
        case .reviewed: return "review"
        case .saved: return "save"
        case .readable: return "read"
        case .playable: return "play"
        }
    }

    public static func stageChainSummary(current: PublishMediaStage) -> String {
        PublishMediaStage.allCases.map { stage in
            let name = stageLabel(stage)
            if stage < current {
                return "[\(name)✓]"
            } else if stage == current {
                return "[\(name)*]"
            } else {
                return name
            }
        }.joined(separator: " -> ")
    }
}

@MainActor
private struct PublishMediaEditorItemRow: View {
    let item: PublishMediaItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(verbatim: kindHeader)
                    .font(.subheadline.bold())
                Spacer()
                Text(verbatim: "当前阶段：\(PublishMediaEditorSectionView.stageLabel(item.stage))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(verbatim: PublishMediaEditorSectionView.stageChainSummary(current: item.stage))
                .font(.caption2)
                .foregroundStyle(.secondary)

            if let review = item.review {
                Text(verbatim: reviewSummary(review))
                    .font(.caption)
                    .foregroundStyle(review == .rejected ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
            }

            if let assetId = item.assetId {
                Text(verbatim: "资源ID：\(assetId)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var kindHeader: String {
        switch item.kind {
        case .image:
            return "图片 · \(item.byteCount) B"
        case .video:
            let duration = item.durationMilliseconds ?? 0
            return "视频 · \(item.byteCount) B · \(duration) ms"
        }
    }

    private func reviewSummary(_ review: PublishMediaItem.Review) -> String {
        switch review {
        case .pending:
            return "审核状态：待审核(PENDING)"
        case .approved:
            if item.kind == .video, let poster = item.posterAssetId {
                return "审核状态：已通过(APPROVED) · 封面：\(poster)"
            }
            return "审核状态：已通过(APPROVED)"
        case .rejected:
            return "审核状态：已驳回(REJECTED，不可保存或发布)"
        }
    }
}
