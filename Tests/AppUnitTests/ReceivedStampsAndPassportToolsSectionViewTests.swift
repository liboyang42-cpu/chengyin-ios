import XCTest
import SwiftUI
#if canImport(QuestifyApp)
@testable import QuestifyApp
import QuestifyCore
#else
@testable import Questify
#endif

@MainActor
final class ReceivedStampsAndPassportToolsSectionViewTests: XCTestCase {
    func testCompliantSampleSnapshotCoversAllFourPassportPillars() {
        let snapshot = ReceivedStampsAndPassportToolsSnapshot.compliantSample
        XCTAssertTrue(snapshot.isAllCompliant)
        XCTAssertEqual(snapshot.verifiedRowCount, 4)
        XCTAssertEqual(snapshot.rows.map(\.kind), PassportToolAuditRow.PillarKind.allCases)

        let view = ReceivedStampsAndPassportToolsSectionView(snapshot: snapshot)
        XCTAssertEqual(
            ReceivedStampsAndPassportToolsSectionView.overallStatusText(for: snapshot),
            "整体状态：印章簿与私人随身工具四大支柱全部达标（4/4）"
        )
        XCTAssertEqual(
            ReceivedStampsAndPassportToolsSectionView.sessionAdmissionStatusText(for: snapshot),
            "I00 会话准入：当前账号身份与角色租约已核验"
        )
        XCTAssertEqual(
            ReceivedStampsAndPassportToolsSectionView.receivedStampsStatusText(for: snapshot),
            "I11 已获印章簿：服务端只读事实与空态展示已对齐"
        )
        XCTAssertEqual(
            ReceivedStampsAndPassportToolsSectionView.privateToolsStatusText(for: snapshot),
            "w2-09 私人随身工具：本人专属作用域与隐私隔离已启用"
        )
        XCTAssertEqual(
            ReceivedStampsAndPassportToolsSectionView.nonCashHonorStatusText(for: snapshot),
            "非现金荣誉边界：印章不可提现、不可转让已核验"
        )
        _ = view.body
    }

    func testUnverifiedReceivedStampsOrPrivateToolsFailsClosed() {
        let rows: [PassportToolAuditRow] = [
            PassportToolAuditRow(
                kind: .i00SessionRoleAdmission,
                title: "I00 会话准入与角色边界核验",
                summary: "已核验",
                verificationNote: "OK",
                isVerified: true
            ),
            PassportToolAuditRow(
                kind: .i11ReceivedStampsReadOnly,
                title: "I11 已获印章簿只读回放",
                summary: "未完成服务端回读",
                verificationNote: "pending",
                isVerified: false
            ),
            PassportToolAuditRow(
                kind: .w209PrivatePassportTools,
                title: "w2-09 私人随身工具与纪念册隔离",
                summary: "缺少本人作用域校验",
                verificationNote: "missing-owner-check",
                isVerified: false
            ),
            PassportToolAuditRow(
                kind: .nonCashStampHonorBoundary,
                title: "印章与纪念物非现金荣誉边界",
                summary: "已核验",
                verificationNote: "OK",
                isVerified: true
            )
        ]

        let nonCompliant = ReceivedStampsAndPassportToolsSnapshot(
            sessionRoleAdmissionVerified: true,
            receivedStampsReadOnlyParityVerified: false,
            privatePassportToolsScopedToOwner: false,
            stampsNonCashHonorOnlyVerified: true,
            rows: rows
        )
        XCTAssertFalse(nonCompliant.isAllCompliant)
        XCTAssertEqual(nonCompliant.verifiedRowCount, 2)
        XCTAssertEqual(
            ReceivedStampsAndPassportToolsSectionView.overallStatusText(for: nonCompliant),
            "整体状态：存在未达标的印章簿或私人随身工具检查项（2/4）"
        )
        XCTAssertEqual(
            ReceivedStampsAndPassportToolsSectionView.receivedStampsStatusText(for: nonCompliant),
            "I11 已获印章簿：只读事实或空态展示待对齐"
        )
        XCTAssertEqual(
            ReceivedStampsAndPassportToolsSectionView.privateToolsStatusText(for: nonCompliant),
            "w2-09 私人随身工具：本人专属作用域或隐私隔离未启用"
        )

        let view = ReceivedStampsAndPassportToolsSectionView(snapshot: nonCompliant)
        _ = view.body
    }

    func testEmptyRowsSnapshotIsNotCompliantAndRendersEmptyState() {
        let emptySnapshot = ReceivedStampsAndPassportToolsSnapshot(
            sessionRoleAdmissionVerified: true,
            receivedStampsReadOnlyParityVerified: true,
            privatePassportToolsScopedToOwner: true,
            stampsNonCashHonorOnlyVerified: true,
            rows: []
        )
        XCTAssertFalse(emptySnapshot.isAllCompliant)
        XCTAssertEqual(emptySnapshot.verifiedRowCount, 0)

        let view = ReceivedStampsAndPassportToolsSectionView(snapshot: emptySnapshot)
        XCTAssertTrue(view.snapshot.rows.isEmpty)
        _ = view.body
    }
}
