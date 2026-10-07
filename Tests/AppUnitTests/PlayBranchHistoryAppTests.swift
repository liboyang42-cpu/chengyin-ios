import XCTest
import SwiftUI
@testable import Questify

@MainActor final class PlayBranchHistoryAppTests: XCTestCase {
    private final class Owner { var session: PlayExperienceSession? }
    private func make(_ owner: Owner, wire: PlayRecoveryRecordingTransport) throws -> PlayExperienceCoordinator {
        .init(scope: .activity(41), service: .init(configuration: try APIConfiguration(baseURL: URL(string: "https://example.com/fixture/")!), transport: wire, enabled: [.reads]), recovery: PlayMemoryCompletionRecovery(), pausedStorage: PlayMemoryPausedStorage(), currentSession: { owner.session })
    }
    private func configure(_ wire: PlayRecoveryRecordingTransport, log: String? = PlayBranchHistorySyntheticFixtures.recorded, sessionID: Int = 501, version: Int = 2) {
        let route = PlayBranchHistorySyntheticFixtures.route(log: log, sessionID: sessionID, version: version)
        wire.responses["/fixture/api/play/nodes"] = .reply(PlayExperienceSyntheticFixtures.envelope(PlayBranchHistorySyntheticFixtures.nodes(route: route)), 200)
        wire.responses["/fixture/api/play/route-state"] = .reply(PlayExperienceSyntheticFixtures.envelope(route), 200)
    }
    private func owner() throws -> Owner {
        let owner = Owner(); owner.session = try .init(accountID: 1, epoch: 1, namespace: "synthetic", token: "synthetic"); return owner
    }
    func testNormalSummaryHistoryBackReopenUsesOnlyAlreadyLoadedReads() async throws {
        let owner = try owner(), wire = PlayRecoveryRecordingTransport(); configure(wire)
        let model = try make(owner, wire: wire); await model.load()
        let snapshot = try XCTUnwrap(model.snapshot)
        let selection = try XCTUnwrap(PlayBranchHistorySelection(snapshot: snapshot))
        let original = wire.requests.count, done = snapshot.displayedDoneCount
        for _ in 0..<3 {
            let history = try XCTUnwrap(selection.presentation(snapshot: model.snapshot))
            _ = UIHostingController(rootView: PlayBranchHistoryView(history: history))
            _ = UIHostingController(rootView: PlayTaskSummaryView(snapshot: snapshot, phase: model.phase.rawValue))
            XCTAssertEqual(history.rows.count, 3)
        }
        XCTAssertEqual(wire.requests.count, original)
        XCTAssertEqual(wire.requests.map { $0.url!.path }, ["/fixture/api/play/nodes", "/fixture/api/play/route-state"])
        XCTAssertTrue(wire.requests.allSatisfy { $0.httpMethod == "GET" })
        XCTAssertEqual(model.snapshot?.displayedDoneCount, done); XCTAssertFalse(model.canWrite)
        XCTAssertNil(model.reward); XCTAssertNil(model.ending)
    }
    func testRefreshDropsOldRowsBeforeAwaitAndNewRunNeverReusesSelection() async throws {
        let owner = try owner(), wire = PlayRecoveryRecordingTransport(); configure(wire)
        let model = try make(owner, wire: wire); await model.load()
        let selection = try XCTUnwrap(PlayBranchHistorySelection(snapshot: XCTUnwrap(model.snapshot)))
        configure(wire, log: "[]", sessionID: 502, version: 0); wire.pauseResponse = true
        let task = Task { await model.load() }
        for _ in 0..<1_000 where !wire.isAwaitingResponse { await Task.yield() }
        XCTAssertTrue(wire.isAwaitingResponse); XCTAssertNil(model.snapshot)
        XCTAssertNil(selection.presentation(snapshot: model.snapshot))
        wire.resumeResponse(); await task.value
        XCTAssertNil(selection.presentation(snapshot: model.snapshot))
        XCTAssertEqual(PlayBranchHistoryPresentation(snapshot: try XCTUnwrap(model.snapshot)).state, .empty)
    }
    func testAccountEpochInvalidationAndFailedRefreshCannotKeepHistory() async throws {
        let owner = try owner(), wire = PlayRecoveryRecordingTransport(); configure(wire)
        let model = try make(owner, wire: wire); await model.load()
        let selection = try XCTUnwrap(PlayBranchHistorySelection(snapshot: XCTUnwrap(model.snapshot)))
        owner.session = try .init(accountID: 2, epoch: 2, namespace: "synthetic", token: "synthetic-other")
        XCTAssertNil(model.snapshot); XCTAssertNil(selection.presentation(snapshot: model.snapshot))
        model.invalidate()
        wire.responses["/fixture/api/play/nodes"] = .failure(.malformed)
        await model.load()
        XCTAssertNil(model.snapshot); XCTAssertNil(selection.presentation(snapshot: model.snapshot))
        XCTAssertTrue(wire.requests.allSatisfy { $0.httpMethod == "GET" })
    }
    func testOldAuthorityVersionAndSessionMismatchRemainRejected() async throws {
        for route in [PlayBranchHistorySyntheticFixtures.route(version: 1), PlayBranchHistorySyntheticFixtures.route(sessionID: 777)] {
            let owner = try owner(), wire = PlayRecoveryRecordingTransport(); configure(wire)
            wire.responses["/fixture/api/play/route-state"] = .reply(PlayExperienceSyntheticFixtures.envelope(route), 200)
            let model = try make(owner, wire: wire); await model.load()
            XCTAssertNil(model.snapshot); XCTAssertEqual(model.phase, .failed)
        }
    }
    func testBilingualMaximumTypeRowsGrowWithinNarrowWidthAndKeepNeutralNames() throws {
        let history = PlayBranchHistoryPresentation(snapshot: try PlayBranchHistorySyntheticFixtures.snapshot())
        for locale in ["en", "zh-Hans"] {
            XCTAssertFalse(branchHistoryLocalized("branchHistory.title", locale: Locale(identifier: locale)).hasPrefix("branchHistory."))
            let row = try XCTUnwrap(history.rows.first)
            func size(_ type: DynamicTypeSize) -> CGSize {
                UIHostingController(rootView: PlayBranchHistoryRowView(row: row)
                    .environment(\.locale, Locale(identifier: locale)).dynamicTypeSize(type)
                    .transaction { $0.animation = nil; $0.disablesAnimations = true })
                    .sizeThatFits(in: CGSize(width: 280, height: 20_000))
            }
            let normal = size(.large), maximum = size(.accessibility5)
            XCTAssertGreaterThan(maximum.height, normal.height)
            XCTAssertLessThanOrEqual(maximum.width, 281); XCTAssertTrue(maximum.height.isFinite)
        }
        XCTAssertEqual(branchHistoryLocalized("branchHistory.nodeUnknown", locale: Locale(identifier: "zh-Hans")), "节点名称暂不可用")
        XCTAssertNil(history.rows.last?.toName)
    }
}
