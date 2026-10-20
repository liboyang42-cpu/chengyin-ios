import SwiftUI
import XCTest
#if canImport(QuestifyApp)
@testable import QuestifyApp
#else
@testable import Questify
#endif
#if canImport(QuestifyCore)
import QuestifyCore
#endif

@MainActor
final class LocalizationCompletenessSectionViewTests: XCTestCase {
    func testDefaultSnapshotCoversRequiredCatalogsWithZeroMissingKeys() {
        let view = LocalizationCompletenessSectionView()
        let catalogNames = view.snapshot.catalogRows.map(\.catalogName)
        XCTAssertEqual(
            catalogNames,
            [
                "Localizable.xcstrings",
                "RoamPrivateTools.xcstrings",
                "MerchantStoreParity.xcstrings",
                "MemberProfile.xcstrings"
            ]
        )
        XCTAssertEqual(view.snapshot.totalMissingKeys, 0)
        XCTAssertTrue(view.snapshot.verbatimViewsCompliant)
        XCTAssertTrue(view.snapshot.isAllComplete)
        XCTAssertTrue(view.snapshot.catalogRows.allSatisfy { $0.supportedLocales == ["en", "zh-Hans"] && $0.isBilingualComplete })
        XCTAssertEqual(view.snapshot.statusHeadline, "多语言词表与 Text(verbatim:) 门禁全部通过")
        _ = view.body
    }

    func testSnapshotDetectsMissingKeysOrMissingLocale() {
        let rows = [
            LocalizationCatalogStatusRow(
                catalogName: "Localizable.xcstrings",
                supportedLocales: ["en", "zh-Hans"],
                missingKeyCount: 0
            ),
            LocalizationCatalogStatusRow(
                catalogName: "MerchantStoreParity.xcstrings",
                supportedLocales: ["zh-Hans"],
                missingKeyCount: 2,
                summaryText: "缺少 en 翻译"
            )
        ]
        let snapshot = LocalizationCompletenessSnapshot(catalogRows: rows, verbatimViewsCompliant: true)
        XCTAssertFalse(snapshot.isAllComplete)
        XCTAssertEqual(snapshot.totalMissingKeys, 2)
        XCTAssertEqual(snapshot.statusHeadline, "多语言词表存在未完成项 (缺失词条 2)")

        let view = LocalizationCompletenessSectionView(snapshot: snapshot)
        XCTAssertEqual(view.snapshot.catalogRows.count, 2)
        XCTAssertFalse(view.snapshot.catalogRows[1].isBilingualComplete)
        _ = view.body
    }
}
