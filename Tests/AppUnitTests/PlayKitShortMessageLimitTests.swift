import XCTest
@testable import Questify

final class PlayKitShortMessageLimitTests: XCTestCase {
    private func validate(_ text: String, raw: PlayWireValue, daily: Bool) throws {
        try PlayKitInputContract.validate(kind: daily ? "dailySign" : "note",
            action: daily ? "CLAIM_DAILY_SIGN" : "SUBMIT_NOTE",
            payload: daily ? ["text": .string(text), "photoUrl": .string("")] : ["text": .string(text)],
            segment: .object([daily ? "textMax" : "maxLength": raw]))
    }
    func testMissingZeroAndNegativeLimitsPreserveFortyUnitMessages() throws {
        let values: [PlayWireValue] = [.null, .integer(0), .integer(-1)]
        for raw in values {
            let text = String(repeating: "文", count: 40)
            let limited = PlayKitInputContract.limitText(text, toUTF16: PlayKitShortMessageLimit.resolve(raw))
            XCTAssertEqual(limited, text)
            for daily in [false, true] {
                XCTAssertNoThrow(try validate(limited, raw: raw, daily: daily))
                XCTAssertThrowsError(try validate(text + "文", raw: raw, daily: daily))
            }
        }
    }
    func testPositiveLimitStillTruncatesAtExactOriginalBoundary() throws {
        let raw = PlayWireValue.integer(3)
        let text = PlayKitInputContract.limitText("ABCD", toUTF16: PlayKitShortMessageLimit.resolve(raw))
        XCTAssertEqual(text, "ABC")
        for daily in [false, true] {
            XCTAssertNoThrow(try validate(text, raw: raw, daily: daily))
            XCTAssertThrowsError(try validate("ABCD", raw: raw, daily: daily))
        }
    }
    func testUTF16FallbackPreservesWholeEmojiAndPresetText() throws {
        let preset = String(repeating: "😀", count: 21)
        let limited = PlayKitInputContract.limitText(preset, toUTF16: PlayKitShortMessageLimit.resolve(.integer(0)))
        XCTAssertEqual(limited, String(repeating: "😀", count: 20)); XCTAssertEqual(limited.utf16.count, 40)
        for daily in [false, true] { XCTAssertNoThrow(try validate(limited, raw: .integer(0), daily: daily)) }
    }
    func testInvalidTypedWireLimitMatchesExistingCoreFallback() throws {
        let values: [PlayWireValue] = [.string("2"), .number(2.5), .bool(true)]
        for raw in values {
            XCTAssertEqual(PlayKitShortMessageLimit.resolve(raw), 40)
            for daily in [false, true] { XCTAssertNoThrow(try validate("more than one", raw: raw, daily: daily)) }
        }
    }
    func testOneAndEmptyInputContractsAreUnchanged() throws {
        XCTAssertEqual(PlayKitShortMessageLimit.resolve(.integer(1)), 1)
        for daily in [false, true] {
            XCTAssertNoThrow(try validate("A", raw: .integer(1), daily: daily))
            XCTAssertThrowsError(try validate("AB", raw: .integer(1), daily: daily))
            XCTAssertThrowsError(try validate(" ", raw: .integer(0), daily: daily))
        }
    }
}
