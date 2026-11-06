import Foundation
import XCTest
@testable import Questify

@MainActor final class NativeWebhookAppFixtureProvider: NativeWebhookScopeProvider, NativeWebhookRequestAuthorizer {
    let context: NativeWebhookContext
    var revoked = false
    init() throws {
        context = NativeWebhookContext(binding: try NativeWebhookBinding(accountID: "5", market: "CN", namespace: "offline-app-fixture",
            origin: URL(string: "https://webhook-app-fixture.invalid")!,
            scope: NativeWebhookScope(ownerID: NativeWebhookID(rawValue: "8")!, channelID: NativeWebhookID(rawValue: "9")!), authorizationVersion: "synthetic-permission-1"),
            eventCatalogue: .unavailable(code: "WEBHOOK_EVENT_CATALOGUE_UNAVAILABLE"))
    }
    func currentContext() async throws -> NativeWebhookContext { if revoked { throw NativeWebhookClientError.scopeChanged }; return context }
    func revalidate(_ binding: NativeWebhookBinding) async throws -> NativeWebhookContext {
        guard !revoked, context.binding == binding else { throw NativeWebhookClientError.scopeChanged }; return context
    }
    func authorize(_ request: URLRequest, binding: NativeWebhookBinding) async throws -> URLRequest { _ = try await revalidate(binding); return request }
    func unauthorized(_ binding: NativeWebhookBinding) { revoked = true }
}
@MainActor final class NativeWebhookAppFixtureTransport: HTTPTransport {
    var requests: [URLRequest] = []
    private var storedJSON = NativeWebhookAppFixtureTransport.json
    var unknown = false
    var onMutation: (() -> Void)?
    static let json = #"{"id":"11","channel_id":"9","owner_type":"CLUB","owner_id":"8","name":"离线合成集成","status":1,"deleted":false,"revision":4,"key_version":2,"events":["fixture.event"],"url_host":"target.invalid","created_at":null,"updated_at":null}"#
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        var json = storedJSON
        if request.httpMethod != "GET" {
            onMutation?()
            if unknown { throw URLError(.timedOut) }
            json = json.replacingOccurrences(of: #""revision":4"#, with: #""revision":5"#).replacingOccurrences(of: #""key_version":2"#, with: #""key_version":3"#)
            storedJSON = json
            json.removeLast(); json += #", "secret_shown_once":true,"secret":"synthetic-credential"}"#
        } else if request.url?.path == NativeWebhookRuntimeRoute.collection(.subscription) {
            json = "{\"list\":[" + json + "],\"has_more\":false,\"next_cursor\":null}"
        }
        return (Data(("{\"code\":200,\"data\":" + json + "}").utf8), 200)
    }
}
@MainActor final class NativeWebhookAppFixtureJournal: OperationPendingJournal {
    var record: OperationPendingRecord?
    func pending(ownerKey: String, targetKey: String) throws -> OperationPendingRecord? {
        guard record?.ownerKey == ownerKey, record?.targetKey == targetKey else { return nil }; return record
    }
    func write(_ record: OperationPendingRecord) throws { self.record = record }
    func clear(_ record: OperationPendingRecord) throws { guard self.record == record else { throw APIError.invalidRequest }; self.record = nil }
}
@MainActor enum NativeWebhookAppFixtures {
    static func model() throws -> (NativeWebhookViewModel, NativeWebhookCoordinator, NativeWebhookAppFixtureProvider, NativeWebhookAppFixtureTransport, NativeWebhookAppFixtureJournal) {
        let provider = try NativeWebhookAppFixtureProvider(), transport = NativeWebhookAppFixtureTransport(), journal = NativeWebhookAppFixtureJournal()
        let service = NativeWebhookHTTPService(provider: provider, authorizer: provider, transport: transport)
        let coordinator = NativeWebhookCoordinator(service: service, provider: provider, journal: NativeWebhookPendingJournal(journal: journal))
        return (NativeWebhookViewModel(makeCoordinator: { coordinator }), coordinator, provider, transport, journal)
    }
}

