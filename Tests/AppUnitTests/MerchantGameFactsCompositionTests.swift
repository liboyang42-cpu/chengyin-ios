import XCTest
import SwiftUI
@testable import Questify

/// Synthetic session/transport and isolated defaults only. No production calls.
@MainActor final class MerchantGameFactsCompositionTests: XCTestCase {
    private let base = URL(string: "https://facts.example.test/native")!
    private func home(_ json: String) throws -> PublicMerchantHome {
        try JSONDecoder().decode(PublicMerchantHome.self, from: Data(json.utf8))
    }
    func testNoNPCCardRequiredAndReturnedRowIsNeverOwnerOrReleaseID() throws {
        let value = try home(#"{"id":31,"memberId":77}"#)
        XCTAssertFalse(value.hasNPCIdentity)
        let selected = try XCTUnwrap(MerchantGameFactsSelection(home: value, target: .ownerMemberID(PublicMerchantOwnerID(77)!), scope: UUID(), snapshot: UUID()))
        XCTAssertEqual(selected.row.rawValue, 31)
    }
    func testMissingRowMismatchedOwnerAndMismatchedLegacyTargetHaveNoEntry() throws {
        let scope = UUID(), snapshot = UUID()
        for json in [#"{"memberId":77}"#, #"{"id":0,"memberId":77}"#, #"{"id":-1,"memberId":77}"#] {
            XCTAssertNil(MerchantGameFactsSelection(home: try home(json), target: .ownerMemberID(PublicMerchantOwnerID(77)!), scope: scope, snapshot: snapshot))
        }
        let value = try home(#"{"id":31,"memberId":77}"#)
        XCTAssertNil(MerchantGameFactsSelection(home: value, target: .ownerMemberID(PublicMerchantOwnerID(31)!), scope: scope, snapshot: snapshot))
        XCTAssertNil(MerchantGameFactsSelection(home: value, target: .legacyMerchantRowID(PublicMerchantRowID(77)!), scope: scope, snapshot: snapshot))
    }
    func testSelectionRetiresWhenRowTargetReaderScopeOrSnapshotChanges() throws {
        let value = try home(#"{"id":31,"memberId":77}"#), scope = UUID(), snapshot = UUID()
        let target = PublicMerchantHomeTarget.ownerMemberID(PublicMerchantOwnerID(77)!)
        let selected = try XCTUnwrap(MerchantGameFactsSelection(home: value, target: target, scope: scope, snapshot: snapshot))
        XCTAssertTrue(selected.matches(home: value, target: target, scope: scope, snapshot: snapshot))
        XCTAssertFalse(selected.matches(home: value, target: target, scope: UUID(), snapshot: snapshot))
        XCTAssertFalse(selected.matches(home: value, target: target, scope: scope, snapshot: UUID()))
        XCTAssertFalse(selected.matches(home: value, target: .legacyMerchantRowID(PublicMerchantRowID(31)!), scope: scope, snapshot: snapshot))
        XCTAssertFalse(selected.matches(home: try home(#"{"id":32,"memberId":77}"#), target: target, scope: scope, snapshot: snapshot))
        XCTAssertFalse(selected.matches(home: try home(#"{"id":31,"memberId":88}"#), target: target, scope: scope, snapshot: snapshot))
    }
    func testPresentationFactoryIsLazySingleUseAndNeverReopensRetiredOwner() {
        var count = 0, current = true
        let owner = MerchantGameFactsPresentation(current: { current }, make: { count += 1; return nil })
        XCTAssertEqual(count, 0); XCTAssertFalse(owner.prepared)
        owner.prepare(); owner.prepare(); XCTAssertEqual(count, 1)
        current = false; owner.revoke(); current = true; owner.prepare()
        XCTAssertEqual(count, 1); XCTAssertNil(owner.coordinator)
    }
    func testStaleUnopenedPresentationNeverConstructsCoordinator() {
        var count = 0
        let owner = MerchantGameFactsPresentation(current: { false }, make: { count += 1; return nil })
        owner.prepare(); XCTAssertTrue(owner.prepared); XCTAssertEqual(count, 0)
    }
    func testDefaultFactsRendererDoesNotCreateReadGrantOrChatAuthority() throws {
        let wire = Wire(), root = try root(wire, grantPaths: nil)
        XCTAssertNotNil(root.merchantGamePlayerDestination)
        let context = RuntimeDependencyContext(market: .china, baseURL: base, role: "player",
            session: try PlayExperienceSession(accountID: 7, epoch: 1, namespace: "fixture", token: "synthetic-7"))
        XCTAssertNil(root.merchantGamePlayerReadGrant(context))
        let session = root.makeSession(), home = session.publicMerchantHomeContext
        XCTAssertNotNil(home.gameFactsDestination); XCTAssertNil(home.gamePlayerDestination)
        XCTAssertFalse(home.shopNpcChat); XCTAssertTrue(wire.requests.isEmpty)
        XCTAssertNil(session.readOnlyPublicMerchantHomeContext.gameFactsDestination)
        XCTAssertNil(session.readOnlyPublicMerchantHomeContext.gamePlayerDestination)
    }
    func testSignedInWithoutGrantShowsConfigurationAndSendsNoGETOrPOST() async throws {
        let wire = Wire(), composition = try root(wire, grantPaths: nil), session = composition.makeSession()
        await login(session); wire.requests = []
        let coordinator = try XCTUnwrap(session.makeMerchantGamePlayerCoordinator(merchantID: 31))
        await coordinator.load()
        XCTAssertEqual(coordinator.failure, .configuration); XCTAssertTrue(wire.requests.isEmpty)
        XCTAssertNotNil(session.publicMerchantHomeContext.gameFactsDestination)
        XCTAssertNil(session.publicMerchantHomeContext.gamePlayerDestination)
    }
    func testPublicationOnlyGrantDoesNotInstallOriginalResultChatGate() async throws {
        let wire = Wire(), composition = try root(wire, grantPaths: ["api/merchant/authoring/player/{merchantId}/game"])
        let session = composition.makeSession(); await login(session); wire.requests = []
        XCTAssertNotNil(session.publicMerchantHomeContext.gameFactsDestination)
        XCTAssertNil(session.publicMerchantHomeContext.gamePlayerDestination)
        XCTAssertFalse(session.publicMerchantHomeContext.shopNpcChat)
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testExistingApprovedChatRemainsSeparateAndWrapperRequiresBothReadPaths() async throws {
        for readEnabled in [false, true] {
            let wire = Wire(), composition = try root(wire,
                grantPaths: readEnabled ? MerchantGamePlayerReadGrant.playerPaths : nil, chatApproved: true)
            let session = composition.makeSession(); await login(session); wire.requests = []
            let context = session.publicMerchantHomeContext
            XCTAssertNotNil(context.gameFactsDestination); XCTAssertNotNil(context.npcDestination)
            XCTAssertTrue(context.shopNpcChat)
            XCTAssertEqual(context.gamePlayerDestination != nil, readEnabled)
            XCTAssertTrue(wire.requests.isEmpty)
        }
    }
    func testRealSessionFactoryReadsSameOriginalAndOnlyExplicitACKClearsMarker() async throws {
        let wire = Wire(), composition = try root(wire, grantPaths: MerchantGamePlayerReadGrant.playerPaths)
        let session = composition.makeSession(); await login(session); wire.requests = []
        let record = try record(composition); wire.requestID = record.operationID
        let journal = composition.storage.operationJournal(); try journal.write(record)
        let coordinator = try XCTUnwrap(session.makeMerchantGamePlayerCoordinator(merchantID: 31))
        let context = session.publicMerchantHomeContext
        XCTAssertNotNil(context.gameFactsDestination); XCTAssertNil(context.gamePlayerDestination)
        XCTAssertFalse(context.shopNpcChat)
        await coordinator.load(); XCTAssertEqual(coordinator.pending, record); XCTAssertFalse(coordinator.canOpenChat)
        await coordinator.readOriginal(); XCTAssertTrue(coordinator.canAcknowledge)
        XCTAssertEqual(try journal.pending(ownerKey: record.ownerKey, targetKey: record.targetKey), record)
        XCTAssertEqual(wire.requests.count, 2)
        XCTAssertTrue(wire.requests.allSatisfy { $0.httpMethod == "GET" && $0.httpBody == nil })
        XCTAssertTrue(wire.requests.last!.url!.path.hasSuffix(record.operationID.uuidString))
        coordinator.acknowledgeOriginal()
        XCTAssertNil(try journal.pending(ownerKey: record.ownerKey, targetKey: record.targetKey))
        XCTAssertEqual(wire.requests.count, 2)
    }
    func testPresentationRevokesLoadedPrivateProjectionWithoutClearingOriginal() async throws {
        let wire = Wire(), composition = try root(wire, grantPaths: MerchantGamePlayerReadGrant.playerPaths)
        let session = composition.makeSession(); await login(session); wire.requests = []
        let record = try record(composition); wire.requestID = record.operationID
        let journal = composition.storage.operationJournal(); try journal.write(record)
        let coordinator = try XCTUnwrap(session.makeMerchantGamePlayerCoordinator(merchantID: 31))
        let owner = MerchantGameFactsPresentation(current: { true }, make: { coordinator }); owner.prepare()
        await coordinator.load(); await coordinator.readOriginal(); XCTAssertNotNil(coordinator.original)
        owner.revoke()
        XCTAssertNil(owner.coordinator); XCTAssertNil(coordinator.original); XCTAssertNil(coordinator.publication)
        XCTAssertFalse(coordinator.canOpenChat); XCTAssertFalse(coordinator.canAcknowledge)
        XCTAssertEqual(try journal.pending(ownerKey: record.ownerKey, targetKey: record.targetKey), record)
    }
    private func record(_ composition: AppCompositionRoot) throws -> OperationPendingRecord {
        let reviewed = try XCTUnwrap(composition.reviewed), api = try XCTUnwrap(reviewed.regional.apiConfiguration)
        let namespace = reviewed.storageScope.service
        return .init(ownerKey: "merchant-public-chat:\(api.baseURL.absoluteString):\(namespace.utf8.count):\(namespace):7", targetKey: "merchant-row:31")
    }
    private func root(_ wire: Wire, grantPaths: Set<String>?, chatApproved: Bool = false) throws -> AppCompositionRoot {
        let suite = "merchant-facts-" + UUID().uuidString, defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let deployment = try ReviewedAppDeployment(market: .china, baseURL: base.absoluteString,
            approvedBaseURLs: [.china: [base.absoluteString]], verifiedCapabilities: [.domesticChinaPhone],
            bundleIdentifier: "test.merchant-facts", realm: "synthetic")
        let vault = Vault()
        var root = AppCompositionRoot(deployment: .reviewed(deployment), storage: .init(defaults: defaults, tokenStore: { _ in vault }), makeTransport: { wire }, sessionDependencies: { context in
            guard chatApproved, let approval = try? MerchantPublicProductionApproval(market: context.market,
                baseURL: context.baseURL, namespace: context.session.namespace, accountID: context.session.accountID,
                publicHomeRead: true, chatMerchantRows: [PublicMerchantRowID(31)!]) else { return .dormant }
            var grants = MerchantNPCGrants(); grants.server = true; grants.provider = true; grants.legal = true
            return .init(merchantPublicApproval: approval, merchantNPCGrants: grants)
        })
        if let grantPaths {
            root.merchantGamePlayerReadGrant = { context in
                guard let endpoints = try? OperationEndpointApproval(baseURL: context.baseURL, namespace: context.session.namespace,
                    accountID: context.session.accountID, paths: grantPaths) else { return nil }
                return MerchantGamePlayerReadGrant(market: context.market, endpoints: endpoints)
            }
        }
        return root
    }
    private func login(_ session: AppSession) async {
        session.authChannels.cancel(); await session.authChannels.loginWithPhone(phone: "10000000000", code: "123456")
        XCTAssertEqual(session.account?.id, 7)
    }
    private final class Vault: AppTokenStorage {
        var value: String?
        func read() throws -> String? { value }
        func write(_ token: String) throws { value = token }
        func clear() throws { value = nil }
    }
    private final class Wire: HTTPTransport {
        var requests: [URLRequest] = [], requestID = UUID()
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            let path = request.url!.path, json: String
            if path.hasSuffix("/appLogin") { json = #"{"code":200,"token":"synthetic-7","data":{"id":7,"role":"player"}}"# }
            else if path.hasSuffix("/userInfo") { json = #"{"code":200,"appUser":{"userId":7,"role":"player"}}"# }
            else if path.hasSuffix("/player/31/game") { json = #"{"code":200,"data":{"merchantId":31,"outcome":"PUBLISHED","releaseId":99,"revisionVersion":2,"facts":{"canonical_plot":"Published facts only"}}}"# }
            else if path.hasSuffix("/player/31/requests/" + requestID.uuidString) {
                json = "{\"code\":200,\"data\":{\"merchantId\":31,\"requestId\":\"\(requestID.uuidString)\",\"outcomeStatus\":\"REJECTED\",\"safetyDecision\":\"NOT_RUN\",\"safeText\":\"Original fixed exit\",\"errorCode\":\"MERCHANT_ENVIRONMENT_EXIT\",\"retryable\":false,\"ai\":false}}"
            } else { throw APIError.notConfigured }
            return (Data(json.utf8), 200)
        }
    }
}
