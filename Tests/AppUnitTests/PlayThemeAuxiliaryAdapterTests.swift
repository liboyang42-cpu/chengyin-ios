import XCTest
@testable import Questify
#if canImport(QuestifyCore)
import QuestifyCore
#elseif canImport(Core)
import Core
#endif

@MainActor final class PlayThemeAuxiliaryAdapterTests: XCTestCase {
    private final class StubTransport: HTTPTransport {
        var responseJSON = "[]"
        var status = 200
        var onSend: (() -> Void)?
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            onSend?()
            return (Data(responseJSON.utf8), status)
        }
    }

    private func makeConfig() throws -> APIConfiguration {
        try APIConfiguration(baseURL: XCTUnwrap(URL(string: "https://example.invalid")))
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
        let reader = try XCTUnwrap(PlayThemeAuxiliaryReader(service: service, scope: scope, topicID: 71, current: { current }))

        transport.onSend = {
            current = try? PlayExperienceSession(accountID: 10, epoch: 2, namespace: "fixture-play", token: "other")
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
}
