import XCTest
import SwiftUI
import UIKit
@testable import Questify

@MainActor final class PublishingAIQuotaSectionTests: XCTestCase {
    func testUnavailableSectionConstructsWithoutReadOrProvider() {
        let flow = PublishingAIDraftFlow(client: nil, product: .city)
        let host = UIHostingController(rootView: Form { PublishingAIQuotaSection(flow: flow) })
        host.loadViewIfNeeded()
        XCTAssertEqual(flow.quotaReadState, .unavailable); XCTAssertFalse(flow.canRefreshQuota)
    }
    func testFreshAndStaleSectionsKeepServerCountsAndNoGeneratedCandidate() async throws {
        let client = Stub(); let flow = PublishingAIDraftFlow(client: client, product: .city)
        await flow.loadQuota()
        let fresh = UIHostingController(rootView: Form { PublishingAIQuotaSection(flow: flow) }.environment(\.locale, Locale(identifier: "zh-Hans")))
        fresh.loadViewIfNeeded(); XCTAssertEqual(flow.quota?.limit, 4); XCTAssertEqual(flow.quota?.remaining, 0)
        client.fail = true; await flow.loadQuota()
        let stale = UIHostingController(rootView: Form { PublishingAIQuotaSection(flow: flow) }.dynamicTypeSize(.accessibility5))
        stale.loadViewIfNeeded(); XCTAssertTrue(flow.quotaIsStale); XCTAssertFalse(flow.canGenerate)
        XCTAssertNil(flow.candidate); XCTAssertEqual(client.generations, 0)
    }
    func testViewConstructionDoesNotImplicitlyRefreshOrGenerate() {
        let client = Stub(); let flow = PublishingAIDraftFlow(client: client, product: .city)
        let host = UIHostingController(rootView: Form { PublishingAIQuotaSection(flow: flow) })
        host.loadViewIfNeeded()
        XCTAssertEqual(client.reads, 0); XCTAssertEqual(client.generations, 0); XCTAssertEqual(flow.quotaReadState, .idle)
    }
    @MainActor private final class Stub: PublishingAIDraftServing {
        var session: PublishingSession? = .init(namespace: "synthetic", accountID: 7, epoch: UUID(), role: "player", region: .china)
        var canGenerate = true; var fail = false; var reads = 0; var generations = 0
        func quota() async throws -> PublishingAIQuota {
            reads += 1; if fail { throw PublishModesError.unavailable }
            return try .init(.object(["limited": .bool(true), "limit": .number(4), "remaining": .number(0)]))
        }
        func generate(idea: String, product: ProjectEditProduct) async throws -> PublishingAIThemeDraft {
            generations += 1; throw PublishModesError.unavailable
        }
        func cancel() {}
    }
}
