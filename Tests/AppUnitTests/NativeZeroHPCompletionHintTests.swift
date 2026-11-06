import Foundation
import XCTest
@testable import Questify

final class NativeZeroHPCompletionHintTests: XCTestCase {
    func testReadOnlyCompletionDoesNotClaimASave() {
        let copy = NativeZeroHPAuthorPresentation(locale: Locale(identifier: "en"))
        XCTAssertEqual(copy.completionHint(readOnly: true), "Close the read-only configuration. No draft is saved or changed.")
        XCTAssertEqual(copy.completionHint(readOnly: false), copy.text("zeroHP.doneHint"))
        XCTAssertTrue(copy.completionHint(readOnly: false).contains("Does not save to the server"))
    }
    func testChineseReadOnlyAndEditableCompletionStayDistinct() {
        let copy = NativeZeroHPAuthorPresentation(locale: Locale(identifier: "zh-Hans"))
        XCTAssertEqual(copy.completionHint(readOnly: true), "关闭只读配置，不保存或修改草稿。")
        XCTAssertEqual(copy.completionHint(readOnly: false), copy.text("zeroHP.doneHint"))
        XCTAssertNotEqual(copy.completionHint(readOnly: true), copy.completionHint(readOnly: false))
    }
}
