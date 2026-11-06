import SwiftUI
#if canImport(QuestifyCore)
import QuestifyCore
#elseif canImport(Core)
import Core
#endif

/// Self-contained row describing an operation class's retry, backoff, and `Retry-After` policy.
public struct NetworkRetryPolicyRow: Sendable, Equatable, Identifiable {
    public let id: String
    public let categoryTitle: String
    public let isIdempotentReadOrStableIntent: Bool
    public let automaticRetryAllowed: Bool
    public let honorsServerRetryAfterHeader: Bool
    public let maxAttempts: Int
    public let summary: String

    public init(
        id: String,
        categoryTitle: String,
        isIdempotentReadOrStableIntent: Bool,
        automaticRetryAllowed: Bool,
        honorsServerRetryAfterHeader: Bool,
        maxAttempts: Int,
        summary: String
    ) {
        self.id = id
        self.categoryTitle = categoryTitle
        self.isIdempotentReadOrStableIntent = isIdempotentReadOrStableIntent
        self.automaticRetryAllowed = automaticRetryAllowed
        self.honorsServerRetryAfterHeader = honorsServerRetryAfterHeader
        self.maxAttempts = maxAttempts
        self.summary = summary
    }

    /// Non-idempotent writes must never auto-retry (`automaticRetryAllowed == false` and `maxAttempts == 1`);
    /// idempotent reads or stable-requestId intents must honor `Retry-After` and bounded attempts (`1...3`).
    public var isPolicySafe: Bool {
        guard honorsServerRetryAfterHeader, (1...3).contains(maxAttempts) else { return false }
        if !isIdempotentReadOrStableIntent {
            return !automaticRetryAllowed && maxAttempts == 1
        }
        return true
    }
}

/// Self-contained snapshot for `NWPathMonitor` reachability status, idempotent vs non-idempotent
/// retry safety, and HTTP 429/503 `Retry-After` backoff compliance.
public struct NetworkReachabilityRetrySnapshot: Sendable, Equatable {
    public let pathMonitorActive: Bool
    public let isConstrainedOrExpensiveAware: Bool
    public let nonIdempotentWritesNeverAutoRetried: Bool
    public let respectsServerRetryAfterHeader: Bool
    public let rows: [NetworkRetryPolicyRow]

    public init(
        pathMonitorActive: Bool,
        isConstrainedOrExpensiveAware: Bool,
        nonIdempotentWritesNeverAutoRetried: Bool,
        respectsServerRetryAfterHeader: Bool,
        rows: [NetworkRetryPolicyRow]
    ) {
        self.pathMonitorActive = pathMonitorActive
        self.isConstrainedOrExpensiveAware = isConstrainedOrExpensiveAware
        self.nonIdempotentWritesNeverAutoRetried = nonIdempotentWritesNeverAutoRetried
        self.respectsServerRetryAfterHeader = respectsServerRetryAfterHeader
        self.rows = rows
    }

    public var safeRowCount: Int {
        rows.filter(\.isPolicySafe).count
    }

    public var isAllSafe: Bool {
        pathMonitorActive &&
            isConstrainedOrExpensiveAware &&
            nonIdempotentWritesNeverAutoRetried &&
            respectsServerRetryAfterHeader &&
            !rows.isEmpty &&
            rows.allSatisfy(\.isPolicySafe)
    }

    public static let defaultReady = NetworkReachabilityRetrySnapshot(
        pathMonitorActive: true,
        isConstrainedOrExpensiveAware: true,
        nonIdempotentWritesNeverAutoRetried: true,
        respectsServerRetryAfterHeader: true,
        rows: [
            NetworkRetryPolicyRow(
                id: "read-only-queries",
                categoryTitle: "只读查询请求 (GET/Read)",
                isIdempotentReadOrStableIntent: true,
                automaticRetryAllowed: true,
                honorsServerRetryAfterHeader: true,
                maxAttempts: 3,
                summary: "支持指数退避与抖动重试（上限 3 次），严格遵守服务端 Retry-After"
            ),
            NetworkRetryPolicyRow(
                id: "idempotent-request-id-writes",
                categoryTitle: "带固定 requestId 的幂等提交",
                isIdempotentReadOrStableIntent: true,
                automaticRetryAllowed: false,
                honorsServerRetryAfterHeader: true,
                maxAttempts: 1,
                summary: "网络结果未知时先回读回执，仅允许用户显式触发同一 requestId 重试"
            ),
            NetworkRetryPolicyRow(
                id: "non-idempotent-mutations",
                categoryTitle: "非幂等写操作 (治理/审核/发布)",
                isIdempotentReadOrStableIntent: false,
                automaticRetryAllowed: false,
                honorsServerRetryAfterHeader: true,
                maxAttempts: 1,
                summary: "单次发送且严禁自动重放（maxAttempts = 1），失败后锁定或引导只读重新核对"
            )
        ]
    )
}

