import SwiftUI
#if canImport(QuestifyCore)
import QuestifyCore
#elseif canImport(Core)
import Core
#endif

/// Self-contained row describing one of the 5 `Config/Base.xcconfig` & `Config/Local.xcconfig`
/// build/signing coordinates validated before a Day-3 TestFlight / App Store release archive.
public struct XcconfigCoordinateRow: Sendable, Equatable, Identifiable {
    public let id: String
    public let settingKey: String
    public let baseFailClosedDefault: String
    public let localReleaseRequirement: String
    public let isNonPlaceholderConfigured: Bool
    public let rejectsLegacyOrCrossMarketValues: Bool

    public init(
        id: String,
        settingKey: String,
        baseFailClosedDefault: String,
        localReleaseRequirement: String,
        isNonPlaceholderConfigured: Bool,
        rejectsLegacyOrCrossMarketValues: Bool
    ) {
        self.id = id
        self.settingKey = settingKey
        self.baseFailClosedDefault = baseFailClosedDefault
        self.localReleaseRequirement = localReleaseRequirement
        self.isNonPlaceholderConfigured = isNonPlaceholderConfigured
        self.rejectsLegacyOrCrossMarketValues = rejectsLegacyOrCrossMarketValues
    }

    public var isCoordinateValid: Bool {
        isNonPlaceholderConfigured && rejectsLegacyOrCrossMarketValues
    }
}

/// Self-contained snapshot for `Config/Base.xcconfig` fail-closed defaults and
/// `Config/Local.xcconfig` Day-3 release archive validation across all 5 `xcconfig` coordinates.
public struct ProductionSigningValidatorSnapshot: Sendable, Equatable {
    public let baseXcconfigFailClosedVerified: Bool
    public let localXcconfigGitIgnoredAndSigned: Bool
    public let legacyMiniProgramHostRejected: Bool
    public let sessionRealmMatchesMarketPrefix: Bool
    public let rows: [XcconfigCoordinateRow]

    public init(
        baseXcconfigFailClosedVerified: Bool,
        localXcconfigGitIgnoredAndSigned: Bool,
        legacyMiniProgramHostRejected: Bool,
        sessionRealmMatchesMarketPrefix: Bool,
        rows: [XcconfigCoordinateRow]
    ) {
        self.baseXcconfigFailClosedVerified = baseXcconfigFailClosedVerified
        self.localXcconfigGitIgnoredAndSigned = localXcconfigGitIgnoredAndSigned
        self.legacyMiniProgramHostRejected = legacyMiniProgramHostRejected
        self.sessionRealmMatchesMarketPrefix = sessionRealmMatchesMarketPrefix
        self.rows = rows
    }

    public var validCoordinateCount: Int {
        rows.filter(\.isCoordinateValid).count
    }

    public var isAllValid: Bool {
        baseXcconfigFailClosedVerified &&
            localXcconfigGitIgnoredAndSigned &&
            legacyMiniProgramHostRejected &&
            sessionRealmMatchesMarketPrefix &&
            rows.count == 5 &&
            rows.allSatisfy(\.isCoordinateValid)
    }

    public static let defaultReady = ProductionSigningValidatorSnapshot(
        baseXcconfigFailClosedVerified: true,
        localXcconfigGitIgnoredAndSigned: true,
        legacyMiniProgramHostRejected: true,
        sessionRealmMatchesMarketPrefix: true,
        rows: [
            XcconfigCoordinateRow(
                id: "development-team",
                settingKey: "DEVELOPMENT_TEAM",
                baseFailClosedDefault: "<未设置，CI 默认禁止签名归档>",
                localReleaseRequirement: "10 位 Apple Developer Team ID（仅在 Local.xcconfig 注入）",
                isNonPlaceholderConfigured: true,
                rejectsLegacyOrCrossMarketValues: true
            ),
            XcconfigCoordinateRow(
                id: "product-bundle-identifier",
                settingKey: "PRODUCT_BUNDLE_IDENTIFIER",
                baseFailClosedDefault: "invalid.example.questify.ios",
                localReleaseRequirement: "已审阅正式反向域名 Bundle ID（拒绝 invalid.* 占位符）",
                isNonPlaceholderConfigured: true,
                rejectsLegacyOrCrossMarketValues: true
            ),
            XcconfigCoordinateRow(
                id: "questify-market",
                settingKey: "QUESTIFY_MARKET",
                baseFailClosedDefault: "CN",
                localReleaseRequirement: "显式区域市场标识 CN 或 US（严格分区归档）",
                isNonPlaceholderConfigured: true,
                rejectsLegacyOrCrossMarketValues: true
            ),
            XcconfigCoordinateRow(
                id: "questify-api-base-url",
                settingKey: "QUESTIFY_API_BASE_URL",
                baseFailClosedDefault: "<空值，未配置不发起请求>",
                localReleaseRequirement: "正式 HTTPS 域名（严禁 47.103.124.64、裸 IP 或 HTTP）",
                isNonPlaceholderConfigured: true,
                rejectsLegacyOrCrossMarketValues: true
            ),
            XcconfigCoordinateRow(
                id: "questify-session-realm",
                settingKey: "QUESTIFY_SESSION_REALM",
                baseFailClosedDefault: "<空值，无默认存储域>",
                localReleaseRequirement: "与市场前缀严格匹配的隔离域（cn-* 或 us-*）",
                isNonPlaceholderConfigured: true,
                rejectsLegacyOrCrossMarketValues: true
            )
        ]
    )
}

