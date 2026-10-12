import XCTest
@testable import Questify

@MainActor final class ClubAIDesignFeedbackViewTests: XCTestCase {
    private func prepared() async throws -> Fixture {
        let f = Fixture(); await f.flow.generate(try .init(idea: "Synthetic idea")); return f
    }
    private func ready(_ f: Fixture) throws -> (ClubAIDesignFeedbackModel, ClubAIDesignFeedbackState.Permit) {
        let model = ClubAIDesignFeedbackModel(), context = try XCTUnwrap(f.snapshot())
        model.bind(context); model.appear(); return (model, try XCTUnwrap(model.state.permit(context, generating: false)))
    }
    func testActualFlowCurrentPromoWritesExactTextOnce() async throws {
        let f = try await prepared(), (model, permit) = try ready(f); var writes: [String] = []
        model.copy(permit, current: f.snapshot, generating: { f.generating }) { writes.append($0); return true }
        XCTAssertEqual(writes, [" Exact\npromo 👋 "]); XCTAssertEqual(model.state.phase, .copied); XCTAssertEqual(f.generator.calls, 1)
    }
    func testWriterFailureIsVisibleAndRetryIsExplicit() async throws {
        let f = try await prepared(), (model, permit) = try ready(f); var writes = 0
        model.copy(permit, current: f.snapshot, generating: { false }) { _ in writes += 1; return false }
        XCTAssertEqual(writes, 1); XCTAssertEqual(model.state.phase, .failed)
        model.copy(permit, current: f.snapshot, generating: { false }) { _ in writes += 1; return true }
        XCTAssertEqual(writes, 2); XCTAssertEqual(model.state.phase, .copied)
    }
    func testStaleOperationCannotWriteBeforeViewRebind() async throws {
        let f = try await prepared(), (model, permit) = try ready(f); f.operation = UUID(); var writes = 0
        model.copy(permit, current: f.snapshot, generating: { false }) { _ in writes += 1; return true }
        XCTAssertEqual(writes, 0)
    }
    func testGeneratingFlagClosesPreTaskWindow() async throws {
        let f = try await prepared(), (model, permit) = try ready(f); f.generating = true; var writes = 0
        model.copy(permit, current: f.snapshot, generating: { f.generating }) { _ in writes += 1; return true }
        XCTAssertEqual(writes, 0)
    }
    func testLiveIdentityChangeRejectsCachedViewSession() async throws {
        let f = try await prepared(), (model, permit) = try ready(f); f.currentOwner = nil; var writes = 0
        model.copy(permit, current: f.snapshot, generating: { false }) { _ in writes += 1; return true }
        XCTAssertEqual(writes, 0); XCTAssertNil(f.flow.result)
    }
    func testReplacedGenerationCannotCopyOldRenderedText() async throws {
        let f = try await prepared(), (model, permit) = try ready(f)
        await f.flow.generate(try .init(idea: "Replacement")); var writes = 0
        model.copy(permit, current: f.snapshot, generating: { false }) { _ in writes += 1; return true }
        XCTAssertEqual(writes, 0)
    }
    func testFailedRegenerationRetainsCandidateButRetiresFeedback() async throws {
        let f = try await prepared(), (model, permit) = try ready(f)
        model.copy(permit, current: f.snapshot, generating: { false }) { _ in true }; XCTAssertEqual(model.state.phase, .copied)
        f.operation = UUID(); f.generator.outcome = .unavailable(""); await f.flow.generate(try .init(idea: "Replacement"))
        XCTAssertNotNil(f.flow.result); model.bind(try XCTUnwrap(f.snapshot())); XCTAssertEqual(model.state.phase, .idle)
        var writes = 0; model.copy(permit, current: f.snapshot, generating: { false }) { _ in writes += 1; return true }; XCTAssertEqual(writes, 0)
    }
    func testCancelRemovesCurrentResultBeforeCopy() async throws {
        let f = try await prepared(), (model, permit) = try ready(f); f.flow.cancel(); var writes = 0
        model.copy(permit, current: f.snapshot, generating: { false }) { _ in writes += 1; return true }; XCTAssertEqual(writes, 0)
    }
    func testBackgroundAndLeaveRetireSameContextPermits() async throws {
        let f = try await prepared(), (model, permit) = try ready(f); model.leave(); model.appear(); var writes = 0
        model.copy(permit, current: f.snapshot, generating: { false }) { _ in writes += 1; return true }; XCTAssertEqual(writes, 0)
    }
    func testReentrantOperationChangeNeverReportsOldSuccess() async throws {
        let f = try await prepared(), (model, permit) = try ready(f)
        model.copy(permit, current: f.snapshot, generating: { false }) { _ in f.operation = UUID(); return true }
        XCTAssertEqual(model.state.phase, .idle)
    }
    func testIdentityRejectionNeverExposesPreviousCopy() async throws {
        let f = try await prepared(), (model, permit) = try ready(f); f.generator.outcome = .rejected("请先登录"); await f.flow.generate(try .init(idea: "Again")); var writes = 0
        model.copy(permit, current: f.snapshot, generating: { false }) { _ in writes += 1; return true }; XCTAssertEqual(writes, 0)
    }
    func testMismatchedAndEmptyCopyNeverProject() async throws {
        let f = try await prepared()
        for text in ["", "Wrong copy", "Exact\npromo 👋"] {
            XCTAssertNil(ClubAIDesignPromoSnapshot.current(clubID: 41, session: f.owner, operationID: f.operation,
                generating: false, flow: f.flow, expectedGeneration: f.renderedGeneration, expectedCopy: text))
        }
    }
    @MainActor private final class Fixture {
        let owner = PublishingSession(namespace: "synthetic", accountID: 7, epoch: UUID(), role: "club", region: .china)
        lazy var currentOwner: PublishingSession? = owner
        let generator = Generator()
        lazy var flow = ClubAIDesignFlow(generator: generator, current: { [weak self] in self?.currentOwner })
        var operation = UUID(), generating = false
        var renderedGeneration = 1
        func snapshot() -> ClubAIDesignFeedbackContext? {
            ClubAIDesignPromoSnapshot.current(clubID: 41, session: owner, operationID: operation,
                generating: generating, flow: flow, expectedGeneration: renderedGeneration, expectedCopy: " Exact\npromo 👋 ")
        }
    }
    @MainActor private final class Generator: ClubAIDesignGenerating {
        var calls = 0
        var outcome: PublishingAuxiliaryOutcome = .acknowledged(.object(["plan": .object(["title": .string("Synthetic plan")]), "promoCopy": .string(" Exact\npromo 👋 ")]))
        func generate(_ input: ClubAIDesignInput, session: PublishingSession) async -> PublishingAuxiliaryOutcome { calls += 1; return outcome }
    }
}
