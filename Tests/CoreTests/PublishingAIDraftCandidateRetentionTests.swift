import XCTest
@testable import QuestifyCore

@MainActor final class PublishingAIDraftCandidateRetentionTests: XCTestCase {
    func testSuccessCapturesOriginalIdeaAndGeneration() async {
        let client = Stub(); let flow = PublishingAIDraftFlow(client: client, product: .city)
        flow.idea = "  Original idea  "; await flow.generate()
        XCTAssertEqual(flow.candidateSourceIdea, "Original idea"); XCTAssertNotNil(flow.candidateGeneration)
        XCTAssertFalse(flow.candidateIsPrevious); XCTAssertTrue(flow.canAcceptCandidate)
    }
    func testSecondFailurePreservesPreviousCandidateAndItsSource() async throws {
        let client = Stub(); let flow = PublishingAIDraftFlow(client: client, product: .city)
        flow.idea = "First idea"; await flow.generate(); let candidate = flow.candidate; let generation = flow.candidateGeneration
        client.failure = PublishModesError.uncertain; flow.idea = "Second idea"; await flow.generate()
        XCTAssertEqual(flow.candidate, candidate); XCTAssertEqual(flow.candidateGeneration, generation)
        XCTAssertEqual(flow.candidateSourceIdea, "First idea"); XCTAssertTrue(flow.candidateIsPrevious)
        XCTAssertEqual(flow.messageKey, "contextPublish.ai.failed"); XCTAssertTrue(flow.canAcceptCandidate)
        XCTAssertEqual(flow.accept(candidateGeneration: try XCTUnwrap(generation))?.title, "First candidate")
    }
    func testInvalidGeneratedContractDoesNotDropPreviousDraft() async {
        let client = Stub(); let flow = PublishingAIDraftFlow(client: client, product: .city)
        flow.idea = "Idea"; await flow.generate(); client.malformed = true; await flow.generate()
        XCTAssertEqual(flow.candidate?.draft.title, "First candidate"); XCTAssertTrue(flow.candidateIsPrevious)
        XCTAssertEqual(flow.messageKey, "contextPublish.ai.failed")
    }
    func testBusyShowsPreviousButCannotAdoptItAndSuccessReplacesAtomically() async throws {
        let client = Stub(); let flow = PublishingAIDraftFlow(client: client, product: .city)
        flow.idea = "First idea"; await flow.generate(); let oldGeneration = try XCTUnwrap(flow.candidateGeneration)
        client.hold = true; client.title = "Second candidate"; flow.idea = "Second idea"
        let started = expectation(description: "Second generation started"); client.onGenerate = { started.fulfill() }
        let task = Task { await flow.generate() }; await fulfillment(of: [started], timeout: 1)
        XCTAssertEqual(flow.candidate?.draft.title, "First candidate"); XCTAssertTrue(flow.candidateIsPrevious)
        XCTAssertFalse(flow.canAcceptCandidate); XCTAssertNil(flow.accept(candidateGeneration: oldGeneration))
        client.resume(); await task.value
        XCTAssertEqual(flow.candidate?.draft.title, "Second candidate"); XCTAssertEqual(flow.candidateSourceIdea, "Second idea")
        XCTAssertNotEqual(flow.candidateGeneration, oldGeneration); XCTAssertFalse(flow.candidateIsPrevious)
    }
    func testStaleRenderedAdoptionCannotAcceptNewerCandidate() async throws {
        let client = Stub(); let flow = PublishingAIDraftFlow(client: client, product: .city)
        flow.idea = "Idea"; await flow.generate(); let first = try XCTUnwrap(flow.candidateGeneration)
        client.title = "Newer candidate"; await flow.generate()
        XCTAssertNil(flow.accept(candidateGeneration: first)); XCTAssertNotNil(flow.candidate)
        XCTAssertEqual(flow.accept(candidateGeneration: try XCTUnwrap(flow.candidateGeneration))?.title, "Newer candidate")
    }
    func testEditingIdeaDoesNotRelabelPreviousResultAsGeneratedForNewInput() async {
        let client = Stub(); let flow = PublishingAIDraftFlow(client: client, product: .city)
        flow.idea = "Original"; await flow.generate(); flow.idea = "Changed"
        XCTAssertEqual(flow.candidateSourceIdea, "Original"); XCTAssertTrue(flow.candidateIsPrevious)
        XCTAssertEqual(client.calls, 1)
    }
    func testObservedAccountChangePermanentlyRetiresOldCandidate() async {
        let client = Stub(); let flow = PublishingAIDraftFlow(client: client, product: .city)
        flow.idea = "Idea"; await flow.generate(); let oldSession = client.session
        client.session = nil; XCTAssertNil(flow.candidate); XCTAssertFalse(flow.canAcceptCandidate)
        client.session = oldSession
        XCTAssertNil(flow.candidate); XCTAssertNil(flow.candidateSourceIdea); XCTAssertNil(flow.candidateGeneration)
        XCTAssertFalse(flow.canGenerate); XCTAssertNil(flow.accept())
    }
    func testCloseAndLateResponseCannotRestoreCandidateOrOrigin() async {
        let client = Stub(); let flow = PublishingAIDraftFlow(client: client, product: .city)
        flow.idea = "Original"; await flow.generate(); client.hold = true
        let started = expectation(description: "Generation started"); client.onGenerate = { started.fulfill() }
        let task = Task { await flow.generate() }; await fulfillment(of: [started], timeout: 1)
        flow.close(); client.resume(); await task.value
        XCTAssertNil(flow.candidate); XCTAssertNil(flow.candidateSourceIdea); XCTAssertNil(flow.candidateGeneration); XCTAssertNil(flow.accept())
    }
    func testQuotaExhaustionBlocksGenerationButDoesNotDiscardReviewableCandidate() async {
        let client = Stub(); client.remaining = 0
        let flow = PublishingAIDraftFlow(client: client, product: .city); flow.idea = "Idea"; await flow.generate()
        XCTAssertEqual(flow.quota?.remaining, 0); XCTAssertFalse(flow.canGenerate); XCTAssertTrue(flow.canAcceptCandidate)
        XCTAssertNotNil(flow.candidate); XCTAssertEqual(client.calls, 1)
    }
    func testUnavailableClientHasNoAdoptableCandidate() {
        let flow = PublishingAIDraftFlow(client: nil, product: .city)
        XCTAssertNil(flow.candidate); XCTAssertFalse(flow.canAcceptCandidate); XCTAssertFalse(flow.candidateIsPrevious)
    }
    @MainActor private final class Stub: PublishingAIDraftServing {
        var session: PublishingSession? = .init(namespace: "synthetic", accountID: 7, epoch: UUID(), role: "player", region: .china)
        var canGenerate = true; var title = "First candidate"; var calls = 0; var remaining = 4
        var failure: Error?; var malformed = false; var hold = false; var onGenerate: (() -> Void)?
        var pending: CheckedContinuation<Void, Never>?
        func quota() async throws -> PublishingAIQuota {
            try .init(.object(["limited": .bool(true), "limit": .number(4), "remaining": .number(Decimal(remaining))]))
        }
        func generate(idea: String, product: ProjectEditProduct) async throws -> PublishingAIThemeDraft {
            calls += 1; if hold { await withCheckedContinuation { pending = $0; onGenerate?() } }
            if let failure { throw failure }
            if malformed { return try .init(.object(["draft": .null]), product: product) }
            return try .init(.object(["draft": .object(["title": .string(title), "storyline": .string("Synthetic story"),
                "nodes": .array([.object(["merchantName": .string("Suggested stop"), "task": .string("Observe")])])])]), product: product)
        }
        func resume() { let value = pending; pending = nil; value?.resume() }
        func cancel() {}
    }
}
