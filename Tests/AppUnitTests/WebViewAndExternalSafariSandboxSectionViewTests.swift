import XCTest
import SwiftUI
#if canImport(QuestifyApp)
@testable import QuestifyApp
import QuestifyCore
#else
@testable import Questify
#endif

@MainActor
final class WebViewAndExternalSafariSandboxSectionViewTests: XCTestCase {
    func testDefaultReadySnapshotPassesAllSandboxAndATSChecks() {
        let snapshot = WebViewSandboxSnapshot.defaultReady
        XCTAssertTrue(snapshot.isAllSafe)
        XCTAssertEqual(snapshot.safeRowCount, 3)
        XCTAssertTrue(snapshot.rows.allSatisfy(\.isContainerSafe))

        XCTAssertEqual(
            WebViewAndExternalSafariSandboxSectionView.overallStatusText(for: snapshot),
            "整体状态：网页与外部链接沙箱策略全部安全就绪（3/3）"
        )
        XCTAssertEqual(
            WebViewAndExternalSafariSandboxSectionView.atsStatusText(for: snapshot),
            "HTTPS / ATS 合规：强制 HTTPS 且无 NSAllowsArbitraryLoads 豁免"
        )
        XCTAssertEqual(
            WebViewAndExternalSafariSandboxSectionView.jsBridgeStatusText(for: snapshot),
            "脚本与容器隔离：未授信 JS Bridge 已隔离 · H5 容器未挂载"
        )
        XCTAssertEqual(
            WebViewAndExternalSafariSandboxSectionView.tokenRedactionStatusText(for: snapshot),
            "URL 凭证脱敏：查询参数 token / ticket 剥离已启用"
        )
    }

    func testInsecureContainerOrUnredactedQueryTokenFailsClosed() {
        let insecureRow = WebContainerPolicyRow(
            id: "insecure-webview",
            containerTitle: "未隔离网页容器",
            enforcesHTTPSOnly: false,
            untrustedJSBridgeDisabled: false,
            redactsQueryAuthTokens: false,
            h5ModPackageRejected: false,
            summary: "违规配置：开放未授信脚本桥接且未剥离 URL Token"
        )
        XCTAssertFalse(insecureRow.isContainerSafe)

        let safeRow = WebContainerPolicyRow(
            id: "safe-safari",
            containerTitle: "合规外部链接",
            enforcesHTTPSOnly: true,
            untrustedJSBridgeDisabled: true,
            redactsQueryAuthTokens: true,
            h5ModPackageRejected: true,
            summary: "安全跳转"
        )
        XCTAssertTrue(safeRow.isContainerSafe)

        let warningSnapshot = WebViewSandboxSnapshot(
            atsStrictHTTPSVerified: false,
            untrustedJSBridgeIsolated: false,
            urlQueryTokensRedacted: false,
            h5RuntimeContainerAbsent: false,
            rows: [insecureRow, safeRow]
        )
        XCTAssertFalse(warningSnapshot.isAllSafe)
        XCTAssertEqual(warningSnapshot.safeRowCount, 1)
        XCTAssertEqual(
            WebViewAndExternalSafariSandboxSectionView.overallStatusText(for: warningSnapshot),
            "整体状态：检测到不安全的网页容器或外部链接策略（1/2）"
        )
        XCTAssertEqual(
            WebViewAndExternalSafariSandboxSectionView.atsStatusText(for: warningSnapshot),
            "HTTPS / ATS 合规：存在非 HTTPS 或 ATS 豁免风险"
        )
        XCTAssertEqual(
            WebViewAndExternalSafariSandboxSectionView.tokenRedactionStatusText(for: warningSnapshot),
            "URL 凭证脱敏：存在查询参数泄漏凭证风险"
        )
    }

    func testMainActorViewBodyInstantiationForReadyAndEmptySnapshots() {
        let readyView = WebViewAndExternalSafariSandboxSectionView(snapshot: .defaultReady)
        XCTAssertEqual(readyView.snapshot.rows.count, 3)
        _ = readyView.body

        let emptySnapshot = WebViewSandboxSnapshot(
            atsStrictHTTPSVerified: true,
            untrustedJSBridgeIsolated: true,
            urlQueryTokensRedacted: true,
            h5RuntimeContainerAbsent: true,
            rows: []
        )
        XCTAssertFalse(emptySnapshot.isAllSafe)
        let emptyView = WebViewAndExternalSafariSandboxSectionView(snapshot: emptySnapshot)
        XCTAssertTrue(emptyView.snapshot.rows.isEmpty)
        _ = emptyView.body
    }
}
