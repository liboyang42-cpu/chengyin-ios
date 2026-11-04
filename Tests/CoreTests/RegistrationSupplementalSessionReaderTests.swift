import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private actor SupplementalSuspendedTransport: HTTPTransport {
    var pending: CheckedContinuation<(Data, Int), Error>?
    private(set) var count = 0
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        count += 1
        return try await withCheckedThrowingContinuation { pending = $0 }
    }
    func isReady() -> Bool { pending != nil }
    func finish(_ body: String) { pending?.resume(returning: (Data(body.utf8), 200)); pending = nil }
}

@MainActor final class RegistrationSupplementalSessionReaderTests: XCTestCase {
    private func context(accountID: Int = 7, epoch: UInt64 = 1, token: String = "synthetic-session", host: String = "example.com") throws -> RuntimeDependencyContext {
        try .init(market: .china, baseURL: URL(string: "https://\(host)/test/")!, role: "player",
                  session: .init(accountID: accountID, epoch: epoch, namespace: "synthetic-tests", token: token))
    }
    private func service(_ transport: any HTTPTransport) throws -> RegistrationSupplementalReadService {
        try .init(configuration: APIConfiguration(baseURL: URL(string: "https://example.com/test/")!), transport: transport)
    }

    func testNilServiceAndDifferentBaseURLStayClosedWithoutRequests() async throws {
        let transport = SupplementalSuspendedTransport()
        let original = try context()
        let disabled = RegistrationSupplementalSessionReader(service: nil, captured: original, current: { original })
        do { _ = try await disabled.paymentReadiness(); XCTFail("No injected service") }
        catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        let other = try context(host: "example.org")
        let mismatch = RegistrationSupplementalSessionReader(service: try service(transport), captured: other, current: { other })
        do { _ = try await mismatch.paymentReadiness(); XCTFail("Wrong endpoint") }
        catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        let count = await transport.count
        XCTAssertEqual(count, 0)
    }

    func testRetainedReaderDoesNotAdoptAnotherAccountBeforeDispatch() async throws {
        let transport = SupplementalSuspendedTransport()
        let original = try context()
        let replacement = try context(accountID: 8, epoch: 2)
        let reader = RegistrationSupplementalSessionReader(service: try service(transport), captured: original, current: { replacement })
        do { _ = try await reader.joinedRegistration(); XCTFail("Old reader cannot query replacement account") }
        catch { XCTAssertTrue(error is CancellationError) }
        let count = await transport.count
        XCTAssertEqual(count, 0)
    }

    func testLateSuccessIsDiscardedAfterAccountChange() async throws {
        let transport = SupplementalSuspendedTransport()
        var current: RuntimeDependencyContext? = try context()
        let reader = RegistrationSupplementalSessionReader(service: try service(transport), captured: current, current: { current })
        let task = Task { try await reader.joinedRegistration() }
        while !(await transport.isReady()) { await Task.yield() }
        current = try context(accountID: 8, epoch: 2)
        await transport.finish(#"{"code":200,"data":{"id":41,"memberId":7}}"#)
        do { _ = try await task.value; XCTFail("Old data cannot cross accounts") }
        catch { XCTAssertTrue(error is CancellationError) }
    }

    func testStale401DoesNotExpireReplacementToken() async throws {
        let transport = SupplementalSuspendedTransport()
        var current: RuntimeDependencyContext? = try context()
        var expired = 0
        let reader = RegistrationSupplementalSessionReader(service: try service(transport), captured: current, current: { current }, onUnauthorized: { _ in expired += 1 })
        let task = Task { try await reader.paymentReadiness() }
        while !(await transport.isReady()) { await Task.yield() }
        current = try context(epoch: 2, token: "synthetic-replacement")
        await transport.finish(#"{"code":401,"data":"bad"}"#)
        do { _ = try await task.value; XCTFail("Old response") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(expired, 0)
    }

    func testCurrent401ExpiresOnlyCapturedSessionWithoutRetry() async throws {
        let transport = SupplementalSuspendedTransport()
        let current = try context()
        var expired: [RuntimeDependencyContext] = []
        let reader = RegistrationSupplementalSessionReader(service: try service(transport), captured: current, current: { current }, onUnauthorized: { expired.append($0) })
        let task = Task { try await reader.paymentReadiness() }
        while !(await transport.isReady()) { await Task.yield() }
        await transport.finish(#"{"code":401}"#)
        do { _ = try await task.value; XCTFail("Unauthorized") }
        catch { XCTAssertEqual(error as? APIError, .unauthorized) }
        XCTAssertEqual(expired, [current])
        let count = await transport.count
        XCTAssertEqual(count, 1)
    }

    func testCancellationAndSignOutDiscardLateReadiness() async throws {
        for signOut in [false, true] {
            let transport = SupplementalSuspendedTransport()
            var current: RuntimeDependencyContext? = try context()
            let reader = RegistrationSupplementalSessionReader(service: try service(transport), captured: current, current: { current })
            let task = Task { try await reader.paymentReadiness() }
            while !(await transport.isReady()) { await Task.yield() }
            if signOut { current = nil } else { task.cancel() }
            await transport.finish(#"{"code":200,"data":{"ready":true}}"#)
            do { _ = try await task.value; XCTFail("Retired read") }
            catch { XCTAssertTrue(error is CancellationError) }
        }
    }
}
