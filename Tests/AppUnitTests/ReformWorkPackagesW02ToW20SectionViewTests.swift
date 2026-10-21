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
final class ReformWorkPackagesW02ToW20SectionViewTests: XCTestCase {
    func testDefaultSnapshotCoversAllNineteenWorkPackagesAcrossDomainsFGAndH() {
        let snapshot = ReformWorkPackagesW02ToW20Snapshot.defaultAllNineteenPackages
        XCTAssertEqual(ReformWorkPackagesW02ToW20Snapshot.canonicalPackageIDs.count, 19)
        XCTAssertEqual(ReformWorkPackagesW02ToW20Snapshot.canonicalPackageIDs.first, "W02")
        XCTAssertEqual(ReformWorkPackagesW02ToW20Snapshot.canonicalPackageIDs.last, "W20")
        XCTAssertTrue(snapshot.coversAllNineteenPackages)
        XCTAssertTrue(snapshot.isFullyReady)
        XCTAssertEqual(snapshot.totalCoveredCount, 19)
        XCTAssertEqual(snapshot.rows.map(\.domain), [.domainF, .domainG, .domainH])
        XCTAssertEqual(snapshot.summaryText, "已覆盖工作包 19/19 (W02..W20) · 领域 3 个")

        let view = ReformWorkPackagesW02ToW20SectionView(snapshot: snapshot)
        _ = view.body
        XCTAssertEqual(view.snapshot, snapshot)
    }

    func testPartialSnapshotDetectsMissingPackagesAndNonReadyState() {
        let partialRows: [ReformPackageDomainSummaryRow] = [
            ReformPackageDomainSummaryRow(
                id: "domain-f",
                domain: .domainF,
                title: "Domain F",
                packageIDs: ["W13", "W14", "W15"],
                state: .gatedPendingBackend,
                detail: "Partial F"
            ),
            ReformPackageDomainSummaryRow(
                id: "domain-g",
                domain: .domainG,
                title: "Domain G",
                packageIDs: ["W16", "W17", "W18"],
                state: .contractAndHostComplete,
                detail: "Partial G"
            )
        ]
        let snapshot = ReformWorkPackagesW02ToW20Snapshot(rows: partialRows)
        XCTAssertFalse(snapshot.coversAllNineteenPackages)
        XCTAssertFalse(snapshot.isFullyReady)
        XCTAssertEqual(snapshot.totalCoveredCount, 6)
        XCTAssertEqual(partialRows.map(\.badgeText), ["GATED", "100% READY"])

        let view = ReformWorkPackagesW02ToW20SectionView(snapshot: snapshot)
        _ = view.body
        XCTAssertEqual(view.snapshot.summaryText, "已覆盖工作包 6/19 (W02..W20) · 领域 2 个")
    }
}
