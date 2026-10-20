import XCTest
@testable import QuestifyCore

final class ClubDetailEventsSummaryTests: XCTestCase {
    func testNoOverviewAndNoFailureIsLoading() {
        XCTAssertEqual(ClubDetailEventsSummary(overview: nil, failure: nil, loading: true).state, .loading)
    }
    func testFailuresAreIsolatedAndMapToExistingKeys() {
        XCTAssertEqual(ClubDetailEventsSummary(overview: nil, failure: .forbidden, loading: false).state, .failed(localizationKey: "club.gov.denied"))
        XCTAssertEqual(ClubDetailEventsSummary(overview: nil, failure: .signedOut, loading: false).state, .failed(localizationKey: "club.gov.signedOut"))
        XCTAssertEqual(ClubDetailEventsSummary(overview: nil, failure: .malformed, loading: false).state, .failed(localizationKey: "club.gov.malformed"))
    }
    func testUpcomingLimitIsThree() { XCTAssertEqual(ClubDetailEventsSummary.upcomingLimit, 3) }
}
