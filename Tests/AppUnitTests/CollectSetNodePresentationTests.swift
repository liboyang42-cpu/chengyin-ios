import Foundation
import XCTest
@testable import Questify

final class CollectSetNodePresentationTests: XCTestCase {
    func testDistinctSavedIDsDisambiguateEqualNames() {
        let copy = CollectSetNodePresentation(nodes: [(31, "Entrance"), (32, "Entrance")], locale: Locale(identifier: "en"))
        XCTAssertEqual(copy.label(id: 31, name: "Entrance"), "Entrance · Node 31")
        XCTAssertEqual(copy.label(id: 32, name: "Entrance"), "Entrance · Node 32")
    }
    func testBlankSavedNodeHasLabelWithoutInventingName() {
        let en = CollectSetNodePresentation(nodes: [(31, " \n")], locale: Locale(identifier: "en"))
        let zh = CollectSetNodePresentation(nodes: [(31, "")], locale: Locale(identifier: "zh-Hans"))
        XCTAssertEqual(en.label(id: 31, name: " \n"), "Node 31")
        XCTAssertEqual(zh.label(id: 31, name: ""), "点位 31")
    }
    func testUniqueNameAndUnicodeBytesStayUntouched() {
        let raw = " %@ e\u{301} 👩🏽‍💻 "
        let copy = CollectSetNodePresentation(nodes: [(31, raw)], locale: Locale(identifier: "en"))
        XCTAssertEqual(Array(copy.label(id: 31, name: raw).utf8), Array(raw.utf8))
    }
    func testSimilarWhitespaceNamesKeepOriginalBytesAndAddIDs() {
        let raw = " %@ e\u{301} "
        let copy = CollectSetNodePresentation(nodes: [(31, raw), (32, "%@ e\u{301}")], locale: Locale(identifier: "en"))
        XCTAssertEqual(Array(copy.label(id: 31, name: raw).utf8), Array((raw + " · Node 31").utf8))
    }
    func testChineseDuplicateNamesUseOriginalNodeIDs() {
        let copy = CollectSetNodePresentation(nodes: [(31, "入口"), (32, "入口")], locale: Locale(identifier: "zh-Hans"))
        XCTAssertEqual(copy.label(id: 32, name: "入口"), "入口 · 点位 32")
    }
}
