import XCTest

@MainActor final class OwnedTopicCoverRecoveryFlowTests:XCTestCase{
    private var app:XCUIApplication?
    override func setUpWithError()throws{continueAfterFailure=false}
    override func tearDownWithError()throws{attachFailureScreenshot(self,app:app);app?.terminate();app=nil}
    private func tap(_ id:String,in app:XCUIApplication,fixed:Bool=false){
        let element=app.buttons[id];XCTAssertTrue(element.waitForExistence(timeout:5),app.debugDescription)
        if !fixed{XCTAssertTrue(revealFixtureElement(element,in:app,maximumSwipes:70),app.debugDescription)}
        XCTAssertEqual(app.buttons.matching(identifier:id).count,1);XCTAssertTrue(element.isEnabled && element.isHittable);XCTAssertTrue(app.windows.firstMatch.frame.contains(element.frame));element.tap()
    }
    @discardableResult private func value(_ id:String,_ expected:String?=nil,in app:XCUIApplication)->String{
        let element=app.staticTexts[id];XCTAssertTrue(element.waitForExistence(timeout:5),app.debugDescription)
        XCTAssertTrue(revealFixtureElement(element,in:app,maximumSwipes:70,requiresHittable:false),app.debugDescription)
        if let expected{XCTAssertEqual(Array(element.label.utf8),Array(expected.utf8))};return element.label
    }
    private struct Probe:Decodable{let coverUploadCount:Int,coverSelectCount:Int,coverStatusCount:Int,coverImageCount:Int;let coverRequestIDs:[String]}
    private func inspect(_ app:XCUIApplication)throws->Probe{
        let element = app.buttons["projectStarter.fixtureSnapshot"]
        let before = (element.value as? String) ?? ""
        tap("projectStarter.fixtureSnapshot",in:app,fixed:true)
        let changed=XCTNSPredicateExpectation(predicate:NSPredicate(format:"value != %@ AND value BEGINSWITH %@",before,"{"),object:element)
        XCTAssertEqual(XCTWaiter.wait(for:[changed],timeout:5),.completed,app.debugDescription)
        return try JSONDecoder().decode(Probe.self,from:Data(try XCTUnwrap(element.value as? String).utf8))
    }
    // UNMEASURED complete method estimate: 900 seconds. Chinese maximum text includes the full saved
    // submission, exact cover confirmation, lost response, host reopen and original-request recovery.
    func testChineseMaximumTextUnknownSelectionReopensAndChecksOriginalRequestWithoutReupload()throws{
        let app=XCUIApplication();self.app=app
        app.launchArguments=["--uitesting-reset-language","-AppleLanguages","(zh-Hans)","-AppleLocale","zh_CN","--uitesting-max-text","-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL","--uitesting-module","projectEdit","--project-edit-bundle-ack","--project-edit-starter-probe","--project-owned-cover","--project-owned-cover-unknown","--project-review-request"]
        app.launch();XCTAssertTrue(revealProjectEditorNameInForm(in: app),app.debugDescription);XCTAssertTrue(app.textFields["projectEdit.name"].waitForExistence(timeout:5));assertFixtureEnvironment(in: app, dynamicTypeSize:"accessibility5")
        tap("projectEdit.review",in:app,fixed:true);tap("projectEdit.confirmSimulation",in:app);assertProjectSubmissionEvidenceValue("projectSubmission.auditTaskID", "3301", in: app, phase: .receipt, maximumSwipes: 70, revealFirst: false);tap("projectSubmission.done",in:app)
        tap("ownedCover.open",in:app);XCTAssertTrue(app.navigationBars["作者封面"].exists)
        tap("ownedCover.choose",in:app);value("ownedCover.localOnly",in:app);tap("ownedCover.upload",in:app)
        value("ownedCover.uploaded.asset","11111111-1111-4111-8111-111111111111",in:app);tap("ownedCover.readUploaded",in:app)
        XCTAssertTrue(app.images["ownedCover.serverPreview"].waitForExistence(timeout:5));tap("ownedCover.reviewSelection",in:app)
        value("ownedCover.confirm.version","22222222-2222-4222-8222-222222222222",in:app);tap("ownedCover.confirm",in:app)
        value("ownedCover.selectionUnknown",in:app);XCTAssertFalse(app.buttons["ownedCover.choose"].isEnabled)
        tap("ownedCover.close",in:app,fixed:true);let before=try inspect(app)
        XCTAssertEqual(before.coverUploadCount,1);XCTAssertEqual(before.coverSelectCount,1);XCTAssertEqual(before.coverStatusCount,0);XCTAssertEqual(before.coverRequestIDs.count,1)
        tap("projectEdit.fixture.reopen",in:app,fixed:true);tap("ownedCover.open",in:app)
        value("ownedCover.selectionUnknown",in:app);XCTAssertFalse(app.buttons["ownedCover.choose"].isEnabled)
        tap("ownedCover.checkSelection",in:app);value("ownedCover.selectedNotice.config","2",in:app)
        let after=try inspect(app);XCTAssertEqual(after.coverUploadCount,1);XCTAssertEqual(after.coverSelectCount,1);XCTAssertEqual(after.coverStatusCount,1)
        XCTAssertEqual(after.coverRequestIDs,[try XCTUnwrap(before.coverRequestIDs.first),try XCTUnwrap(before.coverRequestIDs.first)]);XCTAssertEqual(after.coverImageCount,1)
    }
}
