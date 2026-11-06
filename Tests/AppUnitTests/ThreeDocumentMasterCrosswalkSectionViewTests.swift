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
final class ThreeDocumentMasterCrosswalkSectionViewTests: XCTestCase {
    func testDefaultMasterCrosswalkCoversAllThreeCanonicalDocumentsAndIsFullyAligned() {
        let snapshot = ThreeDocumentCrosswalkSnapshot.defaultMasterCrosswalk
        XCTAssertTrue(snapshot.coversAllThreeCanonicalDocuments)
        XCTAssertTrue(snapshot.isFullyAligned)
        XCTAssertEqual(snapshot.rows.map(\.documentName), [
            "交接文档_20261020.md",
            "落地清单.md",
            "工单-统一实施版.md"
        ])
        XCTAssertEqual(snapshot.alignedCount, 3)
        XCTAssertEqual(snapshot.gatedCount, 0)
        XCTAssertEqual(snapshot.driftCount, 0)
        XCTAssertEqual(snapshot.summaryText, "已对齐 3/3 · 受控门禁 0 · 偏差 0")

        let view = ThreeDocumentMasterCrosswalkSectionView(snapshot: snapshot)
        _ = view.body
        XCTAssertEqual(view.snapshot, snapshot)
    }

    func testCustomSnapshotDetectsGatedAndDriftStates() {
        let customRows: [MasterDocumentCrosswalkRow] = [
            MasterDocumentCrosswalkRow(
                id: "handover-20261020",
                documentName: "交接文档_20261020.md",
                scopeSummary: "构建与签名基线",
                coveredTicketsText: "Base.xcconfig",
                state: .aligned,
                verificationEvidence: "通过"
            ),
            MasterDocumentCrosswalkRow(
                id: "landing-checklist",
                documentName: "落地清单.md",
                scopeSummary: "分包页面对标",
                coveredTicketsText: "w1/w2",
                state: .gatedPendingBackend,
                verificationEvidence: "后端接口待开放"
            ),
            MasterDocumentCrosswalkRow(
                id: "unified-workorders",
                documentName: "工单-统一实施版.md",
                scopeSummary: "改革方案工单",
                coveredTicketsText: "W13..W21",
                state: .driftDetected,
                verificationEvidence: "存在未对齐字段"
            )
        ]
        let snapshot = ThreeDocumentCrosswalkSnapshot(rows: customRows)
        XCTAssertTrue(snapshot.coversAllThreeCanonicalDocuments)
        XCTAssertFalse(snapshot.isFullyAligned)
        XCTAssertEqual(snapshot.alignedCount, 1)
        XCTAssertEqual(snapshot.gatedCount, 1)
        XCTAssertEqual(snapshot.driftCount, 1)
        XCTAssertEqual(customRows.map(\.badgeText), ["ALIGNED", "GATED", "DRIFT"])

        let view = ThreeDocumentMasterCrosswalkSectionView(snapshot: snapshot)
        _ = view.body
        XCTAssertEqual(view.snapshot.summaryText, "已对齐 1/3 · 受控门禁 1 · 偏差 1")
    }
}
