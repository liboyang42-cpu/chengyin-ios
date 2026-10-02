import XCTest
@testable import QuestifyCore

final class ParticipationSupportTests: XCTestCase {
    func testRequiresExactIndependentSupportDestinationApproval() throws {
        let url = try XCTUnwrap(URL(string: "https://support.test/help"))
        XCTAssertThrowsError(try ParticipationSupportConfiguration(name: "Synthetic support", url: url, approvedURLs: []))
        let config = try ParticipationSupportConfiguration(name: "Synthetic support", url: url, approvedURLs: [url])
        XCTAssertEqual(config.url, url)
    }
    func testCannotLeakOrderContextInURLOrAcceptCustomScheme() throws {
        for raw in ["http://support.test", "tel:100", "https://support.test/help?order=1", "https://user:secret@support.test", "https://support.test/#context"] {
            let url = try XCTUnwrap(URL(string: raw))
            XCTAssertThrowsError(try ParticipationSupportConfiguration(name: "Synthetic", url: url, approvedURLs: [url]))
        }
    }
}
