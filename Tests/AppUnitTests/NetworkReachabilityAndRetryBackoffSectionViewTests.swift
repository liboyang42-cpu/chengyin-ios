import XCTest
import SwiftUI
#if canImport(QuestifyApp)
@testable import QuestifyApp
#if canImport(QuestifyCore)
import QuestifyCore
#elseif canImport(Core)
import Core
#endif
#else
@testable import Questify
#endif

@MainActor
final class NetworkReachabilityAndRetryBackoffSectionViewTests: XCTestCase {
    func testDefaultReadySnapshotPassesAllReachabilityAndRetrySafetyChecks() {
        let snapshot = NetworkReachabilityRetrySnapshot.defaultReady
        XCTAssertTrue(snapshot.isAllSafe)
        XCTAssertEqual(snapshot.safeRowCount, 3)
        XCTAssertTrue(snapshot.rows.allSatisfy(\.isPolicySafe))

        XCTAssertEqual(
            NetworkReachabilityAndRetryBackoffSectionView.overallStatusText(for: snapshot),
            "整体状态：网络可达性与重试策略全部安全就绪（3/3）"
        )
        XCTAssertEqual(
            NetworkReachabilityAndRetryBackoffSectionView.reachabilityStatusText(for: snapshot),
            "可达性监控：NWPathMonitor 已激活 · 低数据/受限网络感知已开启"
        )
        XCTAssertEqual(
            NetworkReachabilityAndRetryBackoffSectionView.retrySafetyStatusText(for: snapshot),
            "写操作防重放：非幂等写请求严禁自动重试已核验"
        )
        XCTAssertEqual(
            NetworkReachabilityAndRetryBackoffSectionView.retryAfterStatusText(for: snapshot),
            "Retry-After 合规：429/503 服务端冷却时间窗口严格遵守"
        )
    }

    func testUnsafeNonIdempotentAutoRetryOrIgnoredRetryAfterFailsClosed() {
        let unsafeWriteRow = NetworkRetryPolicyRow(
            id: "unsafe-write",
            categoryTitle: "非幂等写操作",
            isIdempotentReadOrStableIntent: false,
            automaticRetryAllowed: true,
            honorsServerRetryAfterHeader: false,
            maxAttempts: 3,
            summary: "违规配置：允许自动重试非幂等写操作"
        )
        XCTAssertFalse(unsafeWriteRow.isPolicySafe)

        let safeReadRow = NetworkRetryPolicyRow(
            id: "safe-read",
            categoryTitle: "只读查询请求",
            isIdempotentReadOrStableIntent: true,
            automaticRetryAllowed: true,
            honorsServerRetryAfterHeader: true,
            maxAttempts: 2,
            summary: "安全只读重试"
        )
        XCTAssertTrue(safeReadRow.isPolicySafe)

        let unsafeSnapshot = NetworkReachabilityRetrySnapshot(
            pathMonitorActive: true,
            isConstrainedOrExpensiveAware: false,
            nonIdempotentWritesNeverAutoRetried: false,
            respectsServerRetryAfterHeader: false,
            rows: [unsafeWriteRow, safeReadRow]
        )
        XCTAssertFalse(unsafeSnapshot.isAllSafe)
        XCTAssertEqual(unsafeSnapshot.safeRowCount, 1)
        XCTAssertEqual(
            NetworkReachabilityAndRetryBackoffSectionView.overallStatusText(for: unsafeSnapshot),
            "整体状态：检测到不安全的重试策略或可达性缺失（1/2）"
        )
        XCTAssertEqual(
            NetworkReachabilityAndRetryBackoffSectionView.retrySafetyStatusText(for: unsafeSnapshot),
            "写操作防重放：存在非幂等写请求被自动重放的风险"
        )
        XCTAssertEqual(
            NetworkReachabilityAndRetryBackoffSectionView.retryAfterStatusText(for: unsafeSnapshot),
            "Retry-After 合规：未遵守服务端冷却时间窗口"
        )
    }

    func testMainActorViewBodyInstantiationForReadyAndEmptySnapshots() {
        let readyView = NetworkReachabilityAndRetryBackoffSectionView(snapshot: .defaultReady)
        XCTAssertEqual(readyView.snapshot.rows.count, 3)
        _ = readyView.body

        let emptySnapshot = NetworkReachabilityRetrySnapshot(
            pathMonitorActive: true,
            isConstrainedOrExpensiveAware: true,
            nonIdempotentWritesNeverAutoRetried: true,
            respectsServerRetryAfterHeader: true,
            rows: []
        )
        XCTAssertFalse(emptySnapshot.isAllSafe)
        let emptyView = NetworkReachabilityAndRetryBackoffSectionView(snapshot: emptySnapshot)
        XCTAssertTrue(emptyView.snapshot.rows.isEmpty)
        _ = emptyView.body
    }
}
