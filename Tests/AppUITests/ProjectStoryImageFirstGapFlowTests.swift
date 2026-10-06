import XCTest

@MainActor final class ProjectStoryImageFirstGapFlowTests: XCTestCase {
    private var journey: ProjectStoryMediaGapFlowSupport?
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { journey?.finish(self); journey = nil }
    // UNMEASURED complete-method estimate: 900 seconds, including every shared journey helper.
    func testImageFirstGapCancelSaveRestoreAndPreparedOrder() throws {
        let value = ProjectStoryMediaGapFlowSupport(); journey = value
        try value.imageJourney(.first)
    }
}
