import XCTest
@testable import QuestifyCore

@MainActor final class PublishingAIDraftFlowTests: XCTestCase {
    func testCurrentThemeRequestCarriesMode() {
        let request = PublishingAssistance.themeForProduct(idea: " walk ", product: .freeExplore).request
        XCTAssertEqual(request.path, "api/ai/theme/draft")
        XCTAssertEqual(request.fields["productType"], .number(2)); XCTAssertEqual(request.fields["idea"], .string("walk"))
    }
    func testGeneratedDraftPreservesTraceAndRequiresEveryPlace() throws {
        let value = try PublishingAIThemeDraft(Self.response, product: .freeExplore)
        XCTAssertEqual(value.draft.product, .freeExplore); XCTAssertEqual(value.traceID, "synthetic-trace")
        XCTAssertEqual(value.draft.subtitle, "Synthetic subtitle")
        XCTAssertNil(value.draft.nodes[0].confirmedPlace)
        XCTAssertThrowsError(try value.draft.professionalSeed())
    }
    func testDisabledFlowCannotCallProvider() async {
        let flow = PublishingAIDraftFlow(client: nil, product: .city)
        flow.idea = "Walk"; await flow.generate(); XCTAssertNil(flow.candidate); XCTAssertFalse(flow.busy)
    }
    func testCancelScrubsCandidateAndNeverApplies() async throws {
        let client = Stub(); let flow = PublishingAIDraftFlow(client: client, product: .city)
        flow.idea = "Walk"; await flow.generate(); XCTAssertNotNil(flow.candidate)
        flow.close(); XCTAssertNil(flow.accept()); XCTAssertEqual(flow.idea, "")
    }
    func testKnownExhaustedQuotaBlocksAIOnly() async {
        let client = Stub(); client.exhausted = true
        let flow = PublishingAIDraftFlow(client: client, product: .city)
        await flow.loadQuota(); flow.idea = "Walk"; await flow.generate()
        XCTAssertEqual(client.calls, 0); XCTAssertEqual(flow.messageKey, "contextPublish.ai.exhausted")
    }
    func testAccountChangeInvalidatesCandidate() async {
        let client = Stub(); let flow = PublishingAIDraftFlow(client: client, product: .city)
        flow.idea = "Walk"; await flow.generate(); client.session = nil
        XCTAssertNil(flow.accept()); XCTAssertFalse(flow.canGenerate)
    }
    static let response: ProjectEditJSON = .object(["traceId": .string("synthetic-trace"), "draft": .object([
        "title": .string("Synthetic route"), "subtitle": .string("Synthetic subtitle"), "storyline": .string("A story"),
        "nodes": .array([.object(["merchantName": .string("Stop"), "task": .string("Observe")])])])])
    private final class Stub: PublishingAIDraftServing {
        var session: PublishingSession? = PublishingSession(namespace: "fixture", accountID: 1, epoch: UUID(), role: "player", region: .china)
        var canGenerate = true; var exhausted = false; var calls = 0
        func quota() async throws -> PublishingAIQuota { try PublishingAIQuota(.object(["limited": .bool(true), "remaining": .number(exhausted ? 0 : 2)])) }
        func generate(idea: String, product: ProjectEditProduct) async throws -> PublishingAIThemeDraft { calls += 1; return try PublishingAIThemeDraft(PublishingAIDraftFlowTests.response, product: product) }
        func cancel() {}
    }
}
