import XCTest
@testable import QuestifyCore

final class MerchantOnboardingDescriptionLimitTests: XCTestCase {
    func testDescriptionClampsToTwoHundredVisibleCharacters() {
        XCTAssertEqual(MerchantOnboardingDescriptionLimit.maximum, 200)
        let short = String(repeating: "店", count: 200)
        XCTAssertEqual(MerchantOnboardingDescriptionLimit.clamped(short), short)
        let long = String(repeating: "店", count: 199) + "👍🏽好"
        XCTAssertEqual(MerchantOnboardingDescriptionLimit.clamped(long).count, 200)
        XCTAssertTrue(MerchantOnboardingDescriptionLimit.clamped(long).hasSuffix("👍🏽"))
    }
}
