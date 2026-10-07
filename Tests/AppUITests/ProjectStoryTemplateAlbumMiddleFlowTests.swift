import XCTest

@MainActor final class ProjectStoryTemplateAlbumMiddleFlowTests: XCTestCase {
    private var journey: ProjectStoryTemplateFlowSupport?
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { journey?.finish(self); journey = nil }
    // UNMEASURED complete-method estimate: 900 seconds, including all shared helpers.
    func testAlbumMiddleGapPreviewCancelApplySaveAndRestore() throws {
        let value = ProjectStoryTemplateFlowSupport(); journey = value
        try value.journey(.album, gap: .middle)
    }
}
