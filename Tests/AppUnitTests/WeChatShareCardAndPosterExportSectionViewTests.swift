import XCTest
import SwiftUI
#if canImport(QuestifyApp)
@testable import QuestifyApp
import QuestifyCore
#else
@testable import Questify
#endif

@MainActor
final class WeChatShareCardAndPosterExportSectionViewTests: XCTestCase {
    func testDefaultReadySnapshotPassesGoneSeparationAnd3xExportChecks() {
        let snapshot = ShareCardPosterExportSnapshot.defaultReady
        XCTAssertTrue(snapshot.isAllCompliant)
        XCTAssertEqual(snapshot.compliantRowCount, 3)
        XCTAssertTrue(snapshot.rows.allSatisfy(\.isSurfaceCompliant))

        XCTAssertEqual(
            WeChatShareCardAndPosterExportSectionView.overallStatusText(for: snapshot),
            "整体状态：分享卡片与 @3x 海报导出链路全部就绪（3/3）"
        )
        XCTAssertEqual(
            WeChatShareCardAndPosterExportSectionView.statusSeparationText(for: snapshot),
            "状态码严格区分：404/410 映射 .gone（终态无重试） · 503 映射 .error（可重试）"
        )
        XCTAssertEqual(
            WeChatShareCardAndPosterExportSectionView.posterScaleStatusText(for: snapshot),
            "海报导出规格：固定 @3x 渲染精度且仅按用户手势写入相册"
        )
        XCTAssertEqual(
            WeChatShareCardAndPosterExportSectionView.qrDeepLinkStatusText(for: snapshot),
            "二维码深链安全：内嵌公开深链且剥离会话凭证与私人坐标"
        )
    }

    func testConflated404And503OrNon3xPosterTriggersWarningState() {
        var rows = ShareCardPosterExportSnapshot.defaultReady.rows
        rows[0] = SharePosterSurfaceRow(
            id: "roam-share-snapshot-card",
            surfaceTitle: "漫游战报分享卡 (/api/roam/share/snapshot)",
            separates404Or410GoneFrom503Error: false,
            rendersAt3xScale: false,
            embedsSanitizedQRDeepLink: false,
            summary: "违规配置：混淆 404 与 503 状态且未按 @3x 导出海报"
        )
        XCTAssertFalse(rows[0].isSurfaceCompliant)

        let warningSnapshot = ShareCardPosterExportSnapshot(
            separatesGone404Or410From503Error: false,
            exportsPosterAt3xScale: false,
            embedsSanitizedQRDeepLink: false,
            stripsPrivateCoordinatesAndTokensFromPoster: false,
            rows: rows
        )
        XCTAssertFalse(warningSnapshot.isAllCompliant)
        XCTAssertEqual(warningSnapshot.compliantRowCount, 2)
        XCTAssertEqual(
            WeChatShareCardAndPosterExportSectionView.overallStatusText(for: warningSnapshot),
            "整体状态：存在 404/503 状态混淆或海报导出配置缺失（2/3）"
        )
        XCTAssertEqual(
            WeChatShareCardAndPosterExportSectionView.statusSeparationText(for: warningSnapshot),
            "状态码混淆告警：404/410 .gone 与 503 .error 未严格区分"
        )
        XCTAssertEqual(
            WeChatShareCardAndPosterExportSectionView.posterScaleStatusText(for: warningSnapshot),
            "海报导出规格：未固定 @3x 渲染精度"
        )
        XCTAssertEqual(
            WeChatShareCardAndPosterExportSectionView.qrDeepLinkStatusText(for: warningSnapshot),
            "二维码深链告警：二维码深链缺失或未完成敏感参数剥离"
        )
    }

    func testMainActorViewBodyInstantiationForReadyAndEmptySnapshots() {
        let readyView = WeChatShareCardAndPosterExportSectionView(snapshot: .defaultReady)
        XCTAssertEqual(readyView.snapshot.rows.count, 3)
        _ = readyView.body

        let emptySnapshot = ShareCardPosterExportSnapshot(
            separatesGone404Or410From503Error: true,
            exportsPosterAt3xScale: true,
            embedsSanitizedQRDeepLink: true,
            stripsPrivateCoordinatesAndTokensFromPoster: true,
            rows: []
        )
        XCTAssertFalse(emptySnapshot.isAllCompliant)
        let emptyView = WeChatShareCardAndPosterExportSectionView(snapshot: emptySnapshot)
        XCTAssertTrue(emptyView.snapshot.rows.isEmpty)
        _ = emptyView.body
    }
}
