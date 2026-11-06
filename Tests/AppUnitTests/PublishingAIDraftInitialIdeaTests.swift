import XCTest
import SwiftUI
import UIKit
@testable import Questify

@MainActor final class PublishingAIDraftInitialIdeaTests: XCTestCase {
    private final class Client: PublishingAIDraftServing {
        var session: PublishingSession? = .init(namespace: "synthetic-seed", accountID: 7, epoch: UUID(), role: "player", region: .china)
        var canGenerate = true
        var reads = 0
        var ideas: [String] = []
        var products: [ProjectEditProduct] = []
        var cancellations = 0
        func quota() async throws -> PublishingAIQuota {
            reads += 1
            return try .init(.object(["limited": .bool(true), "remaining": .number(4)]))
        }
        func generate(idea: String, product: ProjectEditProduct) async throws -> PublishingAIThemeDraft {
            ideas.append(idea); products.append(product)
            return try .init(.object(["draft": .object(["title": .string("Synthetic candidate"), "storyline": .string("Synthetic story"),
                "nodes": .array([.object(["merchantName": .string("Suggested stop"), "task": .string("Observe")])])])]), product: product)
        }
        func cancel() { cancellations += 1 }
    }
    func testDefaultInitializerPreservesExistingEmptyPrompt() {
        let model = PublishingAIDraftModel(client: nil, product: .city)
        XCTAssertEqual(model.flow.idea, ""); XCTAssertNil(model.flow.candidate)
        XCTAssertFalse(model.flow.canGenerate)
    }
    func testSeedIsExactLocalTextWithoutAnyServiceAction() {
        let client = Client(), original = "  老城 e\u{301} ☕\n"
        let model = PublishingAIDraftModel(client: client, product: .city, initialIdea: original)
        XCTAssertEqual(Data(model.flow.idea.utf8), Data(original.utf8))
        XCTAssertEqual(client.reads, 0); XCTAssertTrue(client.ideas.isEmpty); XCTAssertEqual(client.cancellations, 0)
        XCTAssertNil(model.flow.candidate)
    }
    func testUnconfiguredSeedDoesNotCreateGenerationPermission() async {
        let model = PublishingAIDraftModel(client: nil, product: .city, initialIdea: "Coffee walk")
        XCTAssertTrue(model.flow.canUseIdeaSuggestion); XCTAssertFalse(model.flow.canGenerate)
        await model.flow.generate()
        XCTAssertEqual(model.flow.idea, "Coffee walk"); XCTAssertNil(model.flow.candidate)
        XCTAssertEqual(model.flow.messageKey, "contextPublish.ai.unavailable")
    }
    func testExplicitGenerateUsesEditedPromptAndOriginalProduct() async {
        let client = Client(), model = PublishingAIDraftModel(client: nil, product: .city)
        XCTAssertFalse(model.flow.canGenerate)
        let seeded = PublishingAIDraftModel(client: client, product: .freeExplore, initialIdea: "Initial")
        seeded.flow.idea = "  User edited idea  "
        await seeded.flow.loadQuota()
        XCTAssertEqual(seeded.flow.idea, "  User edited idea  "); XCTAssertTrue(client.ideas.isEmpty)
        await seeded.flow.generate()
        XCTAssertEqual(client.ideas, ["User edited idea"]); XCTAssertEqual(client.products, [.freeExplore])
        XCTAssertEqual(seeded.flow.candidateSourceIdea, "User edited idea")
        XCTAssertEqual(seeded.flow.candidate?.draft.product, .freeExplore)
        XCTAssertTrue(seeded.flow.candidate?.draft.nodes.allSatisfy { $0.confirmedPlace == nil } == true)
    }
    func testOversizedSeedRetainsOriginalValidationWithoutTruncationOrDispatch() async {
        let client = Client(), idea = String(repeating: "字", count: 301)
        let model = PublishingAIDraftModel(client: client, product: .city, initialIdea: idea)
        await model.flow.generate()
        XCTAssertEqual(model.flow.idea, idea); XCTAssertTrue(client.ideas.isEmpty)
        XCTAssertEqual(model.flow.messageKey, "contextPublish.ai.promptRequired")
    }
    func testAccountChangeAndCloseDoNotReseedOrReviveOldFlow() async {
        let client = Client(), model = PublishingAIDraftModel(client: nil, product: .city)
        model.flow.close(); XCTAssertEqual(model.flow.idea, "")
        let seeded = PublishingAIDraftModel(client: client, product: .city, initialIdea: "Original account")
        client.session = .init(namespace: "synthetic-seed", accountID: 8, epoch: UUID(), role: "player", region: .china)
        await seeded.flow.generate()
        XCTAssertTrue(client.ideas.isEmpty); XCTAssertFalse(seeded.flow.canGenerate)
        seeded.flow.close(); XCTAssertEqual(seeded.flow.idea, ""); XCTAssertEqual(client.cancellations, 1)
        await seeded.flow.loadQuota(); XCTAssertEqual(seeded.flow.idea, ""); XCTAssertEqual(client.reads, 0)
    }
    func testSheetSupportsDefaultAndSeededCallersWithoutImplicitAdoption() {
        for idea in ["", "Local inspiration"] {
            let client = Client(); var adoptions = 0
            let host = UIHostingController(rootView: PublishingAIDraftSheet(client: client, product: .city, initialIdea: idea) { _ in adoptions += 1 })
            host.loadViewIfNeeded()
            XCTAssertEqual(adoptions, 0); XCTAssertTrue(client.ideas.isEmpty)
        }
    }
}