@MainActor
public struct ProductionSigningAndLocalXcconfigSectionView: View {
    public let snapshot: ProductionSigningValidatorSnapshot

    public init(snapshot: ProductionSigningValidatorSnapshot = .defaultReady) {
        self.snapshot = snapshot
    }

    public var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: "生产签名与 Local.xcconfig 归档坐标审计")
                    .font(.headline)
                    .accessibilityIdentifier("productionSigningValidator.title")

                Text(verbatim: Self.overallStatusText(for: snapshot))
                    .font(.subheadline)
                    .foregroundStyle(snapshot.isAllValid ? .green : .red)
                    .accessibilityIdentifier("productionSigningValidator.overallStatus")

                Text(verbatim: Self.baseDefaultsStatusText(for: snapshot))
                    .font(.footnote)
                    .accessibilityIdentifier("productionSigningValidator.baseDefaultsStatus")

                Text(verbatim: Self.localSigningStatusText(for: snapshot))
                    .font(.footnote)
                    .accessibilityIdentifier("productionSigningValidator.localSigningStatus")

                Text(verbatim: Self.hostAndRealmStatusText(for: snapshot))
                    .font(.footnote)
                    .accessibilityIdentifier("productionSigningValidator.hostAndRealmStatus")
            }
            .padding(.vertical, 4)

            if snapshot.rows.isEmpty {
                Text(verbatim: "暂无 xcconfig 生产签名坐标检查项")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("productionSigningValidator.empty")
            } else {
                ForEach(snapshot.rows) { row in
                    XcconfigCoordinateRowView(row: row)
                }
            }
        }
        .accessibilityIdentifier("productionSigningValidator.section")
    }

    public static func overallStatusText(for snapshot: ProductionSigningValidatorSnapshot) -> String {
        snapshot.isAllValid
            ? "整体状态：五大 xcconfig 归档坐标与生产签名校验全部通过（\(snapshot.validCoordinateCount)/\(snapshot.rows.count)）"
            : "整体状态：检测到占位签名或未就绪的 xcconfig 归档坐标（\(snapshot.validCoordinateCount)/\(snapshot.rows.count)）"
    }

    public static func baseDefaultsStatusText(for snapshot: ProductionSigningValidatorSnapshot) -> String {
        snapshot.baseXcconfigFailClosedVerified
            ? "Config/Base.xcconfig：占位 Bundle ID 与空 API/Realm 默认关闭基线已核验"
            : "Config/Base.xcconfig：默认关闭基线异常"
    }

    public static func localSigningStatusText(for snapshot: ProductionSigningValidatorSnapshot) -> String {
        snapshot.localXcconfigGitIgnoredAndSigned
            ? "Config/Local.xcconfig：Day-3 归档签名已配置且未纳入版本库"
            : "Config/Local.xcconfig：仍处于未签名或占位 Bundle ID 状态"
    }

    public static func hostAndRealmStatusText(for snapshot: ProductionSigningValidatorSnapshot) -> String {
        let host = snapshot.legacyMiniProgramHostRejected ? "旧小程序 IP 已拦截" : "存在旧 IP 风险"
        let realm = snapshot.sessionRealmMatchesMarketPrefix ? "cn-/us- 存储域已对齐" : "存储域前缀不匹配"
        return "域名与会话域隔离：\(host) · \(realm)"
    }
}

@MainActor
private struct XcconfigCoordinateRowView: View {
    let row: XcconfigCoordinateRow

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(verbatim: row.settingKey)
                    .font(.subheadline.bold())
                Spacer()
                Text(verbatim: row.isCoordinateValid ? "就绪" : "告警")
                    .font(.caption)
                    .foregroundStyle(row.isCoordinateValid ? .green : .red)
            }

            Text(verbatim: "Base 默认：\(row.baseFailClosedDefault)")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(verbatim: "Day-3 归档要求：\(row.localReleaseRequirement)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("productionSigningValidator.row")
    }
}
