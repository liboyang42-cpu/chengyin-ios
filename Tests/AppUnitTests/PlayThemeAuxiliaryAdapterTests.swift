import XCTest
@testable import Questify
#if canImport(QuestifyCore)
import QuestifyCore
#elseif canImport(Core)
import Core
#endif

@MainActor final class PlayThemeAuxiliaryAdapterTests: XCTestCase {
    private final class StubTransport: HTTPTransport {
        var requests: [URLRequest] = []
        var responseJSON = "[]"
        var status = 200
        var onSend: (() -> Void)?
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            onSend?()
            switch request.url?.lastPathComponent {
            case "phone":
                return (Data(#"{"code":200,"token":"synthetic-7","data":{"id":7,"role":"player"}}"#.utf8), 200)
            case "userInfo":
                return (Data(#"{"code":200,"appUser":{"id":7,"role":"player"}}"#.utf8), 200)
            case "logout":
                return (Data(#"{"code":200}"#.utf8), 200)
            default:
                return (Data(responseJSON.utf8), status)
            }
        }
    }

    private final class Vault: AppTokenStorage {
        var value: String?
        func read() throws -> String? { value }
        func write(_ token: String) throws { value = token }
        func clear() throws { value = nil }
    }

    private func makeConfig() throws -> APIConfiguration {
        try APIConfiguration(baseURL: XCTUnwrap(URL(string: "https://example.com")))
    }

    func testReaderReturnsNilWhenReadsDisabledOrSessionMissing() throws {
        let transport = StubTransport()
        let dormant = PlayExperienceService(configuration: try makeConfig(), transport: transport, enabled: [])
        let scope = PlaySessionScope.topic(71)
        let session = try PlayExperienceSession(accountID: 9, epoch: 1, namespace: "fixture-play", token: "tok")

        XCTAssertNil(PlayThemeAuxiliaryReader(service: dormant, scope: scope, topicID: 71, current: { session }))
        let enabled = PlayExperienceService(configuration: try makeConfig(), transport: transport, enabled: [.reads])
        XCTAssertNil(PlayThemeAuxiliaryReader(service: enabled, scope: scope, topicID: 71, current: { nil }))
        XCTAssertNil(PlayThemeAuxiliaryReader(service: enabled, scope: scope, topicID: 0, current: { session }))
    }

    func testReaderInvalidatesWhenSessionChangesMidFlight() async throws {
        let transport = StubTransport()
        let service = PlayExperienceService(configuration: try makeConfig(), transport: transport, enabled: [.reads])
        let scope = PlaySessionScope.topic(71)
        var current: PlayExperienceSession? = try PlayExperienceSession(accountID: 9, epoch: 1, namespace: "fixture-play", token: "tok")
        let replacement = try PlayExperienceSession(accountID: 10, epoch: 2, namespace: "fixture-play", token: "other")
        let reader = try XCTUnwrap(PlayThemeAuxiliaryReader(service: service, scope: scope, topicID: 71, current: { current }))

        transport.onSend = {
            current = replacement
        }
        transport.responseJSON = #"{"code":200,"data":[]}"#
        do {
            _ = try await reader.history(topicID: 71, beforeSessionID: nil)
            XCTFail("Expected staleSession error when account/epoch switches mid-flight")
        } catch let error as PlayExperienceError {
            XCTAssertEqual(error, .staleSession)
        }
    }

    func testStoreReplacesModelsOnRevisionOrTopicChange() throws {
        let transport = StubTransport()
        let service = PlayExperienceService(configuration: try makeConfig(), transport: transport, enabled: [.reads])
        let session = try PlayExperienceSession(accountID: 9, epoch: 1, namespace: "fixture-play", token: "tok")
        let provider: PlayThemeAuxiliaryProvider = { scope, topicID in
            PlayThemeAuxiliaryReader(service: service, scope: scope, topicID: topicID, current: { session })
        }

        let store = PlayThemeAuxiliaryStore()
        let first = store.models(revision: 1, scope: .topic(71), topicID: 71, provider: provider)
        let same = store.models(revision: 1, scope: .topic(71), topicID: 71, provider: provider)
        XCTAssertTrue(first.records === same.records)
        XCTAssertTrue(first.backpack === same.backpack)

        let nextRev = store.models(revision: 2, scope: .topic(71), topicID: 71, provider: provider)
        XCTAssertFalse(first.records === nextRev.records)
        XCTAssertFalse(first.backpack === nextRev.backpack)
    }

    func testAppSessionRootWiringRequiresAcceptedReadGrantAndInvalidatesOnLogout() async throws {
        let unconfigured = AppSession()
        XCTAssertNil(unconfigured.playThemeAuxiliary(scope: .topic(71), topicID: 71))
        XCTAssertNil(unconfigured.playThemeAuxiliaryProvider(.topic(71), 71))

        let base = "https://example.com/play-aux"
        let deployment = try ReviewedAppDeployment(
            market: .china,
            baseURL: base,
            approvedBaseURLs: [.china: [base]],
            verifiedCapabilities: [.domesticChinaPhone],
            bundleIdentifier: "test.play.aux",
            realm: "fixture"
        )
        let suite = "play-aux-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let vault = Vault()
        let transport = StubTransport()
        var allowReads = false

        let root = AppCompositionRoot(
            deployment: .reviewed(deployment),
            storage: .init(defaults: defaults, tokenStore: { _ in vault }),
            makeTransport: { transport },
            sessionDependencies: { context in
                guard allowReads else { return .dormant }
                let endpoints = try? OperationEndpointApproval(
                    baseURL: context.baseURL,
                    namespace: context.session.namespace,
                    accountID: context.session.accountID,
                    paths: [
                        "api/play/theme/history",
                        "api/play/theme/card",
                        "api/play/theme/state"
                    ]
                )
                return .init(
                    configuration: .init(
                        play: .init(enabled: [.reads], endpoints: endpoints),
                        endpoints: endpoints
                    )
                )
            }
        )

        let session = root.makeSession()
        let store = PlayThemeAuxiliaryStore()

        // Signed-out: nil reader and zero requests.
        XCTAssertNil(session.playThemeAuxiliary(scope: .topic(71), topicID: 71))
        let guestModels = store.models(
            revision: session.sessionRevision,
            scope: .topic(71),
            topicID: 71,
            provider: session.playThemeAuxiliaryProvider
        )
        XCTAssertNil(guestModels.records)
        XCTAssertNil(guestModels.backpack)
        XCTAssertTrue(transport.requests.isEmpty)

        // Signed-in without play read grant: still nil and zero play requests.
        session.authChannels.cancel()
        await session.authChannels.loginWithPhone(phone: "10000000000", code: "123456")
        XCTAssertNotNil(session.account)
        let loginCount = transport.requests.count
        XCTAssertNil(session.playThemeAuxiliary(scope: .topic(71), topicID: 71))
        XCTAssertEqual(transport.requests.count, loginCount)

        // Relogin with accepted play read grant: live reader and coordinators are wired.
        await session.logout()
        allowReads = true
        session.authChannels.cancel()
        await session.authChannels.loginWithPhone(phone: "10000000000", code: "123456")
        let reader = try XCTUnwrap(session.playThemeAuxiliary(scope: .topic(71), topicID: 71))
        let activeModels = store.models(
            revision: session.sessionRevision,
            scope: .topic(71),
            topicID: 71,
            provider: session.playThemeAuxiliaryProvider
        )
        XCTAssertNotNil(activeModels.records)
        XCTAssertNotNil(activeModels.backpack)

        // Logout invalidates the captured reader and clears the store on next revision.
        await session.logout()
        XCTAssertNil(session.playThemeAuxiliary(scope: .topic(71), topicID: 71))
        let postLogoutModels = store.models(
            revision: session.sessionRevision,
            scope: .topic(71),
            topicID: 71,
            provider: session.playThemeAuxiliaryProvider
        )
        XCTAssertNil(postLogoutModels.records)
        XCTAssertNil(postLogoutModels.backpack)
        do {
            _ = try await reader.history(topicID: 71, beforeSessionID: nil)
            XCTFail("Expected staleSession after logout")
        } catch let error as PlayExperienceError {
            XCTAssertEqual(error, .staleSession)
        }
    }
}
