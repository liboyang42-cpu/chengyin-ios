import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@MainActor final class PlayKitScreenTests: XCTestCase {
    private func wire(_ json: String) throws -> PlayWireValue { try JSONDecoder().decode(PlayWireValue.self, from: Data(json.utf8)) }
    private func check(_ kind: String, _ action: String, _ payload: [String: PlayWireValue], _ json: String) throws {
        try PlayKitInputContract.validate(kind: kind, action: action, payload: payload, segment: wire(json))
    }
    func testAllTwentyTwoScreensAndFiveMiniOnlyKindsAreRegistered() {
        let source = ["coinFlip","diceRoll","reaction","ballShake","quietHold","countdown","stopwatch","qa","branch","estimate","pricePair","hiddenObject","predict","random","scan","walk","bingo","profile","photoCheck","note","typeIn","dailySign"]
        for kind in source + ["sort","match","classify","compass","shout"] { XCTAssertNotNil(PlayKitScreenKind(rawValue: kind)) }
        XCTAssertEqual(PlayKitScreenKind.priority.last, .bingo)
    }
    func testQAUsesSourceIDsAndMultiSelectArray() throws {
        let segment = #"{"mode":"PICK","multi":true,"options":[{"id":"a","label":"Alpha"},{"id":"b","label":"Beta"}]}"#
        try check("qa", "SUBMIT_QA", ["optionIds": .array([.string("a"),.string("b")])], segment)
        XCTAssertThrowsError(try check("qa", "SUBMIT_QA", ["optionId": .string("a")], segment))
        XCTAssertThrowsError(try check("qa", "SUBMIT_QA", ["optionIds": .array([.string("a"),.string("a")])], segment))
        XCTAssertThrowsError(try check("qa", "SUBMIT_QA", ["optionIds": .array([.string("missing")])], segment))
    }
    func testFinishedQuestionNeverReopensBasedOnLocalAnswer() throws {
        XCTAssertThrowsError(try check("qa", "SUBMIT_QA", ["input": .string("answer")], #"{"mode":"TYPE","finished":true,"passed":false}"#))
        XCTAssertTrue(PlayKitScreenProjection(kind: .qa, segment: try wire(#"{"finished":true,"passed":false}"#)).complete)
    }
    func testPhotoContractsRejectLocalPathsAndClientScores() throws {
        try check("photoCheck", "SUBMIT_PHOTO_CHECK", ["imageUrl": .string("https://example.com/photo.jpg")], "{}")
        XCTAssertThrowsError(try check("photoCheck", "SUBMIT_PHOTO_CHECK", ["imageUrl": .string("file:///tmp/photo.jpg")], "{}"))
        XCTAssertThrowsError(try check("photoCheck", "SUBMIT_PHOTO_CHECK", ["imageUrl": .string("https://example.com/photo.jpg"), "score": .int(100)], "{}"))
        XCTAssertThrowsError(try check("qa", "SUBMIT_QA", ["tempFilePath": .string("/tmp/photo")], #"{"mode":"SHOT"}"#))
    }
    func testEstimateRespectsRangeAndFiniteValues() throws {
        try check("estimate", "SUBMIT_ESTIMATE", ["value": .number(12.5)], #"{"min":0,"max":20}"#)
        for value in [-1.0, 21, .nan, .infinity] { XCTAssertThrowsError(try check("estimate", "SUBMIT_ESTIMATE", ["value": .number(value)], #"{"min":0,"max":20}"#)) }
    }
    func testHiddenCoordinatesRejectLetterboxAndOutsideImage() {
        XCTAssertNil(PlayKitInputContract.imagePoint(x: 10, y: 10, viewWidth: 300, viewHeight: 300, imageWidth: 300, imageHeight: 100))
        let center = PlayKitInputContract.imagePoint(x: 150, y: 150, viewWidth: 300, viewHeight: 300, imageWidth: 300, imageHeight: 100)
        XCTAssertEqual(center?.0, 0.5); XCTAssertEqual(center?.1, 0.5)
        XCTAssertNil(PlayKitInputContract.imagePoint(x: -1, y: 0, viewWidth: 300, viewHeight: 300, imageWidth: 300, imageHeight: 300))
    }
    func testHiddenPayloadNeverIncludesTargetAnswerCoordinates() throws {
        try check("hiddenObject", "SUBMIT_HIDDEN_OBJECT", ["x": .number(0.4), "y": .number(0.6)], #"{"total":2}"#)
        XCTAssertThrowsError(try check("hiddenObject", "SUBMIT_HIDDEN_OBJECT", ["x": .number(40), "y": .number(60)], #"{"total":2}"#))
    }
    func testProfileRequiresAuthoritativeQuestionKeysAndAvatar() throws {
        let source = #"{"questions":[{"key":"name","label":"Name","maxLength":10},{"key":"choice","kind":"pick","options":[{"key":"a","label":"A"}]}],"avatar":{"required":true}}"#
        let valid: [String: PlayWireValue] = ["answers": .object(["name":.string("Alex"),"choice":.string("a")]), "avatarUrl":.string("https://example.com/avatar.jpg")]
        try check("profile", "SUBMIT_PROFILE", valid, source)
        var missing = valid; missing["avatarUrl"] = .string("")
        XCTAssertThrowsError(try check("profile", "SUBMIT_PROFILE", missing, source))
        var extra = valid; extra["answers"] = .object(["name":.string("Alex"), "choice":.string("a"), "hp":.string("999")])
        XCTAssertThrowsError(try check("profile", "SUBMIT_PROFILE", extra, source))
    }
    func testNoteLengthAndNoInventedPayloadFields() throws {
        try check("note", "SUBMIT_NOTE", ["text":.string("hello")], #"{"maxLength":5}"#)
        XCTAssertThrowsError(try check("note", "SUBMIT_NOTE", ["text":.string("toolong")], #"{"maxLength":5}"#))
        XCTAssertThrowsError(try check("note", "SUBMIT_NOTE", ["text":.string("ok"),"approved":.bool(true)], "{}"))
    }
    func testTypeInAttemptLimitIsServerOwned() throws {
        XCTAssertTrue(PlayKitScreenProjection(kind:.typeIn, segment:try wire(#"{"tries":2,"attempts":2,"passed":false}"#)).complete)
        XCTAssertFalse(PlayKitScreenProjection(kind:.typeIn, segment:try wire(#"{"tries":0,"attempts":20,"passed":false}"#)).complete)
    }
    func testCountdownStartCannotBorrowAnotherGame() throws {
        XCTAssertEqual(try PlayKitActionCatalog.payload(kind:"countdown", action:"START_CHALLENGE", detail:["game":.string("reaction")]), ["game":.string("countdown")])
        try check("countdown", "SUBMIT_COUNTDOWN", [:], #"{"seconds":5}"#)
        XCTAssertThrowsError(try check("countdown", "SUBMIT_COUNTDOWN", ["elapsedMs":.int(5000)], #"{"seconds":5}"#))
    }
    func testTimingStartsOnlyThroughAcknowledgementMethodAndInterrupts() {
        var run = PlayKitTimingRun(); XCTAssertEqual(run.elapsed(now:100),0)
        run.beginAfterAcknowledgement(now:10); XCTAssertEqual(run.elapsed(now:10.5),500)
        run.interrupt(); XCTAssertEqual(run.phase,.interrupted); XCTAssertEqual(run.elapsed(now:1000),0)
        run.beginAfterAcknowledgement(now:2000); run.measure(now:2001.5); XCTAssertEqual(run.elapsedMilliseconds,1500)
    }
    func testReactionEarlyTapDoesNotManufactureARound() {
        var run = PlayKitReactionRun(rounds:2)
        run.beginAfterAcknowledgement(now:10, randomUnit:0); run.tap(now:10.5)
        XCTAssertEqual(run.phase,.early); XCTAssertTrue(run.roundsMilliseconds.isEmpty)
        run.arm(now:20, randomUnit:0); run.tick(now:22); run.tap(now:22.05)
        XCTAssertEqual(run.phase,.early); XCTAssertTrue(run.roundsMilliseconds.isEmpty)
    }
    func testReactionCueTimeUsesActualPresentedTick() {
        var run = PlayKitReactionRun(rounds:1)
        run.beginAfterAcknowledgement(now:10,randomUnit:0); run.tick(now:20); run.tap(now:20.25)
        XCTAssertEqual(run.phase,.measured); XCTAssertEqual(run.roundsMilliseconds,[250])
    }
    func testReactionInterruptionClearsAllRounds() {
        var run = PlayKitReactionRun(rounds:2)
        run.beginAfterAcknowledgement(now:0,randomUnit:0); run.tick(now:2); run.tap(now:2.5); run.interrupt()
        XCTAssertEqual(run.phase,.interrupted); XCTAssertTrue(run.roundsMilliseconds.isEmpty)
    }
    func testBingoReadsServerPositionsWithoutActionsOrLocalToggles() throws {
        let board = PlayKitBingoBoard(try wire(#"{"filledPositions":[0,1,2,3,6,6,99,-1]}"#))
        XCTAssertEqual(board.filled, [0,1,2,3,6]); XCTAssertEqual(board.completedLines.count,2)
        XCTAssertEqual(PlayKitActionCatalog.actions["bingo"], [])
        XCTAssertThrowsError(try PlayKitActionCatalog.payload(kind:"bingo", action:"CLAIM_BINGO", detail:[:]))
    }
    func testStepsNeverAcceptsUnverifiedPedometerReplacement() throws {
        XCTAssertThrowsError(try check("steps", "SUBMIT_STEPS", ["steps":.int(9999)], #"{"goal":5000,"todaySteps":0}"#))
    }
    func testSortRequiresFullUniquePermutation() throws {
        let segment = #"{"items":[{"id":"a"},{"id":"b"}]}"#
        try check("sort","SUBMIT_SORT",["order":.array([.string("b"),.string("a")])],segment)
        XCTAssertThrowsError(try check("sort","SUBMIT_SORT",["order":.array([.string("a"),.string("a")])],segment))
    }
    func testMatchingRequiresCompleteOneToOnePairs() throws {
        let segment = #"{"left":[{"id":"a"},{"id":"b"}],"right":[{"id":"x"},{"id":"y"}]}"#
        try check("match","SUBMIT_MATCH",["pairs":.array([.array([.string("a"),.string("x")]),.array([.string("b"),.string("y")])])],segment)
        XCTAssertThrowsError(try check("match","SUBMIT_MATCH",["pairs":.array([.array([.string("a"),.string("x")]),.array([.string("b"),.string("x")])])],segment))
    }
    func testClassificationRequiresEveryItemAndKnownBins() throws {
        let segment = #"{"items":[{"id":"a"},{"id":"b"}],"bins":[{"id":"one"},{"id":"two"}]}"#
        try check("classify","SUBMIT_CLASSIFY",["placement":.object(["a":.string("one"),"b":.string("one")])],segment)
        XCTAssertThrowsError(try check("classify","SUBMIT_CLASSIFY",["placement":.object(["a":.string("one")])],segment))
    }
}

@available(macOS 14.0, *)
@MainActor final class PlayKitReviewTests: XCTestCase {
    private func response(version: Int, note: String = "", withSteps: Bool = false) throws -> Data {
        var kit: [String: PlayWireValue] = ["note":.object(["maxLength":.int(40),"done":.bool(!note.isEmpty)])]
        if withSteps { kit["steps"] = .object(["goal":.int(5000),"reached":.bool(false)]) }
        let state: PlayWireValue = .object(["sessionId":.int(1),"activityId":.int(41),"topicId":.int(71),"nodeId":.int(701),"version":.int(version),"status":.string("RUNNING"),"playKit":.object(kit),"vars":.object(["name":.string("Synthetic")])])
        return try JSONEncoder().encode(PlayWireValue.object(["code":.int(200),"data":state]))
    }
    private func session(_ epoch: UInt64 = 1) throws -> PlayExperienceSession { try .init(accountID:1,epoch:epoch,namespace:"synthetic",token:"synthetic-token") }
    private func coordinator(_ transport: any HTTPTransport, current: @escaping () -> PlayExperienceSession?) throws -> PlayAdvancedCoordinator {
        .init(activityID:41,topicID:71,nodeID:701,service:.init(configuration:try APIConfiguration(baseURL:URL(string:"https://example.com")!),transport:transport,enabled:[.reads,.advanced]),currentSession:current)
    }
    func testReviewCannotSilentlyAcquireNewVersion() async throws {
        let session = try session(); var version = 1
        let transport = PlayKitTestTransport { _ in try (self.response(version:version),200) }
        let model = try coordinator(transport,current:{session}); await model.start()
        let review = try model.review(kind:"note",action:"SUBMIT_NOTE",detail:["text":.string("hello")])
        version = 2; await model.refreshAuthoritative()
        let submitted = await model.submit(review); XCTAssertFalse(submitted); XCTAssertEqual(transport.requests.count,2)
    }
    func testAccountChangeInvalidatesReviewAndDispatch() async throws {
        var current: PlayExperienceSession? = try session()
        let transport = PlayKitTestTransport { _ in try (self.response(version:1),200) }
        let model = try coordinator(transport,current:{current}); await model.start()
        let review = try model.review(kind:"note",action:"SUBMIT_NOTE",detail:["text":.string("hello")])
        current = try session(2)
        let submitted = await model.submit(review); XCTAssertFalse(submitted); XCTAssertEqual(transport.requests.count,1)
    }
    func testUnverifiedStepsDoNotDisableOtherKindsButCannotSubmitProof() async throws {
        let session = try session()
        let transport = PlayKitTestTransport { _ in try (self.response(version:1,withSteps:true),200) }
        let model = try coordinator(transport,current:{session}); await model.start()
        XCTAssertTrue(model.canInteract)
        XCTAssertNoThrow(try model.review(kind:"note",action:"SUBMIT_NOTE",detail:["text":.string("hello")]))
        XCTAssertThrowsError(try model.review(kind:"steps",action:"SUBMIT_STEPS",detail:["steps":.int(5000)]))
        XCTAssertEqual(model.state?.storyVariables["name"],.string("Synthetic"))
    }
    func testUnknownWriteLocksNewActionsAndRetainsFrozenPayload() async throws {
        let session = try session(); var writes = 0
        let transport = PlayKitTestTransport { request in
            if request.url?.path.hasSuffix("action") == true { writes += 1; throw URLError(.timedOut) }
            return try (self.response(version:writes == 0 ? 1 : 2),200)
        }
        let model = try coordinator(transport,current:{session}); await model.start()
        let review = try model.review(kind:"note",action:"SUBMIT_NOTE",detail:["text":.string("hello")])
        let submitted = await model.submit(review); XCTAssertFalse(submitted); let frozen = model.pending
        await model.recover(); XCTAssertEqual(model.phase,"retryable"); XCTAssertEqual(model.pending,frozen)
        XCTAssertThrowsError(try model.review(kind:"note",action:"SUBMIT_NOTE",detail:["text":.string("different")]))
        await model.retryExact(); XCTAssertEqual(model.pending,frozen); XCTAssertEqual(writes,2)
        let actions = transport.requests.filter { $0.url?.path.hasSuffix("action") == true }
        XCTAssertEqual(actions[0].httpBody,actions[1].httpBody)
    }
}
private final class PlayKitTestTransport: HTTPTransport {
    var requests: [URLRequest] = []
    let operation: @MainActor (URLRequest) async throws -> (Data, Int)
    init(_ operation: @escaping @MainActor (URLRequest) async throws -> (Data, Int)) { self.operation = operation }
    func send(_ request: URLRequest) async throws -> (Data, Int) { requests.append(request); return try await operation(request) }
}
