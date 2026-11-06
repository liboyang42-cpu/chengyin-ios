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
final class ProductionSigningAndLocalXcconfigSectionViewTests: XCTestCase {
    func testDefaultReadySnapshotCoversAllFiveXcconfigCoordinates() {
        let snapshot = ProductionSigningValidatorSnapshot.defaultReady
        XCTAssertTrue(snapshot.isAllValid)
        XCTAssertEqual(snapshot.validCoordinateCount, 5)
        XCTAssertEqual(snapshot.rows.map(\.settingKey), [
            "DEVELOPMENT_TEAM",
            "PRODUCT_BUNDLE_IDENTIFIER",
            "QUESTIFY_MARKET",
            "QUESTIFY_API_BASE_URL",
            "QUESTIFY_SESSION_REALM"
        ])
        XCTAssertTrue(snapshot.rows.allSatisfy(\.isCoordinateValid))

        XCTAssertEqual(
            ProductionSigningAndLocalXcconfigSectionView.overallStatusText(for: snapshot),
            "整体状态：五大 xcconfig 归档坐标与生产签名校验全部通过（5/5）"
        )
        XCTAssertEqual(
            ProductionSigningAndLocalXcconfigSectionView.baseDefaultsStatusText(for: snapshot),
            "Config/Base.xcconfig：占位 Bundle ID 与空 API/Realm 默认关闭基线已核验"
        )
        XCTAssertEqual(
            ProductionSigningAndLocalXcconfigSectionView.localSigningStatusText(for: snapshot),
            "Config/Local.xcconfig：Day-3 归档签名已配置且未纳入版本库"
        )
        XCTAssertEqual(
            ProductionSigningAndLocalXcconfigSectionView.hostAndRealmStatusText(for: snapshot),
            "域名与会话域隔离：旧小程序 IP 已拦截 · cn-/us- 存储域已对齐"
        )
    }

    func testPlaceholderBundleOrLegacyHostTriggersWarningState() {
        var rows = ProductionSigningValidatorSnapshot.defaultReady.rows
        rows[1] = XcconfigCoordinateRow(
            id: "product-bundle-identifier",
            settingKey: "PRODUCT_BUNDLE_IDENTIFIER",
            baseFailClosedDefault: "invalid.example.questify.ios",
            localReleaseRequirement: "违规：仍使用 invalid.example.questify.ios 占位符",
            isNonPlaceholderConfigured: false,
            rejectsLegacyOrCrossMarketValues: false
        )
        XCTAssertFalse(rows[1].isCoordinateValid)

        let warningSnapshot = ProductionSigningValidatorSnapshot(
            baseXcconfigFailClosedVerified: true,
            localXcconfigGitIgnoredAndSigned: false,
            legacyMiniProgramHostRejected: false,
            sessionRealmMatchesMarketPrefix: false,
            rows: rows
        )
        XCTAssertFalse(warningSnapshot.isAllValid)
        XCTAssertEqual(warningSnapshot.validCoordinateCount, 4)
        XCTAssertEqual(
            ProductionSigningAndLocalXcconfigSectionView.overallStatusText(for: warningSnapshot),
            "整体状态：检测到占位签名或未就绪的 xcconfig 归档坐标（4/5）"
        )
        XCTAssertEqual(
            ProductionSigningAndLocalXcconfigSectionView.localSigningStatusText(for: warningSnapshot),
            "Config/Local.xcconfig：仍处于未签名或占位 Bundle ID 状态"
        )
        XCTAssertEqual(
            ProductionSigningAndLocalXcconfigSectionView.hostAndRealmStatusText(for: warningSnapshot),
            "域名与会话域隔离：存在旧 IP 风险 · 存储域前缀不匹配"
        )
    }

    func testMainActorViewBodyInstantiationForReadyAndEmptySnapshots() {
        let readyView = ProductionSigningAndLocalXcconfigSectionView(snapshot: .defaultReady)
        XCTAssertEqual(readyView.snapshot.rows.count, 5)
        _ = readyView.body

        let emptySnapshot = ProductionSigningValidatorSnapshot(
            baseXcconfigFailClosedVerified: true,
            localXcconfigGitIgnoredAndSigned: true,
            legacyMiniProgramHostRejected: true,
            sessionRealmMatchesMarketPrefix: true,
            rows: []
        )
        XCTAssertFalse(emptySnapshot.isAllValid)
        let emptyView = ProductionSigningAndLocalXcconfigSectionView(snapshot: emptySnapshot)
        XCTAssertTrue(emptyView.snapshot.rows.isEmpty)
        _ = emptyView.body
    }
}
