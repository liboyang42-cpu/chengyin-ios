import SwiftUI
import QuestifyCore

/// Self-contained diagnostic row for `I05` 404/DELETED `URLCache` media eviction
/// and fail-closed topic like write gate (`w2-13`).
public struct TopicLikeEvictionRow: Identifiable, Equatable, Sendable {
    public let ruleID: String
    public let title: String
    public let detail: String
    public let isEnforced: Bool

    public var id: String { ruleID }

    public init(
        ruleID: String,
        title: String,
        detail: String,
        isEnforced: Bool
    ) {
        self.ruleID = ruleID
        self.title = title
        self.detail = detail
        self.isEnforced = isEnforced
    }
}

/// Self-contained snapshot for `I05` 404/DELETED `URLCache` media eviction and
/// fail-closed topic like write gate (`likeGrantEnabled == false` by default).
public struct TopicLikeAndSquareEvictionSnapshot: Equatable, Sendable {
    public static let canonicalRuleIDs: [String] = [
        "Square404MediaEviction",
        "SquareDeletedPostEviction",
        "TopicLikeFailClosedGate",
        "TopicLikeDirectionEcho"
    ]

    public let evictsCacheOn404: Bool
    public let evictsCacheOnDeletedStatus: Bool
    public let likeGrantEnabled: Bool
    public let preservesServerLikeDirectionEcho: Bool
    public let rows: [TopicLikeEvictionRow]

    public init(
        evictsCacheOn404: Bool = true,
        evictsCacheOnDeletedStatus: Bool = true,
        likeGrantEnabled: Bool = false,
        preservesServerLikeDirectionEcho: Bool = true,
        customRows: [TopicLikeEvictionRow]? = nil
    ) {
        self.evictsCacheOn404 = evictsCacheOn404
        self.evictsCacheOnDeletedStatus = evictsCacheOnDeletedStatus
        self.likeGrantEnabled = likeGrantEnabled
        self.preservesServerLikeDirectionEcho = preservesServerLikeDirectionEcho

        let failClosedGateEnforced = !likeGrantEnabled
        if let customRows {
            self.rows = customRows
        } else {
            self.rows = [
                TopicLikeEvictionRow(
                    ruleID: "Square404MediaEviction",
                    title: "I05 广场 404 媒体缓存驱逐",
                    detail: evictsCacheOn404
                        ? "收到 404 响应时立即驱逐本地 URLCache 与内存媒体项"
                        : "404 响应未触发本地媒体缓存驱逐",
                    isEnforced: evictsCacheOn404
                ),
                TopicLikeEvictionRow(
                    ruleID: "SquareDeletedPostEviction",
                    title: "I05 广场 DELETED 帖子媒体清理",
                    detail: evictsCacheOnDeletedStatus
                        ? "帖子状态变为 DELETED 时同步清理关联图片与视频缓存"
                        : "DELETED 状态未清理关联媒体缓存",
                    isEnforced: evictsCacheOnDeletedStatus
                ),
                TopicLikeEvictionRow(
                    ruleID: "TopicLikeFailClosedGate",
                    title: "w2-13 推文点赞写入默认关闭门控",
                    detail: failClosedGateEnforced
                        ? "likeGrantEnabled 默认关闭 (false)，未显式授权前拒绝写入"
                        : "likeGrantEnabled 未处于默认关闭状态",
                    isEnforced: failClosedGateEnforced
                ),
                TopicLikeEvictionRow(
                    ruleID: "TopicLikeDirectionEcho",
                    title: "w2-13 点赞/取消点赞方向回显校验",
                    detail: preservesServerLikeDirectionEcho
                        ? "TopicLikeDirection 严格对齐服务端回显，禁止乐观伪造计数"
                        : "缺少 TopicLikeDirection 服务端回显校验",
                    isEnforced: preservesServerLikeDirectionEcho
                )
            ]
        }
    }

    public var hasCanonicalRules: Bool {
        rows.map(\.ruleID) == Self.canonicalRuleIDs
    }

    public var isAllCompliant: Bool {
        evictsCacheOn404
            && evictsCacheOnDeletedStatus
            && !likeGrantEnabled
            && preservesServerLikeDirectionEcho
            && hasCanonicalRules
            && rows.allSatisfy(\.isEnforced)
    }
}

/// SwiftUI section rendering `I05` 404/DELETED `URLCache` media eviction and
/// fail-closed topic like write gate using `Text(verbatim:)` throughout (0 new `.xcstrings` keys).
@MainActor public struct TopicLikeAndSquareEvictionSectionView: View {
    public let snapshot: TopicLikeAndSquareEvictionSnapshot

    public init(snapshot: TopicLikeAndSquareEvictionSnapshot = TopicLikeAndSquareEvictionSnapshot()) {
        self.snapshot = snapshot
    }

    public var statusHeadline: String {
        if !snapshot.evictsCacheOn404 || !snapshot.evictsCacheOnDeletedStatus {
            return "I05 媒体缓存告警：404 或 DELETED 状态未立即驱逐本地缓存"
        }
        if snapshot.likeGrantEnabled {
            return "w2-13 点赞门控告警：likeGrantEnabled 默认必须保持关闭 (false)"
        }
        if !snapshot.preservesServerLikeDirectionEcho || !snapshot.isAllCompliant {
            return "推文点赞方向回显或广场缓存清理存在未达标项"
        }
        return "I05 404/DELETED 媒体缓存驱逐与 w2-13 点赞默认关闭门控全部就绪"
    }

    public var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: statusHeadline)
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("topicLikeEviction.statusHeadline")
                Text(verbatim: "404 驱逐：\(snapshot.evictsCacheOn404 ? "已开启" : "未开启") · DELETED 驱逐：\(snapshot.evictsCacheOnDeletedStatus ? "已开启" : "未开启") · 点赞门控：\(snapshot.likeGrantEnabled ? "开启" : "默认关闭")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("topicLikeEviction.summary")
            }

            ForEach(snapshot.rows) { row in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: row.isEnforced ? "trash.slash.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(row.isEnforced ? .green : .red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: row.title)
                            .font(.footnote.weight(.medium))
                        Text(verbatim: row.detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(verbatim: row.isEnforced ? "已生效" : "未生效")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(row.isEnforced ? .green : .red)
                }
                .accessibilityIdentifier("topicLikeEviction.row." + row.ruleID)
            }
        } header: {
            Text(verbatim: "I05 广场媒体驱逐与 w2-13 点赞门控")
        }
        .accessibilityIdentifier("topicLikeEviction.section")
    }
}
