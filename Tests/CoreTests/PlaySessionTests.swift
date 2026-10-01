import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@MainActor
final class PlaySessionTests: XCTestCase {
    private func service(_ operation: @escaping @MainActor (URLRequest) async throws -> (Data, Int)) throws -> PlayService {
        PlayService(configuration: try APIConfiguration(baseURL: URL(string: "https://example.com/fixture/")!), transport: PlayClosureTransport(operation))
    }
    private func credentials(_ id: Int = 1, _ epoch: UInt64 = 1, _ token: String = "synthetic-token") throws -> PlayReadSession {
        try PlayReadSession(accountID: id, epoch: epoch, token: token)
    }
    func testUnconfiguredGuestAndInvalidScopeDoNotDispatch() async throws {
        var reads = 0, requests = 0
        let unconfigured = PlaySessionReader(scope: .activity(41), service: nil, currentSession: { reads += 1; return nil })
        do { _ = try await unconfigured.playSession(); XCTFail() } catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        XCTAssertEqual(reads, 0)
        let api = try service { _ in requests += 1; return (Data(), 200) }
        let guest = PlaySessionReader(scope: .activity(41), service: api, currentSession: { nil })
        do { _ = try await guest.playSession(); XCTFail() } catch { XCTAssertEqual(error as? APIError, .unauthorized) }
        let bad = PlaySessionReader(scope: .topic(-1), service: api, currentSession: { reads += 1; return nil })
        do { _ = try await bad.playSession(); XCTFail() } catch { XCTAssertEqual(error as? APIError, .invalidRequest) }
        XCTAssertEqual(requests, 0); XCTAssertEqual(reads, 0)
    }
    func testChangedAccountEpochTokenAndLogoutDiscardOldResult() async throws {
        for replacement in [try credentials(2, 2), try credentials(1, 2), try credentials(1, 1, "new-synthetic-token"), nil] {
            var current: PlayReadSession? = try credentials()
            let api = try service { _ in current = replacement; return (Data(PlayTestData.envelope.utf8), 200) }
            let reader = PlaySessionReader(scope: .activity(41), service: api, currentSession: { current })
            do { _ = try await reader.playSession(); XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
            XCTAssertFalse(reader.canSubmitAnswer)
        }
    }
    func testStale401CannotExpireNewAccountButMatching401Does() async throws {
        for stale in [false, true] {
            var current: PlayReadSession? = try credentials()
            let next = try credentials(2, 2)
            var expirations = 0
            let api = try service { _ in
                if stale { current = next }
                return (Data(#"{"code":"401"}"#.utf8), 401)
            }
            let reader = PlaySessionReader(scope: .activity(41), service: api, currentSession: { current }, onUnauthorized: { captured in
                expirations += 1; if current == captured { current = nil }
            })
            do { _ = try await reader.playSession(); XCTFail() } catch {
                if stale { XCTAssertTrue(error is CancellationError) } else { XCTAssertEqual(error as? APIError, .unauthorized) }
            }
            XCTAssertEqual(expirations, stale ? 0 : 1)
            if stale { XCTAssertEqual(current, next) } else { XCTAssertNil(current) }
        }
    }
    func testRepeatedLoadRejectsOlderResponseAndImmutableScopeTravelsInIdentity() async throws {
        let current = try credentials()
        var calls = 0
        var reader: PlaySessionReader!
        let api = try service { _ in
            calls += 1
            if calls == 1 { _ = try await reader.playSession() }
            return (Data(PlayTestData.envelope.utf8), 200)
        }
        reader = PlaySessionReader(scope: .activity(41), service: api, answersEnabled: true, currentSession: { current })
        do { _ = try await reader.playSession(); XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(calls, 2); XCTAssertTrue(reader.canSubmitAnswer)
        XCTAssertEqual(reader.identity?.scope, .activity(41))
    }
    func testBranchReadUsesExactScopeAndRejectsDifferentRouteSession() async throws {
        let current = try credentials()
        for mismatched in [false, true] {
            var paths: [String] = []
            let route = #"{"routeMode":"BRANCH_GRAPH","sessionId":99,"version":1,"status":"ACTIVE","nodeStates":{"7":"PLAYABLE"}}"#
            let api = try service { request in
                paths.append(request.url!.lastPathComponent)
                XCTAssertEqual(request.url?.query, "activityId=41")
                let data = request.url?.lastPathComponent == "nodes"
                    ? "{\"nodes\":[{\"nodeId\":7}],\"routeState\":\(route)}"
                    : (mismatched ? route.replacingOccurrences(of: "99", with: "100") : route)
                return (Data("{\"code\":200,\"data\":\(data)}".utf8), 200)
            }
            let reader = PlaySessionReader(scope: .activity(41), service: api, currentSession: { current })
            do { _ = try await reader.playSession(); if mismatched { XCTFail() } }
            catch { XCTAssertTrue(mismatched); XCTAssertEqual(error as? APIError, .malformedResponse) }
            XCTAssertEqual(paths, ["nodes", "route-state"])
        }
    }
    func testAnswersAreOptInAndRequireSuccessfulRead() async throws {
        let current = try credentials()
        var calls = 0
        let api = try service { _ in calls += 1; return (Data(PlayTestData.envelope.utf8), 200) }
        let reader = PlaySessionReader(scope: .activity(41), service: api, currentSession: { current })
        _ = try await reader.playSession()
        XCTAssertFalse(reader.supportsAnswerSubmission); XCTAssertFalse(reader.canSubmitAnswer)
        do { _ = try await reader.submitAnswer(nodeID: 7, answer: "answer"); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .invalidRequest) }
        XCTAssertEqual(calls, 1)
    }
    func testSuccessfulAnswerRequiresReadbackAndCannotDoubleSubmit() async throws {
        let current = try credentials()
        var calls: [String] = [], submitted = false
        let api = try service { request in
            calls.append(request.url!.lastPathComponent)
            if request.httpMethod == "POST" { submitted = true; return (Data(PlayTestData.receipt.utf8), 200) }
            let body = submitted ? PlayTestData.envelope.replacingOccurrences(of: "\"nodeId\":7,\"done\":false", with: "\"nodeId\":7,\"done\":true") : PlayTestData.envelope
            return (Data(body.utf8), 200)
        }
        let reader = PlaySessionReader(scope: .activity(41), service: api, answersEnabled: true, currentSession: { current })
        _ = try await reader.playSession(); XCTAssertTrue(reader.canSubmitAnswer)
        let receipt = try await reader.submitAnswer(nodeID: 7, answer: "answer")
        XCTAssertEqual(receipt.nodeID, 7); XCTAssertFalse(reader.canSubmitAnswer)
        do { _ = try await reader.submitAnswer(nodeID: 7, answer: "answer"); XCTFail() } catch { XCTAssertEqual(error as? APIError, .invalidRequest) }
        XCTAssertEqual(calls, ["nodes", "answer"])
        let refreshed = try await reader.playSession()
        XCTAssertTrue(refreshed.isDone(refreshed.visibleNodes[0]))
        XCTAssertEqual(calls, ["nodes", "answer", "nodes"])
        do { _ = try await reader.submitAnswer(nodeID: 7, answer: "answer"); XCTFail() } catch { XCTAssertEqual(error as? APIError, .invalidRequest) }
    }
    func testUncertainAnswerAndStaleReadbackNeverPermitDuplicateWrite() async throws {
        let current = try credentials()
        var posts = 0
        let api = try service { request in
            if request.httpMethod == "POST" { posts += 1; throw URLError(.timedOut) }
            return (Data(PlayTestData.envelope.utf8), 200)
        }
        let reader = PlaySessionReader(scope: .activity(41), service: api, answersEnabled: true, currentSession: { current })
        _ = try await reader.playSession()
        do { _ = try await reader.submitAnswer(nodeID: 7, answer: "answer"); XCTFail() } catch { XCTAssertTrue(error is URLError) }
        _ = try await reader.playSession()
        XCTAssertFalse(reader.canSubmitAnswer)
        do { _ = try await reader.submitAnswer(nodeID: 7, answer: "answer"); XCTFail() } catch { XCTAssertEqual(error as? APIError, .invalidRequest) }
        XCTAssertEqual(posts, 1)
    }
    func testDefiniteBusinessRejectionPermitsNewExplicitAttemptOnlyAfterReadback() async throws {
        let current = try credentials()
        let api = try service { request in
            (Data((request.httpMethod == "POST" ? #"{"code":400,"msg":"Synthetic wrong answer"}"# : PlayTestData.envelope).utf8), 200)
        }
        let reader = PlaySessionReader(scope: .activity(41), service: api, answersEnabled: true, currentSession: { current })
        _ = try await reader.playSession()
        do { _ = try await reader.submitAnswer(nodeID: 7, answer: "answer"); XCTFail() } catch let failure as PlayFailure { XCTAssertEqual(failure.code, 400) }
        XCTAssertFalse(reader.canSubmitAnswer)
        _ = try await reader.playSession(); XCTAssertTrue(reader.canSubmitAnswer)
    }
    func testOldAnswerReceiptCannotUpdateNewAccountOrEnableActions() async throws {
        var current: PlayReadSession? = try credentials()
        let next = try credentials(2, 2)
        var posts = 0
        let api = try service { request in
            if request.httpMethod == "POST" {
                posts += 1; current = next
                return (Data(PlayTestData.receipt.utf8), 200)
            }
            return (Data(PlayTestData.envelope.utf8), 200)
        }
        let reader = PlaySessionReader(scope: .activity(41), service: api, answersEnabled: true, currentSession: { current })
        _ = try await reader.playSession()
        do { _ = try await reader.submitAnswer(nodeID: 7, answer: "answer"); XCTFail() }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(reader.identity?.accountID, 2); XCTAssertFalse(reader.canSubmitAnswer)
        _ = try await reader.playSession(); XCTAssertTrue(reader.canSubmitAnswer)
        XCTAssertEqual(posts, 1)
    }
    func testConcurrentSubmitAndReadAreRejectedDuringWriteWithoutDispatch() async throws {
        let current = try credentials()
        var posts = 0
        var reader: PlaySessionReader!
        let api = try service { request in
            if request.httpMethod == "POST" {
                posts += 1
                do { _ = try await reader.submitAnswer(nodeID: 7, answer: "again"); XCTFail() }
                catch { XCTAssertEqual(error as? APIError, .invalidRequest) }
                do { _ = try await reader.playSession(); XCTFail() }
                catch { XCTAssertEqual(error as? APIError, .invalidRequest) }
                return (Data(PlayTestData.receipt.utf8), 200)
            }
            return (Data(PlayTestData.envelope.utf8), 200)
        }
        reader = PlaySessionReader(scope: .activity(41), service: api, answersEnabled: true, currentSession: { current })
        _ = try await reader.playSession(); _ = try await reader.submitAnswer(nodeID: 7, answer: "answer")
        XCTAssertEqual(posts, 1)
    }
    func testCancellationIgnoringTransportCannotDeliverData() async throws {
        let current = try credentials()
        let api = try service { _ in
            withUnsafeCurrentTask { $0?.cancel() }
            return (Data(PlayTestData.envelope.utf8), 200)
        }
        let reader = PlaySessionReader(scope: .activity(41), service: api, currentSession: { current })
        let task = Task { @MainActor in try await reader.playSession() }
        do { _ = try await task.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
    }
}

private final class PlayClosureTransport: HTTPTransport {
    private let operation: @MainActor (URLRequest) async throws -> (Data, Int)
    init(_ operation: @escaping @MainActor (URLRequest) async throws -> (Data, Int)) { self.operation = operation }
    func send(_ request: URLRequest) async throws -> (Data, Int) { try await operation(request) }
}
