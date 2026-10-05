import XCTest
import Observation
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor final class SocialPresentationRevisionTests: XCTestCase {
    private func service(_ wire: Wire) throws -> SocialAccountService {
        try .init(configuration: APIConfiguration(baseURL: URL(string: "https://example.com/native")!), transport: wire)
    }
    func testProtocolIdentityReadsObserveExplicitPresentationInvalidation() async throws {
        let reader = SocialAccountSessionReader(service: nil, currentSession: { .init(guestEpoch: 1) })
        let erased: any SocialAccountReading = reader
        let changed = expectation(description: "Observable protocol identity")
        withObservationTracking { _ = erased.identity; _ = erased.presentationRevision } onChange: { changed.fulfill() }
        reader.invalidatePresentation()
        await fulfillment(of: [changed], timeout: 2)
        XCTAssertEqual(reader.presentationRevision, 1)
        XCTAssertNil(reader.identity.accountID)
    }
    func testAccountRoleTokenLogoutAndRevisionABARejectLateSuccessAndBoth401Forms() async throws {
        for transition in ["account", "role", "token", "logout", "aba"] {
            for result in 0...2 {
                let wire = Wire(); wire.suspend = true
                let original = try SocialAccountSession(accountID: 7, epoch: 1, role: "player", token: "synthetic-7")
                var current = original, expirations = 0
                let reader = SocialAccountSessionReader(service: try service(wire), currentSession: { current }, onUnauthorized: { _ in expirations += 1 })
                let started = expectation(description: "Suspended social read \(transition) \(result)"); wire.onPaused = { started.fulfill() }
                let task = Task { try await reader.information(id: 91) }
                await fulfillment(of: [started], timeout: 2)
                guard wire.hasPending else { task.cancel(); return XCTFail("No suspended request") }
                switch transition {
                case "account": current = try .init(accountID: 8, epoch: 1, role: "player", token: "synthetic-8")
                case "role": current = try .init(accountID: 7, epoch: 1, role: "merchant", token: "synthetic-7")
                case "token": current = try .init(accountID: 7, epoch: 1, role: "player", token: "replacement-7")
                case "logout": current = .init(guestEpoch: 2)
                default:
                    current = try .init(accountID: 7, epoch: 1, role: "merchant", token: "synthetic-7")
                    reader.invalidatePresentation(); current = original
                }
                reader.invalidatePresentation(); wire.finish(result)
                do { _ = try await task.value; XCTFail("Retired social response escaped") }
                catch { XCTAssertTrue(error is CancellationError) }
                XCTAssertEqual(expirations, 0)
            }
        }
    }
    func testCancelledReadCannotExpireCurrentViewerWhenTransportIgnoresCancellation() async throws {
        let wire = Wire(); wire.suspend = true
        let current = try SocialAccountSession(accountID: 7, epoch: 1, role: "player", token: "synthetic-7")
        var expirations = 0
        let reader = SocialAccountSessionReader(service: try service(wire), currentSession: { current }, onUnauthorized: { _ in expirations += 1 })
        let started = expectation(description: "Cancelable read"); wire.onPaused = { started.fulfill() }
        let task = Task { try await reader.information(id: 91) }
        await fulfillment(of: [started], timeout: 2)
        guard wire.hasPending else { task.cancel(); return XCTFail("No suspended request") }
        task.cancel(); wire.finish(1)
        do { _ = try await task.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(expirations, 0)
    }
    func testCurrent401StillExpiresSignedInViewerButPublicGuestReadHasNoCredential() async throws {
        for result in 1...2 {
            let wire = Wire(); wire.result = result
            let current = try SocialAccountSession(accountID: 7, epoch: 1, role: "player", token: "synthetic-7")
            var expirations = 0
            let reader = SocialAccountSessionReader(service: try service(wire), currentSession: { current }, onUnauthorized: { _ in expirations += 1 })
            do { _ = try await reader.information(id: 91); XCTFail() } catch { XCTAssertEqual(error as? APIError, .unauthorized) }
            XCTAssertEqual(expirations, 1)
        }
        let wire = Wire(), guest = SocialAccountSessionReader(service: try service(wire), currentSession: { .init(guestEpoch: 1) })
        let information = try await guest.information(id: 91)
        XCTAssertEqual(information.id, 91)
        XCTAssertNil(wire.requests.first?.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(wire.requests.first?.url?.path, "/native/api/common/infomation_detail")
    }
    @MainActor private final class Wire: HTTPTransport {
        var requests: [URLRequest] = []
        var suspend = false, result = 0
        var onPaused: (() -> Void)?
        private var pending: CheckedContinuation<(Data, Int), Error>?
        var hasPending: Bool { pending != nil }
        func reply(_ result: Int) -> (Data, Int) {
            (Data((result == 2 ? #"{"code":401}"# : #"{"code":200,"data":{"id":91,"title":"Guide","contents":"Synthetic article"}}"#).utf8), result == 1 ? 401 : 200)
        }
        func finish(_ result: Int) { let completion = pending; pending = nil; completion?.resume(returning: reply(result)) }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            if suspend { return try await withCheckedThrowingContinuation { pending = $0; onPaused?() } }
            return reply(result)
        }
    }
}
