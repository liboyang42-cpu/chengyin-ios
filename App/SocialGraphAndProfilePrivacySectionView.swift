import SwiftUI
#if canImport(QuestifyCore)
import QuestifyCore
#endif

/// Self-contained row modeling `w2-06` self-profile edit roundtrip and `w2-07`
/// social 4-tab (`following` / `followers` / `friends` / `blacklist`) and visibility
/// (`public` / `friendsOnly` / `private`) parity checks.
public struct SocialProfileParityRow: Sendable, Equatable, Identifiable {
    public enum Scope: String, CaseIterable, Sendable, Equatable {
        case selfProfileEditRoundtrip = "w2-06"
        case socialFourTabsParity = "w2-07-tabs"
        case profileVisibilityScopes = "w2-07-visibility"
    }

    public enum Status: String, Sendable, Equatable {
        case ready
        case alert
    }

    public let id: String
    public let scope: Scope
    public let referenceBadge: String
    public let titleText: String
    public let detailText: String
    public let verifiedTokens: [String]
    public let status: Status

    public init(
        id: String,
        scope: Scope,
        referenceBadge: String,
        titleText: String,
        detailText: String,
        verifiedTokens: [String],
        status: Status = .ready
    ) {
        self.id = id
        self.scope = scope
        self.referenceBadge = referenceBadge
        self.titleText = titleText
        self.detailText = detailText
        self.verifiedTokens = verifiedTokens
        self.status = status
    }

    public var isReady: Bool {
        status == .ready
    }

    public var statusBadgeText: String {
        switch status {
        case .ready:
            return "已对齐"
        case .alert:
            return "缺失项告警"
        }
    }
}

/// Self-contained snapshot for `w2-06` self-profile edit roundtrip and `w2-07`
/// social graph 4-tab + 3-visibility-scope parity.
public struct SocialGraphAndProfilePrivacySnapshot: Sendable, Equatable {
    public static let requiredSocialTabs: [String] = [
        "following",
        "followers",
        "friends",
        "blacklist"
    ]
    public static let requiredVisibilityScopes: [String] = [
        "public",
        "friendsOnly",
        "private"
    ]

    public let selfProfileRoundtripVerified: Bool
    public let availableSocialTabs: [String]
    public let availableVisibilityScopes: [String]
    public let rows: [SocialProfileParityRow]

    public init(
        selfProfileRoundtripVerified: Bool = true,
        availableSocialTabs: [String] = Self.requiredSocialTabs,
        availableVisibilityScopes: [String] = Self.requiredVisibilityScopes
    ) {
        self.selfProfileRoundtripVerified = selfProfileRoundtripVerified
        self.availableSocialTabs = availableSocialTabs
        self.availableVisibilityScopes = availableVisibilityScopes

        let missingTabs = Self.requiredSocialTabs.filter { !availableSocialTabs.contains($0) }
        let missingScopes = Self.requiredVisibilityScopes.filter { !availableVisibilityScopes.contains($0) }

        self.rows = [
            SocialProfileParityRow(
                id: "w2-06-profile-edit-roundtrip",
                scope: .selfProfileEditRoundtrip,
                referenceBadge: "w2-06",
                titleText: "个人资料编辑与服务端回读闭环",
                detailText: selfProfileRoundtripVerified
                    ? "昵称、简介、头像与背景图修改均需服务端确认回读后更新，未知结果不作乐观假设。"
                    : "告警：个人资料编辑回读闭环未就绪。",
                verifiedTokens: ["nickname", "bio", "avatar", "readback"],
                status: selfProfileRoundtripVerified ? .ready : .alert
            ),
            SocialProfileParityRow(
                id: "w2-07-social-four-tabs",
                scope: .socialFourTabsParity,
                referenceBadge: "w2-07",
                titleText: "社交关系 4 分栏 (关注 / 粉丝 / 好友 / 黑名单)",
                detailText: missingTabs.isEmpty
                    ? "完整覆盖 following / followers / friends / blacklist 四分栏列表、互关识别与解除拉黑复核。"
                    : "告警：缺失社交关系分栏 \(missingTabs.joined(separator: ", "))。",
                verifiedTokens: availableSocialTabs,
                status: missingTabs.isEmpty ? .ready : .alert
            ),
            SocialProfileParityRow(
                id: "w2-07-visibility-scopes",
                scope: .profileVisibilityScopes,
                referenceBadge: "w2-07",
                titleText: "主页隐私可见性 3 档范围 (公开 / 仅好友 / 私密)",
                detailText: missingScopes.isEmpty
                    ? "完整支持 public / friendsOnly / private 三档可见性与陌生人受限视图。"
                    : "告警：缺失主页可见性档位 \(missingScopes.joined(separator: ", "))。",
                verifiedTokens: availableVisibilityScopes,
                status: missingScopes.isEmpty ? .ready : .alert
            )
        ]
    }

