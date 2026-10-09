import XCTest
import SwiftUI
import UIKit
@testable import Questify

@MainActor final class PublishingAIDraftCandidateRetentionAppTests: XCTestCase {
    func testSheetConstructionDoesNotAdoptOrGenerate() {
        let client = Stub(); var adopts = 0
        let host = UIHostingController(rootView: PublishingAIDraftSheet(client: client, product: .city) { _ in adopts += 1 })
        host.loadViewIfNeeded(); XCTAssertEqual(adopts, 0); XCTAssertEqual(client.calls, 0)
    }
    func testFailurePresentationCanStillExplicitlyAdoptOnlyPreviousGeneration() async throws {
        let client = Stub(); let flow = PublishingAIDraftFlow(client: client, product: .city)
        flow.idea = "Original idea"; await flow.generate(); let generation = try XCTUnwrap(flow.candidateGeneration)
        client.fail = true; flow.idea = "New idea"; await flow.generate()
        XCTAssertTrue(flow.candidateIsPrevious); XCTAssertEqual(flow.candidateSourceIdea, "Original idea")
        XCTAssertNotNil(flow.accept(candidateGeneration: generation)); XCTAssertNil(flow.accept(candidateGeneration: generation))
        XCTAssertEqual(client.calls, 2)
    }
    func testDefaultUnavailableSheetStillConstructsWithBothLocales() {
        for locale in ["en", "zh-Hans"] {
            let host = UIHostingController(rootView: PublishingAIDraftSheet(client: nil, product: .city) { _ in XCTFail("Unavailable flow cannot adopt") }
                .environment(\.locale, Locale(identifier: locale)).dynamicTypeSize(.accessibility5))
            host.loadViewIfNeeded()
        }
    }
    @MainActor private final class Stub: PublishingAIDraftServing {
        var session: PublishingSession? = .init(namespace: "synthetic", accountID: 7, epoch: UUID(), role: "player", region: .china)
        var canGenerate = true; var fail = false; var calls = 0
        func quota() async throws -> PublishingAIQuota { try .init(.object(["limited": .bool(true), "remaining": .number(4)])) }
        func generate(idea: String, product: ProjectEditProduct) async throws -> PublishingAIThemeDraft {
            calls += 1; if fail { throw PublishModesError.unavailable }
            return try .init(.object(["draft": .object(["title": .string("Synthetic candidate"), "storyline": .string("Synthetic story"),
                "nodes": .array([.object(["merchantName": .string("Suggested stop"), "task": .string("Observe")])])])]), product: product)
        }
        func cancel() {}
    }
}
