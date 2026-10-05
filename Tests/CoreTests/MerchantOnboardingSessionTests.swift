import XCTest
@testable import QuestifyCore

@MainActor
final class MerchantOnboardingSessionTests: XCTestCase {
    private func service(_ transport: MerchantOnboardingTransport) throws -> MerchantOnboardingService {
        .init(configuration: try APIConfiguration(baseURL: URL(string: "https://api.example.test")!), transport: transport)
    }
    func testUnconfiguredOrMismatchedSessionSendsNothing() async throws {
        let transport = MerchantOnboardingTransport(body: #"{"code":200}"#)
        let snapshot = try MerchantOnboardingSession(accountID: 1, epoch: 1, token: "token")
        let adapter = MerchantOnboardingSessionAdapter(service: try service(transport), currentSession: { snapshot })
        do { try await adapter.submit(makeMerchantOnboardingDraft(), expectedIdentity: .init(accountID: 2, epoch: 1)); XCTFail() }
        catch { XCTAssertEqual(error as? MerchantOnboardingWriteError, .notSent) }
        let unavailable = MerchantOnboardingSessionAdapter(service: nil, currentSession: { snapshot })
        do { _ = try await unavailable.application(expectedIdentity: snapshot.identity); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        XCTAssertTrue(transport.requests.isEmpty)
    }
    func testReadResponseFromReplacedSessionIsDiscarded() async throws {
        let transport = MerchantOnboardingTransport(body: #"{"code":200,"data":null,"applicationState":"NONE"}"#)
        var session = try MerchantOnboardingSession(accountID: 1, epoch: 1, token: "first-token")
        let original = session.identity
        let adapter = MerchantOnboardingSessionAdapter(service: try service(transport), currentSession: { session })
        transport.onSend = { session = try! .init(accountID: 2, epoch: 2, token: "second-token") }
        do { _ = try await adapter.application(expectedIdentity: original); XCTFail("Leaked a previous account response") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(transport.requests.first?.value(forHTTPHeaderField: "Authorization"), "first-token")
    }
    func testSameAccountTokenAndEpochReplacementAlsoDiscardsRead() async throws {
        let transport = MerchantOnboardingTransport(body: #"{"code":200,"data":{"registered":true}}"#)
        var session = try MerchantOnboardingSession(accountID: 1, epoch: 1, token: "first-token")
        let original = session.identity
        let adapter = MerchantOnboardingSessionAdapter(service: try service(transport), currentSession: { session })
        transport.onSend = { session = try! .init(accountID: 1, epoch: 2, token: "second-token") }
        do { _ = try await adapter.identityRegistered(expectedIdentity: original); XCTFail() }
        catch { XCTAssertTrue(error is CancellationError) }
    }
    func testStaleUnauthorizedCannotSignOutReplacementAccount() async throws {
        let transport = MerchantOnboardingTransport(body: #"{"code":401}"#)
        var session = try MerchantOnboardingSession(accountID: 1, epoch: 1, token: "first-token")
        let original = session.identity
        var expired = 0
        let adapter = MerchantOnboardingSessionAdapter(service: try service(transport), currentSession: { session }, onUnauthorized: { _ in expired += 1 })
        transport.onSend = { session = try! .init(accountID: 2, epoch: 2, token: "second-token") }
        do { _ = try await adapter.application(expectedIdentity: original); XCTFail() }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(expired, 0)
    }
    func testMatchingUnauthorizedUsesExpiryCallbackOnce() async throws {
        let transport = MerchantOnboardingTransport(body: #"{"code":401}"#)
        let session = try MerchantOnboardingSession(accountID: 1, epoch: 1, token: "token")
        var expired: [MerchantOnboardingSession] = []
        let adapter = MerchantOnboardingSessionAdapter(service: try service(transport), currentSession: { session }, onUnauthorized: { expired.append($0) })
        do { try await adapter.submit(makeMerchantOnboardingDraft(), expectedIdentity: session.identity); XCTFail() }
        catch { XCTAssertEqual(error as? MerchantOnboardingWriteError, .rejected(.init(code: 401))) }
        XCTAssertEqual(expired, [session]); XCTAssertEqual(transport.requests.count, 1)
    }
    func testSessionReplacementAfterDispatchLeavesUnknownOutcomeAndNoRetry() async throws {
        let transport = MerchantOnboardingTransport(body: #"{"code":200}"#)
        var session = try MerchantOnboardingSession(accountID: 1, epoch: 1, token: "first-token")
        let original = session.identity
        let adapter = MerchantOnboardingSessionAdapter(service: try service(transport), currentSession: { session })
        transport.onSend = { session = try! .init(accountID: 2, epoch: 2, token: "second-token") }
        do { try await adapter.submit(makeMerchantOnboardingDraft(), expectedIdentity: original); XCTFail() }
        catch { XCTAssertEqual(error as? MerchantOnboardingWriteError, .outcomeUnknown) }
        XCTAssertEqual(transport.requests.count, 1)
    }
    func testUploadResponseCannotEnterNewAccountForm() async throws {
        let transport = MerchantOnboardingTransport(body: #"{"code":200,"url":"https://fixtures.example/license.jpg"}"#)
        var session = try MerchantOnboardingSession(accountID: 1, epoch: 1, token: "first-token")
        let original = session.identity
        let adapter = MerchantOnboardingSessionAdapter(service: try service(transport), currentSession: { session })
        transport.onSend = { session = try! .init(accountID: 2, epoch: 2, token: "second-token") }
        do {
            _ = try await adapter.uploadLicense(.init(jpegData: Data([0xff, 0xd8, 0xff])), expectedIdentity: original)
            XCTFail()
        } catch { XCTAssertEqual(error as? MerchantOnboardingWriteError, .outcomeUnknown) }
        XCTAssertEqual(transport.requests.count, 1)
    }
    func testInvalidCredentialHeadersAreRejectedLocally() throws {
        XCTAssertThrowsError(try MerchantOnboardingSession(accountID: 0, epoch: 1, token: "token"))
        XCTAssertThrowsError(try MerchantOnboardingSession(accountID: 1, epoch: 1, token: "token\r\nInjected: yes"))
    }
}