@MainActor
public struct NetworkReachabilityAndRetryBackoffSectionView: View {
    public let snapshot: NetworkReachabilityRetrySnapshot

    public init(snapshot: NetworkReachabilityRetrySnapshot = .defaultReady) {
        self.snapshot = snapshot
    }

    public var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: "网络可达性与退避重试安全审计")
                    .font(.headline)
                    .accessibilityIdentifier("networkReachabilityRetry.title")

                Text(verbatim: Self.overallStatusText(for: snapshot))
                    .font(.subheadline)
                    .foregroundStyle(snapshot.isAllSafe ? .green : .red)
                    .accessibilityIdentifier("networkReachabilityRetry.overallStatus")

                Text(verbatim: Self.reachabilityStatusText(for: snapshot))
                    .font(.footnote)
                    .accessibilityIdentifier("networkReachabilityRetry.reachabilityStatus")

                Text(verbatim: Self.retrySafetyStatusText(for: snapshot))
                    .font(.footnote)
                    .accessibilityIdentifier("networkReachabilityRetry.retrySafetyStatus")

                Text(verbatim: Self.retryAfterStatusText(for: snapshot))
                    .font(.footnote)
                    .accessibilityIdentifier("networkReachabilityRetry.retryAfterStatus")
            }
            .padding(.vertical, 4)

            if snapshot.rows.isEmpty {
                Text(verbatim: "暂无网络退避与重试策略检查项")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("networkReachabilityRetry.empty")
            } else {
                ForEach(snapshot.rows) { row in
                    NetworkRetryPolicyRowView(row: row)
                }
            }
        }
        .accessibilityIdentifier("networkReachabilityRetry.section")
    }

    public static func overallStatusText(for snapshot: NetworkReachabilityRetrySnapshot) -> String {
        snapshot.isAllSafe
            ? "整体状态：网络可达性与重试策略全部安全就绪（\(snapshot.safeRowCount)/\(snapshot.rows.count)）"
            : "整体状态：检测到不安全的重试策略或可达性缺失（\(snapshot.safeRowCount)/\(snapshot.rows.count)）"
    }

    public static func reachabilityStatusText(for snapshot: NetworkReachabilityRetrySnapshot) -> String {
        let monitor = snapshot.pathMonitorActive ? "NWPathMonitor 已激活" : "NWPathMonitor 未激活"
        let constrained = snapshot.isConstrainedOrExpensiveAware ? "低数据/受限网络感知已开启" : "受限网络感知未开启"
        return "可达性监控：\(monitor) · \(constrained)"
    }

    public static func retrySafetyStatusText(for snapshot: NetworkReachabilityRetrySnapshot) -> String {
        snapshot.nonIdempotentWritesNeverAutoRetried
            ? "写操作防重放：非幂等写请求严禁自动重试已核验"
            : "写操作防重放：存在非幂等写请求被自动重放的风险"
    }

    public static func retryAfterStatusText(for snapshot: NetworkReachabilityRetrySnapshot) -> String {
        snapshot.respectsServerRetryAfterHeader
            ? "Retry-After 合规：429/503 服务端冷却时间窗口严格遵守"
            : "Retry-After 合规：未遵守服务端冷却时间窗口"
    }
}

@MainActor
private struct NetworkRetryPolicyRowView: View {
    let row: NetworkRetryPolicyRow

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(verbatim: row.categoryTitle)
                    .font(.subheadline.bold())
                Spacer()
                Text(verbatim: row.isPolicySafe ? "安全" : "告警")
                    .font(.caption)
                    .foregroundStyle(row.isPolicySafe ? .green : .red)
            }

            Text(verbatim: row.summary)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(verbatim: "最大尝试：\(row.maxAttempts) 次 · 自动重试：\(row.automaticRetryAllowed ? "允许" : "禁止") · Retry-After：\(row.honorsServerRetryAfterHeader ? "遵守" : "忽略")")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("networkReachabilityRetry.row")
    }
}
