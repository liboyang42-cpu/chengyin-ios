import SwiftUI
import XCTest
#if canImport(Questify)
@testable import Questify
#elseif canImport(QuestifyApp)
@testable import QuestifyApp
#endif
#if canImport(QuestifyCore)
@testable import QuestifyCore
#endif

@MainActor final class LocalizationPluralAndFormatterConsistencySectionViewTests: XCTestCase {
    func testDefaultReadySnapshotCoversAllThreeDomainsAndExactFenToYuanFormatting() {
        let snapshot = FormatterConsistencySnapshot.defaultReady
        XCTAssertTrue(snapshot.isReady)
        XCTAssertEqual(snapshot.rows.count, 3)
        XCTAssertEqual(snapshot.consistentRowCount, 3)
        XCTAssertEqual(snapshot.driftWarningCount, 0)
        XCTAssertEqual(
            snapshot.rows.map(\.kind),
            [
                .fenToYuanExactCurrency,
                .posixAndShanghaiDateParsing,
                .bilingualPluralAndCatalogReadiness,
            ]
        )

        XCTAssertEqual(FormatterConsistencySnapshot.formatFenToYuan(0), "¥0.00")
        XCTAssertEqual(FormatterConsistencySnapshot.formatFenToYuan(5), "¥0.05")
        XCTAssertEqual(FormatterConsistencySnapshot.formatFenToYuan(9_900), "¥99.00")
        XCTAssertEqual(FormatterConsistencySnapshot.formatFenToYuan(12_345), "¥123.45")
        XCTAssertEqual(FormatterConsistencySnapshot.formatFenToYuan(-50), "-¥0.50")
    }

    func testFormatterDriftWarningOrUnpinnedParserMarksSnapshotNotReady() {
        let driftWarningSnapshot = FormatterConsistencySnapshot(
            driftWarningCount: 2
        )
        XCTAssertFalse(driftWarningSnapshot.isReady)

        let unpinnedParserSnapshot = FormatterConsistencySnapshot(
            posixLocaleAndShanghaiZonePinned: false
        )
        XCTAssertFalse(unpinnedParserSnapshot.isReady)

        var customRows = FormatterConsistencyDomainRow.defaultRows
        customRows[0] = FormatterConsistencyDomainRow(
            id: "fen-to-yuan-currency",
            kind: .fenToYuanExactCurrency,
            title: "Exact Fen-to-Yuan Currency Formatting",
            sampleOutput: "Drift warning",
            detail: "Float rounding detected",
            isConsistent: false,
            badgeText: "DRIFT"
        )
        let rowDriftSnapshot = FormatterConsistencySnapshot(rows: customRows)
        XCTAssertEqual(rowDriftSnapshot.consistentRowCount, 2)
        XCTAssertFalse(rowDriftSnapshot.isReady)
    }

    func testMainActorViewBodyInstantiatesAcrossDefaultAndDriftSnapshots() {
        let defaultView = LocalizationPluralAndFormatterConsistencySectionView()
        _ = defaultView.body
        XCTAssertTrue(defaultView.snapshot.isReady)

        let driftView = LocalizationPluralAndFormatterConsistencySectionView(
            snapshot: FormatterConsistencySnapshot(
                exactFenToYuanVerified: false,
                posixLocaleAndShanghaiZonePinned: false,
                bilingualPluralCatalogComplete: false,
                driftWarningCount: 3
            )
        )
        _ = driftView.body
        XCTAssertFalse(driftView.snapshot.isReady)
    }
}
