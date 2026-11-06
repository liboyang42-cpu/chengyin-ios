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
final class XcodeGenAndScaffoldDiagnosticsSectionViewTests: XCTestCase {
    func testCompliantSampleSnapshotCoversAllFiveTargets() {
        let snapshot = XcodeGenScaffoldSnapshot.compliantSample
        XCTAssertTrue(snapshot.isAllCompliant)
        XCTAssertEqual(snapshot.compliantTargetCount, 5)
        XCTAssertEqual(snapshot.rows.map(\.target), XcodeTargetScaffoldRow.TargetKind.allCases)

        let view = XcodeGenAndScaffoldDiagnosticsSectionView(snapshot: snapshot)
        XCTAssertEqual(
            XcodeGenAndScaffoldDiagnosticsSectionView.overallStatusText(for: snapshot),
            "整体状态：五大工程 Target 与脚手架校验全部通过（5/5）"
        )
        XCTAssertEqual(
            XcodeGenAndScaffoldDiagnosticsSectionView.pbxprojStatusText(for: snapshot),
            "工程等价性：project.pbxproj 与 generate_project.py 语义完全一致"
        )
        XCTAssertEqual(
            XcodeGenAndScaffoldDiagnosticsSectionView.catalogStatusText(for: snapshot),
            "双语词表：en / zh-Hans 词条完整且无未注册表引用"
        )
        XCTAssertEqual(
            XcodeGenAndScaffoldDiagnosticsSectionView.signingAndAtsStatusText(for: snapshot),
            "安全基线：无证书/私钥残留 · ATS 严格启用"
        )
        _ = view.body
    }

    func testDriftedPbxprojOrDuplicateBasenameFailsClosed() {
        let rows: [XcodeTargetScaffoldRow] = [
            XcodeTargetScaffoldRow(
                target: .questifyCore,
                sourceFolder: "Core",
                registeredFileCount: 280,
                uniqueBasenamesVerified: true,
                schemeBuildableReferenceValid: true
            ),
            XcodeTargetScaffoldRow(
                target: .questifyApp,
                sourceFolder: "App",
                registeredFileCount: 240,
                uniqueBasenamesVerified: false,
                schemeBuildableReferenceValid: true
            ),
            XcodeTargetScaffoldRow(
                target: .questifyCoreTests,
                sourceFolder: "Tests/CoreTests",
                registeredFileCount: 210,
                uniqueBasenamesVerified: true,
                schemeBuildableReferenceValid: true
            ),
            XcodeTargetScaffoldRow(
                target: .questifyAppUnitTests,
                sourceFolder: "Tests/AppUnitTests",
                registeredFileCount: 145,
                uniqueBasenamesVerified: true,
                schemeBuildableReferenceValid: false
            ),
            XcodeTargetScaffoldRow(
                target: .questifyUITests,
                sourceFolder: "Tests/AppUITests",
                registeredFileCount: 38,
                uniqueBasenamesVerified: true,
                schemeBuildableReferenceValid: true
            )
        ]

        let nonCompliant = XcodeGenScaffoldSnapshot(
            pbxprojSemanticEquivalenceVerified: false,
            bilingualCatalogComplete: false,
            noForbiddenSigningArtifacts: true,
            atsStrictnessVerified: true,
            rows: rows
        )
        XCTAssertFalse(nonCompliant.isAllCompliant)
        XCTAssertEqual(nonCompliant.compliantTargetCount, 3)
        XCTAssertEqual(
            XcodeGenAndScaffoldDiagnosticsSectionView.overallStatusText(for: nonCompliant),
            "整体状态：存在未通过的工程 Target 或脚手架检查项（3/5）"
        )
        XCTAssertEqual(
            XcodeGenAndScaffoldDiagnosticsSectionView.pbxprojStatusText(for: nonCompliant),
            "工程等价性：project.pbxproj 与生成器输出存在偏差"
        )
        XCTAssertEqual(
            XcodeGenAndScaffoldDiagnosticsSectionView.catalogStatusText(for: nonCompliant),
            "双语词表：存在缺失翻译或未注册的词表键"
        )

        let view = XcodeGenAndScaffoldDiagnosticsSectionView(snapshot: nonCompliant)
        _ = view.body
    }

    func testEmptyRowsSnapshotIsNotCompliantAndRendersEmptyState() {
        let emptySnapshot = XcodeGenScaffoldSnapshot(
            pbxprojSemanticEquivalenceVerified: true,
            bilingualCatalogComplete: true,
            noForbiddenSigningArtifacts: true,
            atsStrictnessVerified: true,
            rows: []
        )
        XCTAssertFalse(emptySnapshot.isAllCompliant)
        XCTAssertEqual(emptySnapshot.compliantTargetCount, 0)

        let view = XcodeGenAndScaffoldDiagnosticsSectionView(snapshot: emptySnapshot)
        XCTAssertTrue(view.snapshot.rows.isEmpty)
        _ = view.body
    }
}
