import XCTest

/// Ordinary editor and author controls with generated local imagery and in-memory producer replies only.
@MainActor final class OwnedTopicCoverSelectionFlowTests:XCTestCase {
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
    private struct Probe:Decodable{let coverUploadCount:Int,coverSelectCount:Int,coverStatusCount:Int,coverImageCount:Int,coverHash:String,reviewSubmitCount:Int;let coverRequestIDs:[String]}
    private func inspect(_ app:XCUIApplication)throws->Probe{
        let element = app.buttons["projectStarter.fixtureSnapshot"]
        let before = (element.value as? String) ?? ""
        tap("projectStarter.fixtureSnapshot",in:app,fixed:true)
        let changed=XCTNSPredicateExpectation(predicate:NSPredicate(format:"value != %@ AND value BEGINSWITH %@",before,"{"),object:element)
        XCTAssertEqual(XCTWaiter.wait(for:[changed],timeout:5),.completed,app.debugDescription)
        return try JSONDecoder().decode(Probe.self,from:Data(try XCTUnwrap(element.value as? String).utf8))
    }
    // UNMEASURED complete method estimate: 900 seconds. Includes submit receipt, local cancel/reselect,
    // explicit upload, exact body read, captured selection, next-review readback and original-asset display.
    func testExplicitLocalPickUploadSelectionAndCapturedReviewImageUseOneExactAsset()throws{
        let app=XCUIApplication();self.app=app
        app.launchArguments=["--uitesting-reset-language","-AppleLanguages","(en)","-AppleLocale","en_US","--uitesting-module","projectEdit","--project-edit-bundle-ack","--project-edit-starter-probe","--project-owned-cover","--project-review-request"]
        app.launch();XCTAssertTrue(app.textFields["projectEdit.name"].waitForExistence(timeout:5));XCTAssertTrue(app.staticTexts["ownedCover.fixture.scope"].exists)
        tap("projectEdit.review",in:app,fixed:true);tap("projectEdit.confirmSimulation",in:app);value("projectSubmission.auditTaskID","3301",in:app);tap("projectSubmission.done",in:app)
        tap("ownedCover.open",in:app);tap("ownedCover.choose",in:app)
        XCTAssertTrue(app.images["ownedCover.localPreview"].waitForExistence(timeout:5));value("ownedCover.localOnly",in:app)
        tap("ownedCover.cancelLocal",in:app);XCTAssertFalse(app.images["ownedCover.localPreview"].exists)
        tap("ownedCover.close",in:app,fixed:true);let local=try inspect(app);XCTAssertEqual(local.coverUploadCount,0);XCTAssertEqual(local.coverSelectCount,0);XCTAssertEqual(local.coverImageCount,0)
        tap("ownedCover.open",in:app);tap("ownedCover.choose",in:app);tap("ownedCover.upload",in:app)
        value("ownedCover.uploaded.asset","11111111-1111-4111-8111-111111111111",in:app)
        value("ownedCover.uploaded.version","22222222-2222-4222-8222-222222222222",in:app);value("ownedCover.uploaded.hash",local.coverHash,in:app)
        XCTAssertFalse(app.images["ownedCover.serverPreview"].exists);tap("ownedCover.readUploaded",in:app)
        XCTAssertTrue(app.images["ownedCover.serverPreview"].waitForExistence(timeout:5));tap("ownedCover.reviewSelection",in:app)
        value("ownedCover.confirm.asset","11111111-1111-4111-8111-111111111111",in:app);value("ownedCover.confirm.hash",local.coverHash,in:app)
        tap("ownedCover.cancel",in:app,fixed:true);XCTAssertFalse(app.buttons["ownedCover.confirm"].exists)
        tap("ownedCover.reviewSelection",in:app);tap("ownedCover.confirm",in:app)
        value("ownedCover.selectedNotice.asset","11111111-1111-4111-8111-111111111111",in:app);value("ownedCover.selectedNotice.config","2",in:app)
        tap("topicReview.open",in:app);value("topicReview.selectedCover.hash",local.coverHash,in:app);value("topicReview.selectedCover.selection","1",in:app)
        tap("topicReview.selectedCover.openImage",in:app);XCTAssertTrue(app.images["ownedCover.image.content"].waitForExistence(timeout:5))
        value("ownedCover.image.asset","11111111-1111-4111-8111-111111111111",in:app);value("ownedCover.image.version","22222222-2222-4222-8222-222222222222",in:app)
        tap("ownedCover.image.close",in:app,fixed:true);tap("topicReview.close",in:app,fixed:true)
        let final=try inspect(app);XCTAssertEqual(final.coverUploadCount,1);XCTAssertEqual(final.coverSelectCount,1);XCTAssertEqual(final.coverImageCount,2);XCTAssertEqual(final.coverStatusCount,0);XCTAssertEqual(final.reviewSubmitCount,0);XCTAssertEqual(final.coverRequestIDs.count,1)
    }
}
