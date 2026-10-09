import XCTest
@testable import QuestifyCore

@MainActor final class ClubAIDesignCandidateRetentionTests: XCTestCase {
    private func session() -> PublishingSession { .init(namespace: "synthetic", accountID: 7, epoch: UUID(), role: "club", region: .china) }
    private func input(_ idea: String = "Original idea", style: String = "Quiet", minutes: Int? = 90) throws -> ClubAIDesignInput {
        try .init(idea: idea, style: style, minutes: minutes)
    }
    func testSuccessfulResultKeepsExactInputAndGeneration() async throws {
        let owner = session(), generator = Generator(); let flow = ClubAIDesignFlow(generator: generator, current: { owner })
        let value = try input(); await flow.generate(value)
        XCTAssertEqual(flow.resultInput, value); XCTAssertNotNil(flow.resultGeneration); XCTAssertTrue(flow.canAdoptResult)
        XCTAssertFalse(flow.resultIsPrevious(comparedTo: value))
    }
    func testFailedRegenerationKeepsOldResultAndSourceForExplicitAdoption() async throws {
        let owner = session(), generator = Generator(); let flow = ClubAIDesignFlow(generator: generator, current: { owner })
        let original = try input(); await flow.generate(original); let before = flow.result; let generation = try XCTUnwrap(flow.resultGeneration)
        generator.outcome = .unavailable(""); let newer = try input("New idea", style: "Lively", minutes: 45); await flow.generate(newer)
        XCTAssertEqual(flow.result, before); XCTAssertEqual(flow.resultInput, original); XCTAssertEqual(flow.resultGeneration, generation)
        XCTAssertTrue(flow.resultIsPrevious(comparedTo: newer)); XCTAssertEqual(flow.failure, .unavailable)
        let draft = try flow.adopt(clubID: 4, generation: generation)
        XCTAssertEqual(draft.name, "Original candidate"); XCTAssertEqual(draft.clubID, 4)
        XCTAssertFalse(draft.chapters[0].nodes[0].hasUsableCoordinates)
    }
    func testParseErrorDoesNotOverwritePreviousValidPlan() async throws {
        let owner = session(), generator = Generator(); let flow = ClubAIDesignFlow(generator: generator, current: { owner })
        let value = try input(); await flow.generate(value)
        generator.outcome = .acknowledged(.object(["parseError": .string(""), "plan": .object(["title": .string("Must not replace")])]))
        await flow.generate(value)
        XCTAssertEqual(flow.result?.title, "Original candidate"); XCTAssertEqual(flow.failure, .parse); XCTAssertTrue(flow.resultIsPrevious(comparedTo: value))
    }
    func testBusyCannotAdoptAndNewSuccessReplacesValueWithItsInputTogether() async throws {
        let owner = session(), generator = Generator(); let flow = ClubAIDesignFlow(generator: generator, current: { owner })
        await flow.generate(try input()); let oldGeneration = try XCTUnwrap(flow.resultGeneration)
        let newInput = try input("New idea", style: "Lively", minutes: 45); generator.hold = true
        generator.outcome = .acknowledged(Generator.plan("New candidate"))
        let started = expectation(description: "Started"); generator.onStart = { started.fulfill() }
        let task = Task { await flow.generate(newInput) }; await fulfillment(of: [started], timeout: 1)
        XCTAssertEqual(flow.result?.title, "Original candidate"); XCTAssertFalse(flow.canAdoptResult)
        XCTAssertThrowsError(try flow.adopt(clubID: 4, generation: oldGeneration))
        generator.finish(); await task.value
        XCTAssertEqual(flow.result?.title, "New candidate"); XCTAssertEqual(flow.resultInput, newInput)
        XCTAssertNotEqual(flow.resultGeneration, oldGeneration); XCTAssertFalse(flow.resultIsPrevious(comparedTo: newInput))
    }
    func testStaleRenderedGenerationCannotAdoptTheReplacement() async throws {
        let owner = session(), generator = Generator(); let flow = ClubAIDesignFlow(generator: generator, current: { owner })
        let value = try input(); await flow.generate(value); let oldGeneration = try XCTUnwrap(flow.resultGeneration)
        generator.outcome = .acknowledged(Generator.plan("Replacement")); await flow.generate(value)
        XCTAssertThrowsError(try flow.adopt(clubID: 4, generation: oldGeneration))
        XCTAssertEqual(try flow.adopt(clubID: 4, generation: XCTUnwrap(flow.resultGeneration)).name, "Replacement")
    }
    func testUnknownLockSurvivesLocalAdoptionOfEarlierResult() async throws {
        let owner = session(), generator = Generator(); let flow = ClubAIDesignFlow(generator: generator, current: { owner })
        let value = try input(); await flow.generate(value); let generation = try XCTUnwrap(flow.resultGeneration)
        generator.outcome = .unknown; await flow.generate(value)
        XCTAssertFalse(flow.canGenerate); XCTAssertEqual(flow.failure, .unknown); XCTAssertTrue(flow.canAdoptResult)
        _ = try flow.adopt(clubID: 4, generation: generation); await flow.generate(value)
        XCTAssertEqual(flow.failure, .unknown); XCTAssertEqual(generator.calls, 2)
    }
    func testQuotaLockDoesNotDiscardOldResultOrAllowAnotherGeneration() async throws {
        let owner = session(), generator = Generator(); let flow = ClubAIDesignFlow(generator: generator, current: { owner })
        let value = try input(); await flow.generate(value); generator.outcome = .rejected("今日AI次数已用完"); await flow.generate(value)
        XCTAssertEqual(flow.failure, .quota); XCTAssertFalse(flow.canGenerate); XCTAssertNotNil(flow.result)
        await flow.generate(value); XCTAssertEqual(generator.calls, 2); XCTAssertEqual(flow.failure, .quota)
    }
    func testIdentityRejectionDoesNotExposeOrAdoptOldResult() async throws {
        let owner = session(), generator = Generator(); let flow = ClubAIDesignFlow(generator: generator, current: { owner })
        let value = try input(); await flow.generate(value); generator.outcome = .rejected("请先登录"); await flow.generate(value)
        XCTAssertEqual(flow.failure, .identity); XCTAssertFalse(flow.canGenerate); XCTAssertNil(flow.result)
        XCTAssertNil(flow.resultInput); XCTAssertFalse(flow.canAdoptResult); XCTAssertThrowsError(try flow.adopt(clubID: 4))
    }
    func testObservedOwnerChangePermanentlyRemovesPriorProjection() async throws {
        let original = session(); var current: PublishingSession? = original; let generator = Generator()
        let flow = ClubAIDesignFlow(generator: generator, current: { current }); await flow.generate(try input())
        current = nil; XCTAssertNil(flow.result); current = original
        XCTAssertNil(flow.result); XCTAssertNil(flow.resultInput); XCTAssertFalse(flow.canGenerate)
        XCTAssertThrowsError(try flow.adopt(clubID: 4))
    }
    func testCancelRetiresPreviousResultAndLateReplacement() async throws {
        let owner = session(), generator = Generator(); let flow = ClubAIDesignFlow(generator: generator, current: { owner })
        let value = try input(); await flow.generate(value); generator.hold = true
        let started = expectation(description: "Started"); generator.onStart = { started.fulfill() }
        let task = Task { await flow.generate(value) }; await fulfillment(of: [started], timeout: 1)
        flow.cancel(); generator.finish(); await task.value
        XCTAssertNil(flow.result); XCTAssertNil(flow.resultInput); XCTAssertNil(flow.resultGeneration); XCTAssertFalse(flow.busy)
    }
    func testChangedStyleMinutesAndInvalidFormAreClearlyPrevious() async throws {
        let owner = session(), generator = Generator(); let flow = ClubAIDesignFlow(generator: generator, current: { owner })
        await flow.generate(try input())
        XCTAssertTrue(flow.resultIsPrevious(comparedTo: try input(style: "New style")))
        XCTAssertTrue(flow.resultIsPrevious(comparedTo: try input(minutes: nil)))
        XCTAssertTrue(flow.resultIsPrevious(comparedTo: nil)); XCTAssertEqual(generator.calls, 1)
    }
    func testUnavailableGeneratorDoesNotCreateResultOrSource() async throws {
        let owner = session(); let flow = ClubAIDesignFlow(generator: nil, current: { owner }); await flow.generate(try input())
        XCTAssertNil(flow.result); XCTAssertNil(flow.resultInput); XCTAssertFalse(flow.canAdoptResult)
    }
    @MainActor private final class Generator: ClubAIDesignGenerating {
        var outcome: PublishingAuxiliaryOutcome = .acknowledged(Generator.plan("Original candidate"))
        var calls = 0; var hold = false; var onStart: (() -> Void)?; var waiting: CheckedContinuation<PublishingAuxiliaryOutcome, Never>?
        static func plan(_ title: String) -> ProjectEditJSON {
            .object(["plan": .object(["title": .string(title), "storyline": .string("Synthetic story"),
                "nodes": .array([.object(["merchantName": .string("Suggested stop"), "address": .string("Suggested address"), "task": .string("Observe")])])])])
        }
        func generate(_ input: ClubAIDesignInput, session: PublishingSession) async -> PublishingAuxiliaryOutcome {
            calls += 1; if hold { return await withCheckedContinuation { waiting = $0; onStart?() } }
            return outcome
        }
        func finish() { let pending = waiting; waiting = nil; pending?.resume(returning: outcome) }
    }
}
