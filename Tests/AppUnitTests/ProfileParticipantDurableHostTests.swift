import Foundation
import XCTest
@testable import Questify

@MainActor final class ProfileParticipantDurableHostTests: XCTestCase {
    private func host(_ h: ParticipantHostSpecimen, epoch: UInt64, namespace: String? = nil,
                      account: Int = 7, baseURL: URL? = nil) throws -> ProfileParticipantHost {
        let context = RuntimeDependencyContext(market: .china, baseURL: baseURL ?? ParticipantHostSpecimen.base,
            role: "player", session: try .init(accountID: account, epoch: epoch,
                namespace: namespace ?? h.namespace, token: "synthetic-participant-7"))
        let access = try ProfileParticipantAccess(context: context, permitsWrites: true,
            expiresAt: Date().addingTimeInterval(60))
        return ProfileParticipantHost(current: { context }, viewer: { epoch }, access: { _ in access },
            makeTransport: { captured, issued, valid in
                ProfileParticipantTransport(context: captured, access: issued, underlying: h.wire,
                    current: { context }, stillCurrent: valid)
            }, pendingJournal: OperationDefaultsJournal(defaults: h.defaults))
    }
    func testNewHostNewEpochRestoresUnknownThroughNormalOwnedHost() async throws {
        let h = try ParticipantHostSpecimen(); defer { h.cleanup() }
        let first = try host(h, epoch: 1)
        h.wire.failAddress = true
        let review = try first.coordinator.prepare(.save(ParticipantHostSpecimen.draft()),
            expectedIdentity: try XCTUnwrap(first.reader.identity))
        _ = await first.coordinator.confirm(review)
        XCTAssertEqual(h.wire.addressRequests.count, 1)
        let restarted = try host(h, epoch: 100)
        XCTAssertEqual(restarted.coordinator.state, .outcomeUnknown(.transport))
        XCTAssertFalse(restarted.coordinator.canPrepare)
        XCTAssertNil(restarted.coordinator.savedParticipant)
        XCTAssertEqual(h.wire.addressRequests.count, 1)
        h.wire.failAddress = false
        _ = await restarted.coordinator.readBackUncertainOutcome()
        XCTAssertFalse(restarted.coordinator.canPrepare)
        XCTAssertEqual(h.wire.addressRequests.count, 2)
        XCTAssertTrue(h.wire.addressRequests.last?.url?.path.hasSuffix("/list") == true)
    }
    func testSameNumericAccountInAnotherNamespaceOrOriginIsIsolated() async throws {
        let h = try ParticipantHostSpecimen(); defer { h.cleanup() }
        let first = try host(h, epoch: 1)
        h.wire.failAddress = true
        let review = try first.coordinator.prepare(.delete(id: 9), expectedIdentity: try XCTUnwrap(first.reader.identity))
        _ = await first.coordinator.confirm(review)
        XCTAssertFalse(first.coordinator.canPrepare)
        for other in [try host(h, epoch: 2, namespace: h.namespace + ".other"),
                      try host(h, epoch: 2, account: 8),
                      try host(h, epoch: 2, baseURL: URL(string: "https://other.example.com/native/")!)] {
            XCTAssertEqual(other.coordinator.state, .idle); XCTAssertTrue(other.coordinator.canPrepare)
            XCTAssertEqual(other.coordinator.readbackState, .idle)
        }
        XCTAssertFalse(try host(h, epoch: 3).coordinator.canPrepare)
        XCTAssertEqual(h.wire.addressRequests.count, 1)
    }
}
