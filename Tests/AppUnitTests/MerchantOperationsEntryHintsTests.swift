import XCTest
@testable import Questify

/// Each 品牌中心 entry carries its own source-aligned subtitle key (w2-17).
final class MerchantOperationsEntryHintsTests: XCTestCase {
    func testPrimaryEntriesHaveDistinctHints() {
        let entries: [MerchantOperationsDestination] = [.profile, .businessStatus, .decor, .gallery, .story, .cooperation, .character, .assets, .cityNodes]
        let keys = entries.map(\.entryHintKey)
        XCTAssertEqual(Set(keys).count, entries.count)
        XCTAssertFalse(keys.contains("merchant.operations.entryHint"))
        XCTAssertEqual(MerchantOperationsDestination.templates.entryHintKey, "merchant.operations.entryHint")
    }
}
