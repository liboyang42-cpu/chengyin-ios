import XCTest

@MainActor final class ProjectStoryTemplateAlbumEndFlowTests: XCTestCase {
    private var journey: ProjectStoryTemplateFlowSupport?
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { journey?.finish(self); journey = nil }
    // UNMEASURED complete-method estimate: 900 seconds, including all shared helpers.
    func testAlbumEndGapPreviewCancelApplySaveAndRestore() throws {
        let value = ProjectStoryTemplateFlowSupport(); journey = value
        try value.journey(.album, gap: .end)
    }
}
