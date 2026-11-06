import SwiftUI
#if canImport(QuestifyCore)
import QuestifyCore
#endif

/// Self-contained row for each of the 4 privacy & security redaction pillars:
/// `W19` private-home coordinate redaction, `W13.5` 6-disclosure location share gate,
/// `G-W04`/`I08` NPC AI sensitive data filtering & deletion fence, and `I05` 404/DELETED media cache eviction.
public struct PrivacyRedactionPillarRow: Identifiable, Equatable, Sendable {
    public enum PillarKind: String, CaseIterable, Equatable, Sendable {
        case w19PrivateHomeRedaction = "W19"
        case w13LocationShareDisclosure = "W13.5"
        case gW04NpcSensitiveFilterAndDelete = "G-W04/I08"
        case i05DeletedMediaCacheEviction = "I05"
    }

    public let id: String
    public let kind: PillarKind
    public let title: String
    public let summary: String
    public let redactionSample: String
    public let isEnforced: Bool

    public init(
        id: String? = nil,
        kind: PillarKind,
        title: String,
        summary: String,
        redactionSample: String,
        isEnforced: Bool
    ) {
        self.id = id ?? kind.rawValue
        self.kind = kind
        self.title = title
        self.summary = summary
        self.redactionSample = redactionSample
        self.isEnforced = isEnforced
    }
}

/// Self-contained snapshot for the 4 privacy & security redaction pillars.
public struct PrivacyAndSecurityRedactionSnapshot: Equatable, Sendable {
    public static let requiredLocationDisclosureCount: Int = 6

    public let privateHomeCoordinatesRedacted: Bool
    public let locationShareDisclosureItemsCount: Int
    public let npcSensitiveFilterAndDeletionFenced: Bool
    public let deletedMediaCacheEvictedImmediately: Bool
    public let rows: [PrivacyRedactionPillarRow]

    public init(
        privateHomeCoordinatesRedacted: Bool,
        locationShareDisclosureItemsCount: Int,
        npcSensitiveFilterAndDeletionFenced: Bool,
        deletedMediaCacheEvictedImmediately: Bool,
        rows: [PrivacyRedactionPillarRow]
    ) {
        self.privateHomeCoordinatesRedacted = privateHomeCoordinatesRedacted
        self.locationShareDisclosureItemsCount = locationShareDisclosureItemsCount
        self.npcSensitiveFilterAndDeletionFenced = npcSensitiveFilterAndDeletionFenced
        self.deletedMediaCacheEvictedImmediately = deletedMediaCacheEvictedImmediately
        self.rows = rows
    }

    public var hasCompleteLocationDisclosures: Bool {
        locationShareDisclosureItemsCount >= Self.requiredLocationDisclosureCount
    }

    public var enforcedRowCount: Int {
        rows.filter(\.isEnforced).count
    }

    public var isAllCompliant: Bool {
        privateHomeCoordinatesRedacted &&
            hasCompleteLocationDisclosures &&
            npcSensitiveFilterAndDeletionFenced &&
            deletedMediaCacheEvictedImmediately &&
            Set(rows.map(\.kind)) == Set(PrivacyRedactionPillarRow.PillarKind.allCases) &&
            rows.allSatisfy(\.isEnforced)
    }

    public static let compliantSample = PrivacyAndSecurityRedactionSnapshot(
        privateHomeCoordinatesRedacted: true,
        locationShareDisclosureItemsCount: 6,
        npcSensitiveFilterAndDeletionFenced: true,
        deletedMediaCacheEvictedImmediately: true,
        rows: [
            PrivacyRedactionPillarRow(
                kind: .w19PrivateHomeRedaction,
                title: "W19 私人据点坐标脱敏",
                summary: "诊断日志、崩溃报告与分享链路永不输出私人据点经纬度",
                redactionSample: "HomeReturnCheck[redacted]",
                isEnforced: true
            ),
            PrivacyRedactionPillarRow(
                kind: .w13LocationShareDisclosure,
                title: "W13.5 位置共享六项必读告知",
                summary: "首次开启位置共享前必须完整展示对象、粒度、用途、时效、撤回与权限回退六项说明",
                redactionSample: "6/6 必读告知项已确认",
                isEnforced: true
            ),
            PrivacyRedactionPillarRow(
                kind: .gW04NpcSensitiveFilterAndDelete,
                title: "G-W04 / I08 NPC 对话敏感过滤与删除围栏",
                summary: "屏蔽手机号/身份证/位置等敏感输入，提供本地清空且禁止未审批远端删除写入",
                redactionSample: "[敏感信息已拦截] · 远端删除默认关闭",
                isEnforced: true
            ),
            PrivacyRedactionPillarRow(
                kind: .i05DeletedMediaCacheEviction,
                title: "I05 404/DELETED 媒体缓存即时驱逐",
                summary: "收到 404 或 DELETED 状态时立即驱逐本地图片与视频缓存并显示占位提示",
                redactionSample: "HTTP 404 / DELETED -> 缓存已清除",
                isEnforced: true
            )
        ]
    )
}

