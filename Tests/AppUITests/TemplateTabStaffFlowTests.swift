import XCTest

/// Offline merchant template tab for a staff role (当前岗位可浏览模板…). Apple execution is unrun here.
final class TemplateTabStaffFlowTests: XCTestCase {
    private var runningApp: XCUIApplication?
    override func setUp() { super.setUp(); continueAfterFailure = false }
    override func tearDown() { attachFailureScreenshot(self, app: runningApp); runningApp?.terminate(); runningApp = nil; super.tearDown() }

    func testStaffSeesReadOnlyNoteAndCanStillBrowseTopics() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-reset-language", "--uitesting-module", "templateTabStaff",
                               "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        runningApp = app; app.launch()
        let note = app.staticTexts["discovery.templateTab.staffReadOnly"]
        XCTAssertTrue(note.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(note.label.contains("店主或店长"))
        XCTAssertTrue(app.segmentedControls["discovery.shelf"].exists)
        XCTAssertTrue(revealFixtureElement(app.buttons["discovery.topic.801"], in: app), app.debugDescription)
    }
}
