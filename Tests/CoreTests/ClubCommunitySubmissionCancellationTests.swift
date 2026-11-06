import Foundation
import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class CancelClubSubmitTransport: ClubCommunityOfflineTransport {
    var requests: [URLRequest] = []
    var cancelAfterSend = false
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        if cancelAfterSend { withUnsafeCurrentTask { $0?.cancel() } }
        return (Data(#"{"code":200,"data":null}"#.utf8), 200)
    }
}
@MainActor final class ClubCommunitySubmissionCancellationTests: XCTestCase {
    private struct Harness {
        let transport: CancelClubSubmitTransport
        let service: ClubCommunityService
        let session: ClubCommunitySession
        let evidence: ClubCommunityEvidence
        let journal: ClubCommunityInMemoryPendingJournal
        let flow: ClubCommunityCoordinator
    }
    private func harness(refresh: @escaping (ClubCommunityEvidence) async throws -> ClubCommunityEvidence = { $0 }) throws -> Harness {
        let transport = CancelClubSubmitTransport()
        let service = ClubCommunityService(offlineBaseURL: URL(string: "https://club-cancellation.invalid")!, transport: transport)
        let session = try ClubCommunitySession(identity: .init(accountID: 5, epoch: 1), token: "synthetic-token")
        let evidence = ClubCommunityEvidence(identity: session.identity, clubID: 10, joined: true, owner: false, administrator: false)
        let journal = ClubCommunityInMemoryPendingJournal()
        let flow = ClubCommunityCoordinator(service: service, currentSession: { session }, refreshEvidence: refresh, journal: journal, namespace: { "cancel-tests" })
        return .init(transport: transport, service: service, session: session, evidence: evidence, journal: journal, flow: flow)
    }
    func testCancelledPrepareNeverRefreshesOrPublishesReview() async throws {
        var refreshes = 0
        let h = try harness { value in refreshes += 1; return value }
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            do { _ = try await h.flow.prepare(.create(content: "draft", images: []), evidence: h.evidence); return false }
            catch is CancellationError { return true } catch { return false }
        }
        let cancelled = await task.value
        XCTAssertTrue(cancelled); XCTAssertEqual(refreshes, 0); XCTAssertNil(h.flow.review)
        XCTAssertTrue(h.transport.requests.isEmpty)
    }
    func testCancelledPrepareResponseCannotInstallReview() async throws {
        let h = try harness { value in withUnsafeCurrentTask { $0?.cancel() }; return value }
        let task = Task { @MainActor in
            do { _ = try await h.flow.prepare(.create(content: "draft", images: []), evidence: h.evidence); return false }
            catch is CancellationError { return true } catch { return false }
        }
        let cancelled = await task.value
        XCTAssertTrue(cancelled); XCTAssertNil(h.flow.review); XCTAssertTrue(h.transport.requests.isEmpty)
    }
    func testCancelledConfirmPreflightDoesNotReserveOrSendAndExplicitRetryWorks() async throws {
        var cancel = false
        let h = try harness { value in if cancel { withUnsafeCurrentTask { $0?.cancel() } }; return value }
        let review = try await h.flow.prepare(.create(content: "draft", images: []), evidence: h.evidence)
        cancel = true
        let task = Task { @MainActor in
            do { try await h.flow.confirm(review); return false }
            catch is CancellationError { return true } catch { return false }
        }
        let cancelled = await task.value
        XCTAssertTrue(cancelled); XCTAssertTrue(h.transport.requests.isEmpty)
        XCTAssertNil(h.flow.pendingRecord(for: h.evidence))
        cancel = false
        try await h.flow.confirm(review)
        XCTAssertEqual(h.flow.outcome, .acknowledgedRefreshRequired)
        XCTAssertEqual(h.transport.requests.count, 1)
    }
    func testCancelledDispatchedWriteKeepsOriginalUnknownAcrossCoordinatorRestart() async throws {
        let h = try harness()
        let review = try await h.flow.prepare(.create(content: "draft", images: []), evidence: h.evidence)
        h.transport.cancelAfterSend = true
        let task = Task { @MainActor in
            do { try await h.flow.confirm(review); return false }
            catch { return error as? ClubCommunityFailure == .unknown }
        }
        let unknown = await task.value
        XCTAssertTrue(unknown); XCTAssertEqual(h.flow.outcome, .unknownLocked)
        let record = try XCTUnwrap(h.flow.pendingRecord(for: h.evidence))
        XCTAssertEqual(record.operationID, review.id); XCTAssertEqual(record.phase, .unknownLocked)
        let restarted = ClubCommunityCoordinator(service: h.service, currentSession: { h.session }, refreshEvidence: { $0 }, journal: h.journal, namespace: { "cancel-tests" })
        XCTAssertTrue(restarted.recoverPendingLock(for: h.evidence))
        do { _ = try await restarted.prepare(.create(content: "draft", images: []), evidence: h.evidence); XCTFail() }
        catch { XCTAssertEqual(error as? ClubCommunityFailure, .locked) }
        XCTAssertEqual(h.transport.requests.count, 1); XCTAssertFalse(Task.isCancelled)
    }
    func testDirectServiceCancelledBeforeDispatchSendsNothing() async throws {
        let h = try harness()
        let review = try await h.flow.prepare(.create(content: "draft", images: []), evidence: h.evidence)
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            do { try await h.service.submit(review, session: h.session, check: {}); return false }
            catch is CancellationError { return true } catch { return false }
        }
        let cancelled = await task.value
        XCTAssertTrue(cancelled); XCTAssertTrue(h.transport.requests.isEmpty)
    }
}
