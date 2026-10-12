import XCTest
@testable import QuestifyCore

@MainActor final class PublishingAIPromptSuggestionTests: XCTestCase {
    func testSourceSuggestionsAreLocalEditableAndNeverGrantGeneration() async {
        XCTAssertEqual(PublishingAIPromptSuggestion.allCases.map { $0.text(languageCode:"zh-Hans") },
                       ["老城建筑与咖啡","周末亲子探险","雨天室内漫游"])
        XCTAssertEqual(Set(PublishingAIPromptSuggestion.allCases.map(\.id)).count,3)
        let flow = PublishingAIDraftFlow(client:nil,product:.city)
        await flow.generate(); XCTAssertNotNil(flow.messageKey)
        let action = flow.ideaSuggestionAction(.oldTown,languageCode:"en-US")
        XCTAssertTrue(action()); XCTAssertFalse(action())
        XCTAssertEqual(flow.idea,"Old-town architecture and coffee"); XCTAssertNil(flow.messageKey)
        XCTAssertFalse(flow.canGenerate); XCTAssertNil(flow.candidate)
        flow.idea += " at sunset"; XCTAssertTrue(flow.idea.hasSuffix(" at sunset"))
        flow.close(); XCTAssertFalse(flow.canUseIdeaSuggestion)
    }
    func testPromptChangesCloseAndOwnerChangesRetireOldActions() {
        let client = Stub(), flow = PublishingAIDraftFlow(client:nil,product:.city)
        let old = flow.ideaSuggestionAction(.oldTown,languageCode:"zh")
        flow.idea = "Handwritten"; XCTAssertFalse(old()); XCTAssertEqual(flow.idea,"Handwritten")
        let closed = flow.ideaSuggestionAction(.rainyDay,languageCode:"zh"); flow.close(); XCTAssertFalse(closed())
        let owned = PublishingAIDraftFlow(client:client,product:.freeExplore)
        let stale = owned.ideaSuggestionAction(.familyWeekend,languageCode:"zh")
        client.session = .init(namespace:"fixture",accountID:2,epoch:UUID(),role:"player",region:.china)
        XCTAssertFalse(stale()); XCTAssertFalse(owned.canUseIdeaSuggestion); XCTAssertEqual(client.calls,0)
    }
    func testExistingGenerationCandidateAndQuotaAreNotChangedBySuggestions() async throws {
        let client = Stub()
        let owned = PublishingAIDraftFlow(client:client,product:.freeExplore)
        await owned.loadQuota(); let quota = owned.quota
        XCTAssertTrue(owned.ideaSuggestionAction(.familyWeekend,languageCode:"en")())
        XCTAssertEqual(client.calls,0); XCTAssertEqual(owned.quota,quota)
        owned.idea += " with friends"
        let stale = owned.ideaSuggestionAction(.rainyDay,languageCode:"zh")
        client.onGenerate = { XCTAssertFalse(stale()) }
        await owned.generate(); XCTAssertEqual(client.calls,1)
        XCTAssertEqual(client.lastIdea,"A weekend family adventure with friends")
        let candidate = try XCTUnwrap(owned.candidate), source = owned.candidateSourceIdea
        XCTAssertFalse(stale()); XCTAssertFalse(owned.canUseIdeaSuggestion)
        XCTAssertFalse(owned.ideaSuggestionAction(.oldTown,languageCode:"zh")())
        XCTAssertEqual(owned.candidate,candidate); XCTAssertEqual(owned.candidateSourceIdea,source)
        XCTAssertEqual(owned.accept()?.title,"Synthetic route")
    }
    private final class Stub: PublishingAIDraftServing {
        var session: PublishingSession? = .init(namespace:"fixture",accountID:1,epoch:UUID(),role:"player",region:.china)
        var canGenerate = true; var calls = 0; var lastIdea = ""
        var onGenerate: (() -> Void)?
        func quota() async throws -> PublishingAIQuota { try .init(.object(["limited":.bool(true),"remaining":.number(2)])) }
        func generate(idea:String,product:ProjectEditProduct) async throws -> PublishingAIThemeDraft {
            calls += 1; lastIdea = idea; onGenerate?()
            return try .init(.object(["traceId":.string("synthetic"),"draft":.object(["title":.string("Synthetic route"),"storyline":.string("Story"),"nodes":.array([.object(["merchantName":.string("Stop"),"task":.string("Observe")])])])]),product:product)
        }
        func cancel() {}
    }
}