@MainActor
public struct PrivacyAndSecurityRedactionSectionView: View {
    public let snapshot: PrivacyAndSecurityRedactionSnapshot

    public init(snapshot: PrivacyAndSecurityRedactionSnapshot = .compliantSample) {
        self.snapshot = snapshot
    }

    public var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: "隐私脱敏与安全围栏审计")
                    .font(.headline)
                    .accessibilityIdentifier("privacyRedaction.title")

                Text(verbatim: Self.overallStatusText(for: snapshot))
                    .font(.subheadline)
                    .foregroundStyle(snapshot.isAllCompliant ? .green : .red)
                    .accessibilityIdentifier("privacyRedaction.overallStatus")

                Text(verbatim: Self.homeRedactionStatusText(for: snapshot))
                    .font(.footnote)
                    .accessibilityIdentifier("privacyRedaction.homeRedactionStatus")

                Text(verbatim: Self.locationDisclosureStatusText(for: snapshot))
                    .font(.footnote)
                    .accessibilityIdentifier("privacyRedaction.locationDisclosureStatus")

                Text(verbatim: Self.npcSafetyStatusText(for: snapshot))
                    .font(.footnote)
                    .accessibilityIdentifier("privacyRedaction.npcSafetyStatus")

                Text(verbatim: Self.cacheEvictionStatusText(for: snapshot))
                    .font(.footnote)
                    .accessibilityIdentifier("privacyRedaction.cacheEvictionStatus")
            }
            .padding(.vertical, 4)

            if snapshot.rows.isEmpty {
                Text(verbatim: "暂无隐私与安全围栏检查项")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("privacyRedaction.empty")
            } else {
                ForEach(snapshot.rows) { row in
                    PrivacyRedactionPillarRowView(row: row)
                }
            }
        }
        .accessibilityIdentifier("privacyRedaction.section")
    }

    public static func overallStatusText(for snapshot: PrivacyAndSecurityRedactionSnapshot) -> String {
        snapshot.isAllCompliant
            ? "整体状态：四大隐私脱敏与安全围栏全部生效（\(snapshot.enforcedRowCount)/\(snapshot.rows.count)）"
            : "整体状态：存在未生效的隐私脱敏或安全围栏项（\(snapshot.enforcedRowCount)/\(snapshot.rows.count)）"
    }

    public static func homeRedactionStatusText(for snapshot: PrivacyAndSecurityRedactionSnapshot) -> String {
        snapshot.privateHomeCoordinatesRedacted
            ? "W19 私人据点：坐标已脱敏（HomeReturnCheck[redacted]）"
            : "W19 私人据点：存在未脱敏坐标风险"
    }

    public static func locationDisclosureStatusText(for snapshot: PrivacyAndSecurityRedactionSnapshot) -> String {
        "W13.5 位置共享告知：\(snapshot.locationShareDisclosureItemsCount)/\(PrivacyAndSecurityRedactionSnapshot.requiredLocationDisclosureCount) 项已齐备"
    }

    public static func npcSafetyStatusText(for snapshot: PrivacyAndSecurityRedactionSnapshot) -> String {
        snapshot.npcSensitiveFilterAndDeletionFenced
            ? "G-W04/I08 NPC 对话安全：敏感词过滤与删除围栏已启用"
            : "G-W04/I08 NPC 对话安全：过滤或删除围栏未就绪"
    }

    public static func cacheEvictionStatusText(for snapshot: PrivacyAndSecurityRedactionSnapshot) -> String {
        snapshot.deletedMediaCacheEvictedImmediately
            ? "I05 媒体缓存驱逐：404/DELETED 即时清理已启用"
            : "I05 媒体缓存驱逐：404/DELETED 即时清理未启用"
    }
}

@MainActor
private struct PrivacyRedactionPillarRowView: View {
    let row: PrivacyRedactionPillarRow

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(verbatim: row.title)
                    .font(.subheadline.bold())
                Spacer()
                Text(verbatim: row.isEnforced ? "已生效" : "未生效")
                    .font(.caption)
                    .foregroundStyle(row.isEnforced ? .green : .red)
            }

            Text(verbatim: row.summary)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(verbatim: "验证样本：\(row.redactionSample)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("privacyRedaction.row")
    }
}
