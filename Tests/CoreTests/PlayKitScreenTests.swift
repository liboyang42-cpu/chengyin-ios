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
    func testTypeInResultUsesOnlyAuthoritativeOutcome() throws {
        for (json, expected) in [
            (#"{"attempts":1,"submitted":false,"passed":false}"#, "playkit.type.retry"),
            (#"{"attempts":2,"submitted":true,"passed":false}"#, "playkit.type.finishedNotPassed"),
            (#"{"attempts":1,"submitted":true,"passed":true}"#, "playkit.result.passed"),
            (#"{"attempts":9,"tries":1,"submitted":false,"passed":false}"#, "playkit.type.retry"),
            (#"{"attempts":1,"tries":0,"submitted":true,"passed":false}"#, "playkit.type.finishedNotPassed")
        ] {
            XCTAssertEqual(PlayKitScreenProjection(kind: .typeIn, segment: try wire(json)).typeInResultKey, expected)
        }
    }
    func testTypeInResultRejectsMissingMalformedAndContradictoryFields() throws {
        for json in ["{}",
                     #"{"attempts":0,"submitted":true,"passed":false}"#,
                     #"{"attempts":-1,"submitted":true,"passed":false}"#,
                     #"{"attempts":1.5,"submitted":true,"passed":false}"#,
                     #"{"attempts":"1","submitted":true,"passed":false}"#,
                     #"{"attempts":true,"submitted":true,"passed":false}"#,
                     #"{"attempts":1,"passed":false}"#,
                     #"{"attempts":1,"submitted":"true","passed":false}"#,
                     #"{"attempts":1,"submitted":true,"passed":"false"}"#,
                     #"{"attempts":1,"submitted":true}"#,
                     #"{"attempts":1,"submitted":false,"passed":true}"#] {
            XCTAssertNil(PlayKitScreenProjection(kind: .typeIn, segment: try wire(json)).typeInResultKey, json)
        }
        XCTAssertNil(PlayKitScreenProjection(kind: .stopwatch, segment: try wire(#"{"attempts":1,"submitted":true,"passed":true}"#)).typeInResultKey)
    }
    func testReasoningResultSeparatesTerminalFailureFromRetry() throws {
        for (kind, json, expected) in [
            (PlayKitScreenKind.sort, #"{"attempts":2,"finished":true,"passed":false}"#, "playkit.reasoning.finishedNotPassed"),
            (.sort, #"{"attempts":1,"finished":false,"passed":false}"#, "playkit.reasoning.tryAgain"),
            (.sort, #"{"attempts":2,"finished":true,"passed":true}"#, "playkit.result.passed"),
            (.sort, #"{"attempts":99,"maxAttempts":1,"finished":false,"passed":false}"#, "playkit.reasoning.tryAgain"),
            (.match, #"{"attempts":2,"passed":false}"#, "playkit.reasoning.tryAgain"),
            (.classify, #"{"attempts":2,"passed":true}"#, "playkit.result.passed")
        ] {
            let result = PlayKitScreenProjection(kind: kind, segment: try wire(json))
            XCTAssertEqual(result.reasoningResultKey, expected)
        }
    }
    func testReasoningResultDoesNotInventUnreportedVerdicts() throws {
        for json in ["{}", #"{"attempts":0,"finished":true,"passed":false}"#,
                     #"{"attempts":-1,"finished":true,"passed":false}"#,
                     #"{"attempts":1,"finished":true}"#,
                     #"{"attempts":1,"finished":"true","passed":false}"#,
                     #"{"attempts":1,"finished":true,"passed":"false"}"#,
                     #"{"attempts":1,"passed":true}"#,
                     #"{"attempts":1,"finished":"bad","passed":true}"#,
                     #"{"attempts":1,"finished":false,"passed":true}"#,
                     #"{"attempts":1.5,"finished":true,"passed":false}"#] {
            XCTAssertNil(PlayKitScreenProjection(kind: .sort, segment: try wire(json)).reasoningResultKey)
        }
        XCTAssertNil(PlayKitScreenProjection(kind: .qa, segment: try wire(#"{"attempts":1,"finished":true,"passed":false}"#)).reasoningResultKey)
    }
    func testPhotoContractsRejectLocalPathsAndClientScores() throws {
        try check("photoCheck", "SUBMIT_PHOTO_CHECK", ["imageUrl": .string("https://example.com/photo.jpg")], "{}")
        XCTAssertThrowsError(try check("photoCheck", "SUBMIT_PHOTO_CHECK", ["imageUrl": .string("file:///tmp/photo.jpg")], "{}"))
        XCTAssertThrowsError(try check("photoCheck", "SUBMIT_PHOTO_CHECK", ["imageUrl": .string("https://example.com/photo.jpg"), "score": .int(100)], "{}"))
        XCTAssertThrowsError(try check("qa", "SUBMIT_QA", ["tempFilePath": .string("/tmp/photo")], #"{"mode":"SHOT"}"#))
    }
    func testEstimateWheelUsesMiniTicksAndInclusiveUpperEndpoint() throws {
        for (lo, hi, expected) in [
            (0.0, 3.0, [0.0, 1, 2, 3]),
            (0.25, 3.5, [0.25, 1.25, 2.25, 3.25, 3.5]),
            (-2.5, 0.0, [-2.5, -1.5, -0.5, 0.0]),
            (2.5, 2.5, [2.5]),
            (0.1, 0.4, [0.1, 0.4])
        ] {
            let wheel = try XCTUnwrap(PlayKitEstimateWheel(segment: .object(["min": .number(lo), "max": .number(hi)])))
            XCTAssertEqual(wheel.ticks, expected)
            XCTAssertEqual(wheel.value(at: wheel.initialIndex), expected[expected.count / 2])
            XCTAssertNil(wheel.value(at: -1)); XCTAssertNil(wheel.value(at: expected.count))
        }
    }
    func testEstimateWheelThresholdsAreBoundedAndCentered() throws {
        for (upper, count, step) in [(2000.0, 2001, 1.0), (2001.0, 202, 10.0), (20000.0, 2001, 10.0), (20001.0, 202, 100.0), (99999.6, 101, 1000.0), (1e20, 101, 1e18), (999999999999999.0, 1001, 1e12), (999999999999999900000.0, 1001, 1e18)] {
            let wheel = try XCTUnwrap(PlayKitEstimateWheel(segment: .object(["min": .number(0), "max": .number(upper)])))
            XCTAssertEqual(wheel.ticks.count, count); XCTAssertEqual(wheel.ticks[1], step)
            XCTAssertEqual(wheel.ticks.first, 0); XCTAssertEqual(wheel.ticks.last, upper)
            XCTAssertLessThanOrEqual(wheel.ticks.count, PlayKitEstimateWheel.maximumTicks)
            XCTAssertEqual(wheel.initialIndex, count / 2)
        }
    }
    func testEstimateWheelRejectsMalformedOverflowAndNonProgressingRanges() {
        for (lo, hi) in [(Double.nan, 1), (0, Double.infinity), (5, 4), (-Double.greatestFiniteMagnitude, Double.greatestFiniteMagnitude), (0, 1e21), (1e20, 1e20.nextUp)] {
            XCTAssertNil(PlayKitEstimateWheel(segment: .object(["min": .number(lo), "max": .number(hi)])))
        }
        XCTAssertNil(PlayKitEstimateWheel(segment: .object(["min": .string("0"), "max": .int(5)])))
        XCTAssertNil(PlayKitEstimateWheel(segment: .object(["min": .int(0)])))
    }
    func testEstimateWheelCannotUseSecretOrClientOutcomeFields() throws {
        let clean = try wire(#"{"min":0,"max":10}"#)
        let hostile = try wire(#"{"min":0,"max":10,"answer":1,"tolerance":99,"tier":"HIT","awardedXp":999}"#)
        XCTAssertEqual(PlayKitEstimateWheel(segment: clean), PlayKitEstimateWheel(segment: hostile))
        let wheel = try XCTUnwrap(PlayKitEstimateWheel(segment: clean))
        let detail: [String: PlayWireValue] = ["value": .number(try XCTUnwrap(wheel.value(at: wheel.initialIndex)))]
        let payload = try PlayKitActionCatalog.payload(kind: "estimate", action: "SUBMIT_ESTIMATE", detail: detail)
        XCTAssertEqual(payload, detail)
        try PlayKitInputContract.validate(kind: "estimate", action: "SUBMIT_ESTIMATE", payload: payload, segment: clean)
        XCTAssertThrowsError(try PlayKitInputContract.validate(kind: "estimate", action: "SUBMIT_ESTIMATE", payload: ["value": .number(.nan)], segment: clean))
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
    func testDiceTotalReadsServerSumForOneAndTwoD6Dice() throws {
        for (count, sum) in [(1, 4), (2, 9)] {
            let value = PlayKitScreenProjection(kind: .diceRoll, segment: try wire("{\"rolled\":true,\"diceCount\":\(count),\"sum\":\(sum)}"))
            XCTAssertEqual(value.diceTotal, sum)
        }
    }
    func testDiceTotalNeverRecomputesMissingOrMalformedServerSum() throws {
        for json in [
            #"{"rolled":true,"diceCount":2,"pips":[5,4]}"#,
            #"{"rolled":true,"diceCount":2,"sum":"9"}"#,
            #"{"rolled":true,"diceCount":2,"sum":9.5}"#,
            #"{"rolled":true,"diceCount":2,"sum":1}"#,
            #"{"rolled":true,"diceCount":2,"sum":13}"#,
            #"{"rolled":true,"diceCount":1,"sum":7}"#,
            #"{"rolled":true,"diceCount":3,"sum":9}"#,
            #"{"rolled":true,"sum":9}"#,
            #"{"rolled":false,"diceCount":2,"sum":9}"#
        ] {
            XCTAssertNil(PlayKitScreenProjection(kind: .diceRoll, segment: try wire(json)).diceTotal, json)
        }
        // The server's field is the authority; do not substitute local arithmetic.
        XCTAssertEqual(PlayKitScreenProjection(kind: .diceRoll, segment: try wire(#"{"rolled":true,"diceCount":2,"sum":8,"pips":[5,4]}"#)).diceTotal, 8)
    }
    func testDiceModesCannotBorrowEachOthersTotal() throws {
        XCTAssertEqual(PlayKitScreenProjection(kind: .diceRoll, segment: try wire(#"{"mode":"d20","rolled":true,"total":23,"sum":9}"#)).diceTotal, 23)
        for total in [-5, 0] {
            XCTAssertEqual(PlayKitScreenProjection(kind: .diceRoll, segment: try wire("{\"mode\":\"d20\",\"rolled\":true,\"total\":\(total)}")).diceTotal, total)
        }
        for json in [
            #"{"mode":"d20","rolled":true,"sum":9}"#,
            #"{"mode":"d6","rolled":true,"diceCount":2,"total":9}"#,
            #"{"mode":"other","rolled":true,"diceCount":2,"sum":9}"#
        ] { XCTAssertNil(PlayKitScreenProjection(kind: .diceRoll, segment: try wire(json)).diceTotal) }
        XCTAssertNil(PlayKitScreenProjection(kind: .coinFlip, segment: try wire(#"{"rolled":true,"diceCount":2,"sum":9}"#)).diceTotal)
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
    private func response(version: Int, note: String = "", withSteps: Bool = false, dice: PlayWireValue? = nil, estimate: PlayWireValue? = nil) throws -> Data {
        var kit: [String: PlayWireValue] = ["note":.object(["maxLength":.int(40),"done":.bool(!note.isEmpty)])]
        if let dice { kit["diceRoll"] = dice }
        if let estimate { kit["estimate"] = estimate }
        if withSteps { kit["steps"] = .object(["goal":.int(5000),"reached":.bool(false)]) }
        let state: PlayWireValue = .object(["sessionId":.int(1),"activityId":.int(41),"topicId":.int(71),"nodeId":.int(701),"version":.int(version),"status":.string("RUNNING"),"playKit":.object(kit),"vars":.object(["name":.string("Synthetic")])])
        return try JSONEncoder().encode(PlayWireValue.object(["code":.int(200),"data":state]))
    }
    private func session(_ epoch: UInt64 = 1) throws -> PlayExperienceSession { try .init(accountID:1,epoch:epoch,namespace:"synthetic",token:"synthetic-token") }
    private func coordinator(_ transport: any HTTPTransport, current: @escaping () -> PlayExperienceSession?) throws -> PlayAdvancedCoordinator {
        .init(activityID:41,topicID:71,nodeID:701,service:.init(configuration:try APIConfiguration(baseURL:URL(string:"https://example.com")!),transport:transport,enabled:[.reads,.advanced]),currentSession:current)
    }
    private func estimate(submitted: Bool = false, maximum: Double = 10) -> PlayWireValue {
        .object(["min": .number(0), "max": .number(maximum), "submitted": .bool(submitted)])
    }
    func testEstimateWheelReviewRetainsChoiceButRejectsNewServerRevision() async throws {
        let session = try session(); var version = 1
        let transport = PlayKitTestTransport { _ in try (self.response(version: version, estimate: self.estimate(maximum: version == 1 ? 10 : 100)), 200) }
        let model = try coordinator(transport, current: { session }); await model.start()
        let wheel = try XCTUnwrap(PlayKitEstimateWheel(segment: model.state?.playKit["estimate"] ?? .null))
        let chosen = try XCTUnwrap(wheel.value(at: 7))
        let detail: [String: PlayWireValue] = ["value": .number(chosen)]
        let cancelled = try model.review(kind: "estimate", action: "SUBMIT_ESTIMATE", detail: detail)
        // Cancelling only discards the immutable review, not the picker selection.
        let reviewedAgain = try model.review(kind: "estimate", action: "SUBMIT_ESTIMATE", detail: detail)
        XCTAssertNotEqual(cancelled.id, reviewedAgain.id); XCTAssertEqual(cancelled.payload, reviewedAgain.payload)
        XCTAssertEqual(transport.requests.count, 1)
        version = 2; await model.refreshAuthoritative()
        let sent = await model.submit(reviewedAgain); XCTAssertFalse(sent)
        XCTAssertEqual(transport.requests.count, 2)
        let replacement = try XCTUnwrap(PlayKitEstimateWheel(segment: model.state?.playKit["estimate"] ?? .null))
        XCTAssertEqual(replacement.value(at: replacement.initialIndex), 50)
    }
    func testEstimateWheelUnknownResultRetriesExactValueWithoutNewChoice() async throws {
        let session = try session(); var writes = 0
        let transport = PlayKitTestTransport { request in
            if request.url?.path.hasSuffix("action") == true {
                writes += 1
                if writes == 1 { throw URLError(.timedOut) }
            }
            return try (self.response(version: writes == 0 ? 1 : 2, estimate: self.estimate(submitted: writes > 0)), 200)
        }
        let model = try coordinator(transport, current: { session }); await model.start()
        let wheel = try XCTUnwrap(PlayKitEstimateWheel(segment: model.state?.playKit["estimate"] ?? .null))
        let selected = try XCTUnwrap(wheel.value(at: wheel.initialIndex))
        let review = try model.review(kind: "estimate", action: "SUBMIT_ESTIMATE", detail: ["value": .number(selected)])
        let sent = await model.submit(review); XCTAssertFalse(sent)
        let frozen = model.pending; await model.recover()
        XCTAssertEqual(model.pending, frozen); XCTAssertEqual(model.phase, "retryable")
        XCTAssertThrowsError(try model.review(kind: "estimate", action: "SUBMIT_ESTIMATE", detail: ["value": .number(8)]))
        await model.retryExact(); XCTAssertNil(model.pending)
        let actions = transport.requests.filter { $0.url?.path.hasSuffix("action") == true }
        XCTAssertEqual(actions.count, 2); XCTAssertEqual(actions[0].httpBody, actions[1].httpBody)
        let body = try JSONDecoder().decode(PlayWireValue.self, from: XCTUnwrap(actions[0].httpBody))
        XCTAssertEqual(Set(body["payload"].object?.keys.map { $0 } ?? []), ["value"])
        XCTAssertEqual(body["payload"]["value"].double, selected)
        let duplicate = await model.submit(review); XCTAssertFalse(duplicate)
        XCTAssertEqual(transport.requests.filter { $0.url?.path.hasSuffix("action") == true }.count, 2)
    }
    func testEstimateWheelRevokedOwnerCannotSubmitSelectedValue() async throws {
        var current: PlayExperienceSession? = try session()
        let transport = PlayKitTestTransport { _ in try (self.response(version: 1, estimate: self.estimate()), 200) }
        let model = try coordinator(transport, current: { current }); await model.start()
        let wheel = try XCTUnwrap(PlayKitEstimateWheel(segment: model.state?.playKit["estimate"] ?? .null))
        let review = try model.review(kind: "estimate", action: "SUBMIT_ESTIMATE", detail: ["value": .number(try XCTUnwrap(wheel.value(at: wheel.initialIndex)))])
        current = try session(2)
        let sent = await model.submit(review); XCTAssertFalse(sent)
        XCTAssertFalse(model.isCurrent); XCTAssertEqual(transport.requests.count, 1)
    }
    private func dice(rolled: Bool) -> PlayWireValue {
        .object(["diceCount": .int(2), "rolled": .bool(rolled), "sum": .int(rolled ? 9 : 0),
                 "pips": .array(rolled ? [.int(5), .int(4)] : [])])
    }
    private func diceTotal(_ model: PlayAdvancedCoordinator) -> Int? {
        guard let state = model.state else { return nil }
        return PlayKitScreenProjection(kind: .diceRoll, segment: ChapterInlineKitSelection.segment(.diceRoll, in: state)).diceTotal
    }
    func testDiceUnknownRefreshShowsOnlyServerSumAndRetainsExactReplay() async throws {
        let session = try session(); var writes = 0
        let transport = PlayKitTestTransport { request in
            if request.url?.path.hasSuffix("action") == true {
                writes += 1
                if writes == 1 { throw URLError(.timedOut) }
            }
            return try (self.response(version: writes == 0 ? 1 : 2, dice: self.dice(rolled: writes > 0)), 200)
        }
        let model = try coordinator(transport, current: { session }); await model.start()
        XCTAssertNil(diceTotal(model))
        let review = try model.review(kind: "diceRoll", action: "ROLL_DICE")
        XCTAssertTrue(review.payload.isEmpty)
        let sent = await model.submit(review); XCTAssertFalse(sent)
        XCTAssertNil(diceTotal(model)); XCTAssertEqual(model.phase, "unknown")
        let frozen = model.pending
        await model.recover()
        XCTAssertEqual(diceTotal(model), 9); XCTAssertEqual(model.pending, frozen)
        XCTAssertEqual(model.phase, "retryable"); XCTAssertFalse(model.canInteract)
        await model.retryExact()
        XCTAssertEqual(diceTotal(model), 9); XCTAssertNil(model.pending)
        let actions = transport.requests.filter { $0.url?.path.hasSuffix("action") == true }
        XCTAssertEqual(actions.count, 2); XCTAssertEqual(actions[0].httpBody, actions[1].httpBody)
        // Reopening/refreshing a rolled result does not authorize another roll.
        await model.refreshAuthoritative(); XCTAssertEqual(diceTotal(model), 9)
        XCTAssertThrowsError(try model.review(kind: "diceRoll", action: "ROLL_DICE"))
        let duplicate = await model.submit(review); XCTAssertFalse(duplicate)
        XCTAssertEqual(transport.requests.filter { $0.url?.path.hasSuffix("action") == true }.count, 2)
    }
    func testDiceCancelledReviewHasNoRollAndRevokedReviewCannotDispatch() async throws {
        var current: PlayExperienceSession? = try session()
        let transport = PlayKitTestTransport { _ in try (self.response(version: 1, dice: self.dice(rolled: false)), 200) }
        let model = try coordinator(transport, current: { current }); await model.start()
        let abandoned = try model.review(kind: "diceRoll", action: "ROLL_DICE")
        XCTAssertNil(diceTotal(model)); XCTAssertEqual(transport.requests.count, 1)
        // Cancelling a review is local; a later fresh review still has no result.
        let fresh = try model.review(kind: "diceRoll", action: "ROLL_DICE")
        XCTAssertNotEqual(abandoned.id, fresh.id)
        current = try session(2)
        let sent = await model.submit(fresh); XCTAssertFalse(sent)
        XCTAssertNil(diceTotal(model)); XCTAssertEqual(transport.requests.count, 1)
    }
    func testDiceResponseAfterOwnerRevocationCannotPublishAnOutcome() async throws {
        var current: PlayExperienceSession? = try session()
        let transport = PlayKitTestTransport { request in
            if request.url?.path.hasSuffix("action") == true {
                current = nil
                return try (self.response(version: 2, dice: self.dice(rolled: true)), 200)
            }
            return try (self.response(version: 1, dice: self.dice(rolled: false)), 200)
        }
        let model = try coordinator(transport, current: { current }); await model.start()
        let review = try model.review(kind: "diceRoll", action: "ROLL_DICE")
        let sent = await model.submit(review); XCTAssertFalse(sent)
        XCTAssertFalse(model.isCurrent); XCTAssertNil(model.state); XCTAssertNil(diceTotal(model))
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
    func testExactAdvancedRequestUsesStableNestedJSONKeyOrder() async throws {
        let transport = PlayKitTestTransport { _ in try (self.response(version: 2), 200) }
        let api = PlayExperienceService(configuration: try APIConfiguration(baseURL: URL(string: "https://example.com")!),
            transport: transport, enabled: [.advanced])
        let pending = PlayAdvancedPending(sessionID: 1, version: 1, key: "synthetic-replay-key",
            action: "SUBMIT_CLASSIFY", payload: ["placement": .object(["b": .string("two"), "a": .string("one")])])
        for _ in 0..<8 { _ = try await api.advancedAction(pending, token: "synthetic-token") }
        let expected = #"{"action":"SUBMIT_CLASSIFY","idempotencyKey":"synthetic-replay-key","payload":{"placement":{"a":"one","b":"two"}},"sessionId":1,"version":1}"#
        XCTAssertEqual(transport.requests.count, 8)
        for request in transport.requests {
            XCTAssertEqual(request.url?.path, "/api/play/advanced/action")
            XCTAssertEqual(request.httpBody, Data(expected.utf8))
        }
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
