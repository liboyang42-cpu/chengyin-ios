import XCTest
import SwiftUI
import UIKit
@testable import Questify

@MainActor final class ClubAIDesignCandidateRetentionAppTests: XCTestCase {
    private let owner = PublishingSession(namespace: "synthetic", accountID: 7, epoch: UUID(), role: "club", region: .china)
    func testConstructionDoesNotGenerateOrAdopt() {
        let generator = Generator(); let flow = ClubAIDesignFlow(generator: generator, current: { self.owner }); var adopted = false
        let host = UIHostingController(rootView: ClubAIDesignView(clubID: 4, session: owner, flow: flow) { _ in adopted = true })
        host.loadViewIfNeeded(); XCTAssertEqual(generator.calls, 0); XCTAssertFalse(adopted)
    }
    func testRetainedPlanConstructsWithOriginalInputsAndExplicitAdoptionOnly() async throws {
        let generator = Generator(); let flow = ClubAIDesignFlow(generator: generator, current: { self.owner })
        let original = try ClubAIDesignInput(idea: "Original", style: "Quiet", minutes: 90); await flow.generate(original)
        generator.fail = true; await flow.generate(try .init(idea: "Changed", style: "Lively", minutes: 45))
        var adopted = false
        let host = UIHostingController(rootView: ClubAIDesignView(clubID: 4, session: owner, flow: flow) { _ in adopted = true }
            .environment(\.locale, Locale(identifier: "zh-Hans")).dynamicTypeSize(.accessibility5))
        host.loadViewIfNeeded(); XCTAssertFalse(adopted); XCTAssertEqual(flow.resultInput, original); XCTAssertEqual(generator.calls, 2)
    }
    func testUnknownLockStillPreventsGenerationAfterReadingRetainedPlan() async throws {
        let generator = Generator(); let flow = ClubAIDesignFlow(generator: generator, current: { self.owner })
        let input = try ClubAIDesignInput(idea: "Original"); await flow.generate(input)
        generator.fail = true; await flow.generate(input)
        XCTAssertEqual(flow.failure, .unknown); XCTAssertNotNil(flow.result); XCTAssertFalse(flow.canGenerate)
        await flow.generate(input); XCTAssertEqual(generator.calls, 2)
    }
    @MainActor private final class Generator: ClubAIDesignGenerating {
        var calls = 0; var fail = false
        func generate(_ input: ClubAIDesignInput, session: PublishingSession) async -> PublishingAuxiliaryOutcome {
            calls += 1
            return fail ? .unknown : .acknowledged(.object(["plan": .object(["title": .string("Synthetic plan"), "storyline": .string("Synthetic story")])]))
        }
    }
}
