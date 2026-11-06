import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class CancellationGovernanceTransport: SquareGovernanceOfflineTransport {
    let source = SquareGovernanceSyntheticTransport()
    var cancelRead = false
    var cancelWrite = false
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        let result = try await source.send(request)
        if request.httpMethod == "GET" ? cancelRead : cancelWrite {
            withUnsafeCurrentTask { $0?.cancel() }
        }
        return result
    }
}
@MainActor private final class CancellationGovernanceAccess: SquareGovernanceAccess {
    var identity: SquareGovernanceIdentity? = .init(accountID: 11, epoch: 1, namespace: "cancellation-test")
    var token: String? = "synthetic-token"
    var cancelComments = false
    func freshComments() async throws -> [SquareGovernanceComment] {
        if cancelComments { withUnsafeCurrentTask { $0?.cancel() } }
        return []
    }
}
@MainActor final class SquareGovernanceCancellationTests: XCTestCase {
    private func service(_ transport: CancellationGovernanceTransport) -> SquareGovernanceService {
        .init(offlineBaseURL: URL(string: "https://governance-cancellation.invalid")!, transport: transport)
    }
    func testCancelledReadNeverDispatchesEvenWithEmptyCallerCheck() async {
        let transport = CancellationGovernanceTransport(), service = service(transport)
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            do { _ = try await service.enforcements(token: "synthetic-token", check: {}); return false }
            catch is CancellationError { return true }
            catch { return false }
        }
        let cancelled = await task.value
        XCTAssertTrue(cancelled); XCTAssertTrue(transport.source.requests.isEmpty)
        XCTAssertFalse(Task.isCancelled)
    }
    func testReadCancelledAfterResponseDoesNotReturnPrivateProjection() async {
        let transport = CancellationGovernanceTransport(), service = service(transport)
        transport.cancelRead = true
        let task = Task { @MainActor in
            do { _ = try await service.enforcements(token: "synthetic-token", check: {}); return false }
            catch is CancellationError { return true }
            catch { return false }
        }
        let cancelled = await task.value
        XCTAssertTrue(cancelled); XCTAssertEqual(transport.source.requests.count, 1)
    }
    func testCancelledPreflightDoesNotConsumeReviewOrClaimJournal() async throws {
        let transport = CancellationGovernanceTransport(), access = CancellationGovernanceAccess()
        let flow = SquareGovernanceCoordinator(service: service(transport), journal: .ephemeral())
        let snapshot = try await flow.load(access: access)
        let review = try flow.prepare(.markRead(notificationID: 81), snapshot: snapshot, access: access)
        access.cancelComments = true
        let task = Task { @MainActor in
            do { _ = try await flow.confirm(review, access: access); return false }
            catch is CancellationError { return true }
            catch { return false }
        }
        let cancelled = await task.value
        XCTAssertTrue(cancelled)
        XCTAssertTrue(transport.source.requests.allSatisfy { $0.httpMethod == "GET" })
        // A fresh explicit confirmation of the same review is safe: no write was dispatched.
        access.cancelComments = false
        let receipt = try await flow.confirm(review, access: access)
        XCTAssertEqual(receipt, .acknowledgedNeedsRefresh)
        XCTAssertEqual(transport.source.requests.filter { $0.httpMethod != "GET" }.count, 1)
    }
    func testCancellationAfterDispatchKeepsUnknownAndOriginalLock() async throws {
        let transport = CancellationGovernanceTransport(), access = CancellationGovernanceAccess()
        let journal = SquareGovernanceJournal.ephemeral(), service = service(transport)
        let flow = SquareGovernanceCoordinator(service: service, journal: journal)
        let snapshot = try await flow.load(access: access)
        let action = SquareGovernanceAction.markRead(notificationID: 81)
        let review = try flow.prepare(action, snapshot: snapshot, access: access)
        transport.cancelWrite = true
        let task = Task { @MainActor in
            do { _ = try await flow.confirm(review, access: access); return false }
            catch { return error as? SquareGovernanceFailure == .unknown }
        }
        let unknown = await task.value
        XCTAssertTrue(unknown)
        transport.cancelWrite = false
        do { _ = try await flow.confirm(review, access: access); XCTFail("Original must remain locked") }
        catch { XCTAssertEqual(error as? SquareGovernanceFailure, .outcomeLocked) }
        let restarted = SquareGovernanceCoordinator(service: service, journal: journal)
        XCTAssertThrowsError(try restarted.prepare(action, snapshot: snapshot, access: access)) {
            XCTAssertEqual($0 as? SquareGovernanceFailure, .outcomeLocked)
        }
        XCTAssertEqual(transport.source.requests.filter { $0.httpMethod != "GET" }.count, 1)
        XCTAssertFalse(Task.isCancelled)
    }
    func testDirectDispatchCancelledBeforeSendMakesNoMutation() async throws {
        let transport = CancellationGovernanceTransport(), access = CancellationGovernanceAccess()
        let service = service(transport), flow = SquareGovernanceCoordinator(service: service, journal: .ephemeral())
        let snapshot = try await flow.load(access: access)
        let review = try flow.prepare(.markRead(notificationID: 81), snapshot: snapshot, access: access)
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            do { _ = try await service.dispatch(review, token: "synthetic-token", check: {}); return false }
            catch is CancellationError { return true }
            catch { return false }
        }
        let cancelled = await task.value
        XCTAssertTrue(cancelled)
        XCTAssertTrue(transport.source.requests.allSatisfy { $0.httpMethod == "GET" })
    }
}
