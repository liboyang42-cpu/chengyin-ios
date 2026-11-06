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
final class ProductionTelemetryAndPrivacyRedactionSectionViewTests: XCTestCase {
    func testDefaultReadySnapshotPassesAllFourTelemetryPipelines() {
        let snapshot = TelemetryPrivacyRedactionSnapshot.defaultReady
        XCTAssertTrue(snapshot.isAllRedacted)
        XCTAssertEqual(snapshot.redactedRowCount, 4)
        XCTAssertEqual(snapshot.rows.count, 4)
        XCTAssertTrue(snapshot.rows.allSatisfy(\.isRedacted))

        XCTAssertEqual(
            ProductionTelemetryAndPrivacyRedactionSectionView.overallStatusText(for: snapshot),
            "整体状态：四大生产遥测管线隐私脱敏全部就绪（4/4）"
        )
        XCTAssertEqual(
            ProductionTelemetryAndPrivacyRedactionSectionView.tokenMaskingStatusText(for: snapshot),
            "Bearer 凭证掩码：Authorization / 会话令牌脱敏已启用"
        )
        XCTAssertEqual(
            ProductionTelemetryAndPrivacyRedactionSectionView.piiRedactionStatusText(for: snapshot),
            "PII 身份脱敏：手机号与身份标识掩码已启用"
        )
        XCTAssertEqual(
            ProductionTelemetryAndPrivacyRedactionSectionView.gpsQuantizationStatusText(for: snapshot),
            "GPS 坐标保护：精确经纬度量化与私人据点抹除已启用"
        )
        XCTAssertEqual(
            ProductionTelemetryAndPrivacyRedactionSectionView.payloadStrippingStatusText(for: snapshot),
            "正文内容剥离：聊天记录与草稿正文零落盘已核验"
        )
    }

    func testUnredactedPipelineOrDisabledMaskingTriggersWarningState() {
        var rows = TelemetryPrivacyRedactionSnapshot.defaultReady.rows
        rows[0] = TelemetryRedactionPipelineRow(
            id: "network-diagnostics-pipeline",
            pipelineTitle: "网络诊断与请求追踪管线",
            masksBearerAndAuthTokens: false,
            redactsPhoneAndIdentityNumbers: true,
            quantizesOrStripsGPSCoordinates: false,
            stripsChatAndDraftPayloads: true,
            summary: "违规配置：未掩码 Bearer Token 且输出原始 GPS"
        )
        XCTAssertFalse(rows[0].isRedacted)

        let warningSnapshot = TelemetryPrivacyRedactionSnapshot(
            bearerTokenMaskingEnabled: false,
            phoneAndIdRedactionEnabled: true,
            gpsCoordinateQuantizationEnabled: false,
            chatAndDraftBodyStrippingEnabled: false,
            rows: rows
        )
        XCTAssertFalse(warningSnapshot.isAllRedacted)
        XCTAssertEqual(warningSnapshot.redactedRowCount, 3)
        XCTAssertEqual(
            ProductionTelemetryAndPrivacyRedactionSectionView.overallStatusText(for: warningSnapshot),
            "整体状态：检测到未脱敏的生产遥测管线或字段（3/4）"
        )
        XCTAssertEqual(
            ProductionTelemetryAndPrivacyRedactionSectionView.tokenMaskingStatusText(for: warningSnapshot),
            "Bearer 凭证掩码：存在会话令牌明文输出风险"
        )
        XCTAssertEqual(
            ProductionTelemetryAndPrivacyRedactionSectionView.gpsQuantizationStatusText(for: warningSnapshot),
            "GPS 坐标保护：存在精确经纬度写入日志风险"
        )
        XCTAssertEqual(
            ProductionTelemetryAndPrivacyRedactionSectionView.payloadStrippingStatusText(for: warningSnapshot),
            "正文内容剥离：存在聊天或草稿正文写入遥测风险"
        )
    }

    func testMainActorViewBodyInstantiationForReadyAndEmptySnapshots() {
        let readyView = ProductionTelemetryAndPrivacyRedactionSectionView(snapshot: .defaultReady)
        XCTAssertEqual(readyView.snapshot.rows.count, 4)
        _ = readyView.body

        let emptySnapshot = TelemetryPrivacyRedactionSnapshot(
            bearerTokenMaskingEnabled: true,
            phoneAndIdRedactionEnabled: true,
            gpsCoordinateQuantizationEnabled: true,
            chatAndDraftBodyStrippingEnabled: true,
            rows: []
        )
        XCTAssertFalse(emptySnapshot.isAllRedacted)
        let emptyView = ProductionTelemetryAndPrivacyRedactionSectionView(snapshot: emptySnapshot)
        XCTAssertTrue(emptyView.snapshot.rows.isEmpty)
        _ = emptyView.body
    }
}
