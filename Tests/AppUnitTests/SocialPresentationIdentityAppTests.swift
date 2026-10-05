import XCTest
import Observation
@testable import Questify

@MainActor final class SocialPresentationIdentityAppTests: XCTestCase {
    func testFixtureChangeIsObservableThroughErasedReaderAndReplacesArticleIdentity() async throws {
        let fixture = SocialAccountFixtureReader(.articleHTML), reader: any SocialAccountReading = fixture
        let first = try await reader.information(id: 91)
        XCTAssertTrue(first.contents?.contains("示例正文标题") == true)
        let changed = expectation(description: "Pushed reader presentation invalidated")
        let previous = withObservationTracking {
            SocialReadPresentationKey(reader: reader, request: "information-91", requiresSignIn: false)
        } onChange: { changed.fulfill() }
        fixture.switchAccount()
        await fulfillment(of: [changed], timeout: 2)
        XCTAssertNotEqual(previous, SocialReadPresentationKey(reader: reader, request: "information-91", requiresSignIn: false))
        let replacement = try await reader.information(id: 91)
        XCTAssertTrue(replacement.contents?.contains("替换正文标题") == true)
        XCTAssertFalse(replacement.contents?.contains("示例正文标题") == true)
    }
    func testReaderReplacementRequestAndSignInRequirementEachRetirePresentationKey() {
        let first = SocialAccountSessionReader(service: nil, currentSession: { .init(guestEpoch: 1) })
        let second = SocialAccountSessionReader(service: nil, currentSession: { .init(guestEpoch: 1) })
        let old = SocialReadPresentationKey(reader: first, request: "information-91", requiresSignIn: false)
        XCTAssertNotEqual(old, .init(reader: second, request: "information-91", requiresSignIn: false))
        XCTAssertNotEqual(old, .init(reader: first, request: "information-92", requiresSignIn: false))
        XCTAssertNotEqual(old, .init(reader: first, request: "information-91", requiresSignIn: true))
        first.invalidatePresentation(); first.invalidatePresentation()
        XCTAssertNotEqual(old, .init(reader: first, request: "information-91", requiresSignIn: false))
    }
    func testNormalSessionLoginRoleABAAndLogoutInvalidateSameSocialReaderWithoutGrantingReads() async throws {
        let wire = Wire(), vault = Vault(), base = "https://example.com/native"
        let deployment = try ReviewedAppDeployment(market: .china, baseURL: base, approvedBaseURLs: [.china: [base]],
            verifiedCapabilities: [.domesticChinaPhone], bundleIdentifier: "test.social.presentation", realm: "synthetic")
        let suite = "social-presentation-" + UUID().uuidString, defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let session = AppCompositionRoot(deployment: .reviewed(deployment), storage: .init(defaults: defaults, tokenStore: { _ in vault }), makeTransport: { wire }).makeSession()
        let reader = session.socialAccountReader, initial = reader.presentationRevision
        await session.authChannels.loginWithPhone(phone: "10000000000", code: "123456")
        XCTAssertEqual(session.account?.id, 7); XCTAssertGreaterThan(reader.presentationRevision, initial)
        let old = SocialReadPresentationKey(reader: reader, request: "information-91", requiresSignIn: false)
        wire.role = "merchant"; await session.refreshOwnAccount(); wire.role = "player"; await session.refreshOwnAccount()
        XCTAssertNotEqual(old, .init(reader: reader, request: "information-91", requiresSignIn: false))
        let revision = reader.presentationRevision
        await session.logout()
        XCTAssertTrue(reader === session.socialAccountReader)
        XCTAssertGreaterThan(reader.presentationRevision, revision); XCTAssertNil(reader.identity.accountID); XCTAssertNil(vault.token)
        let before = wire.requests.count
        do { _ = try await reader.information(id: 91); XCTFail("No social grant is installed") }
        catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        XCTAssertEqual(wire.requests.count, before)
        XCTAssertTrue(wire.requests.allSatisfy { ["phone", "userInfo", "logout"].contains($0.url?.lastPathComponent ?? "") })
    }
    @MainActor private final class Vault: AppTokenStorage {
        var token: String?
        func read() throws -> String? { token }
        func write(_ value: String) throws { token = value }
        func clear() throws { token = nil }
    }
    @MainActor private final class Wire: HTTPTransport {
        var role = "player", requests: [URLRequest] = []
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            let json: String
            switch request.url?.lastPathComponent {
            case "phone": json = #"{"code":200,"token":"synthetic-7","data":{"id":7,"role":"player"}}"#
            case "userInfo": json = "{\"code\":200,\"appUser\":{\"userId\":7,\"role\":\"\(role)\"}}"
            case "logout": json = #"{"code":200}"#
            default: throw APIError.invalidRequest
            }
            return (Data(json.utf8), 200)
        }
    }
}