@MainActor final class NativeWebhookPresentationTests: XCTestCase {
    func testPendingUnknownAndReceivedArePresentedAsDifferentOutcomes() {
        XCTAssertNotEqual(NativeWebhookPresentation.delivery(.pending), NativeWebhookPresentation.delivery(.sent))
        XCTAssertNotEqual(NativeWebhookPresentation.delivery(.unknown), NativeWebhookPresentation.delivery(.failed))
        XCTAssertNotEqual(NativeWebhookPresentation.inbound(.received), NativeWebhookPresentation.inbound(.accepted))
    }
    func testDefaultEntryAndViewModelRemainClosed() async {
        let model = NativeWebhookViewModel(); await model.start()
        XCTAssertNil(model.coordinator); XCTAssertFalse(model.available); XCTAssertFalse(model.canMutate)
        XCTAssertNil(model.sheet); XCTAssertTrue(model.path.isEmpty)
        _ = NativeWebhookManagementEntry()
    }
    func testUserConfirmationThenOneTimeCredentialSurvivesReadbackAndClearsOnBackground() async throws {
        let (model, coordinator, _, transport, _) = try NativeWebhookAppFixtures.model(); await model.start()
        let resource = try XCTUnwrap(coordinator.resources.first)
        model.action(.rotate, resource: resource)
        XCTAssertEqual(model.sheet, .confirmation)
        XCTAssertTrue(transport.requests.allSatisfy { $0.httpMethod == "GET" })
        await model.confirm(try XCTUnwrap(coordinator.confirmation).id)
        XCTAssertEqual(model.sheet, .credential); XCTAssertNotNil(coordinator.credential)
        XCTAssertGreaterThan(transport.requests.filter { $0.httpMethod == "GET" }.count, 1)
        model.background(); XCTAssertNil(model.sheet); XCTAssertNil(coordinator.credential)
        await model.foreground(); XCTAssertNil(coordinator.credential)
    }
    func testDismissConfirmationHasZeroMutationsAndClearsDraftPresentation() async throws {
        let (model, coordinator, _, transport, _) = try NativeWebhookAppFixtures.model(); await model.start()
        model.action(.delete, resource: try XCTUnwrap(coordinator.resources.first)); model.dismissSheet()
        XCTAssertNil(coordinator.confirmation); XCTAssertNil(model.sheet)
        XCTAssertFalse(transport.requests.contains { $0.httpMethod != "GET" })
    }
    func testUnknownLocksFreshActionsAndExposesExplicitOriginalRecovery() async throws {
        let (model, coordinator, _, transport, journal) = try NativeWebhookAppFixtures.model(); await model.start()
        transport.unknown = true
        model.action(.rotate, resource: try XCTUnwrap(coordinator.resources.first)); await model.confirm(try XCTUnwrap(coordinator.confirmation).id)
        XCTAssertFalse(model.canMutate); XCTAssertNotNil(journal.record); XCTAssertNil(coordinator.credential)
        await model.openRecovery(); XCTAssertEqual(model.sheet, .recovery)
        XCTAssertEqual(transport.requests.filter { $0.httpMethod == "POST" }.count, 1)
    }
    func testLateEditorDismissalCannotCancelNewConfirmation() async throws {
        let (model, coordinator, _, transport, _) = try NativeWebhookAppFixtures.model(); await model.start()
        let resource = try XCTUnwrap(coordinator.resources.first)
        model.edit(resource); let oldBinding = model.sheetBinding
        model.setActive(false, resource: resource)
        let originalConfirmation = try XCTUnwrap(coordinator.confirmation)
        oldBinding.wrappedValue = nil
        XCTAssertEqual(model.sheet, .confirmation); XCTAssertEqual(coordinator.confirmation?.id, originalConfirmation.id)
        XCTAssertFalse(transport.requests.contains { $0.httpMethod != "GET" })
        model.dismissSheet(); XCTAssertNil(coordinator.confirmation)
    }
}
