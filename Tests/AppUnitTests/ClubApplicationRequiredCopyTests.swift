import Foundation
import XCTest
@testable import Questify

final class ClubApplicationRequiredCopyTests: XCTestCase {
    func testRequiredLabelAndFailureAreAvailableInBothLanguages() throws {
        for locale in ["en","zh-Hans"] {
            let label = String(localized:"club.admission.messageLabel",table:"ClubApplicationMessage",locale:Locale(identifier:locale))
            let failure = String(localized:"club.admission.messageRequired",table:"ClubApplicationMessage",locale:Locale(identifier:locale))
            XCTAssertFalse(label.isEmpty); XCTAssertNotEqual(label,"club.admission.messageLabel")
            XCTAssertFalse(failure.isEmpty); XCTAssertNotEqual(failure,"club.admission.messageRequired")
            XCTAssertFalse(label.lowercased().contains("optional")); XCTAssertFalse(label.contains("选填"))
        }
    }
}