    public static let defaultReady = SocialGraphAndProfilePrivacySnapshot()

    public var isAllReady: Bool {
        !rows.isEmpty && rows.allSatisfy(\.isReady)
    }

    public var alertCount: Int {
        rows.filter { !$0.isReady }.count
    }

    public var summaryHeadlineText: String {
        isAllReady
            ? "w2-06 个人资料回读与 w2-07 社交 4 分栏 / 3 档隐私可见性全部就绪（\(rows.count)/\(rows.count)）"
            : "存在 \(alertCount) 项社交图谱或主页隐私对齐告警"
    }

    public func row(for scope: SocialProfileParityRow.Scope) -> SocialProfileParityRow? {
        rows.first { $0.scope == scope }
    }
}

/// Offline SwiftUI section view displaying `w2-06` self-profile edit roundtrip and `w2-07`
/// social 4-tab + visibility parity using `Text(verbatim:)` (`0` new `.xcstrings` keys) and
/// deterministic `socialProfileParity.*` accessibility identifiers.
@MainActor
public struct SocialGraphAndProfilePrivacySectionView: View {
    public let snapshot: SocialGraphAndProfilePrivacySnapshot
    public var onSelectRow: ((SocialProfileParityRow) -> Void)?

    public init(
        snapshot: SocialGraphAndProfilePrivacySnapshot = .defaultReady,
        onSelectRow: ((SocialProfileParityRow) -> Void)? = nil
    ) {
        self.snapshot = snapshot
        self.onSelectRow = onSelectRow
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: "个人资料与社交隐私关系图谱对齐状态")
                        .font(.headline)
                        .accessibilityIdentifier("socialProfileParity.header.title")
                    Text(verbatim: snapshot.summaryHeadlineText)
                        .font(.subheadline)
                        .foregroundStyle(snapshot.isAllReady ? .green : .orange)
                        .accessibilityIdentifier("socialProfileParity.header.summary")
                }
                Spacer()
                Text(verbatim: snapshot.isAllReady ? "全部就绪" : "存在告警")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(
                            snapshot.isAllReady
                                ? Color.green.opacity(0.15)
                                : Color.orange.opacity(0.15)
                        )
                    )
                    .accessibilityIdentifier("socialProfileParity.header.badge")
            }

            ForEach(snapshot.rows) { row in
                rowView(row)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.08)))
        .accessibilityIdentifier("socialProfileParity.section")
    }

    @ViewBuilder
    private func rowView(_ row: SocialProfileParityRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: row.titleText)
                    .font(.subheadline.weight(.medium))
                    .accessibilityIdentifier("socialProfileParity.row.\(row.id).title")
                Spacer()
                Text(verbatim: row.referenceBadge)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("socialProfileParity.row.\(row.id).ref")
                Text(verbatim: row.statusBadgeText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(row.isReady ? .green : .red)
                    .accessibilityIdentifier("socialProfileParity.row.\(row.id).status")
            }

            Text(verbatim: row.detailText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("socialProfileParity.row.\(row.id).detail")

            if !row.verifiedTokens.isEmpty {
                Text(verbatim: row.verifiedTokens.joined(separator: " · "))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("socialProfileParity.row.\(row.id).tokens")
            }

            if let onSelectRow {
                Button(action: { onSelectRow(row) }) {
                    Text(verbatim: "查看对齐项详情")
                        .font(.caption)
                }
                .accessibilityIdentifier("socialProfileParity.row.\(row.id).action")
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.06)))
        .accessibilityIdentifier("socialProfileParity.row.\(row.id)")
    }
}
