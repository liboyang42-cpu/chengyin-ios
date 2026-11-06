import Foundation
import SwiftUI
import XCTest
@testable import Questify

@MainActor private final class MarketingSettingsVault: AppTokenStorage {
    var value: String? = "synthetic-settings-7"
    func read() throws -> String? { value }
    func write(_ token: String) throws { value = token }
    func clear() throws { value = nil }
}
@MainActor private final class MarketingSettingsWire: HTTPTransport {
    var requests: [URLRequest] = []
    var role = "player", status = 200, code = 200, choice = false
    var recorded: [String: Bool] = [:]
    var afterReply: (() -> Void)?
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        if request.url?.lastPathComponent == "userInfo" { return (Data("{\"code\":200,\"appUser\":{\"userId\":7,\"role\":\"\(role)\"}}".utf8), 200) }
        defer { afterReply?() }
        let value: Any
        if request.httpMethod == "POST" {
            let body = try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as! [String: Any]
            choice = body["optedIn"] as! Bool; recorded[body["requestId"] as! String] = choice; value = [:]
        } else if request.url?.lastPathComponent == "result" {
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            let id = query.first { $0.name == "requestId" }!.value!
            var receipt: [String: Any] = ["receiptVersion": 1, "actorId": 7, "merchantRowId": 41, "merchantOwnerMemberId": 7,
                "channel": "IN_APP", "requestId": id, "outcome": recorded[id] == nil ? "NOT_OBSERVED" : "RECORDED"]
            if let optedIn = recorded[id] { receipt["consentId"] = 19; receipt["eventType"] = optedIn ? "OPT_IN" : "OPT_OUT"; receipt["recordedAt"] = 1 }
            value = receipt
        } else {
            value = [["merchantRowId": 41, "merchantOwnerMemberId": 7, "merchantName": "Synthetic shop", "inAppOptedIn": choice, "couponOptedIn": false]]
        }
        return (try JSONSerialization.data(withJSONObject: ["code": code, "data": value]), status)
    }
}
@MainActor private final class MarketingSettingsFixture {
    let wire = MarketingSettingsWire(), vault = MarketingSettingsVault()
    let root: AppCompositionRoot
    let suite = "marketing-settings-" + UUID().uuidString
    let defaults: UserDefaults
    init() throws {
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let deployment = try ReviewedAppDeployment(market: .china, baseURL: "https://settings.example.test/native",
            approvedBaseURLs: [.china: ["https://settings.example.test/native"]], verifiedCapabilities: [.domesticChinaPhone],
            bundleIdentifier: "test.marketing." + UUID().uuidString.lowercased(), realm: "synthetic")
        let vault = vault, wire = wire
        root = .init(deployment: .reviewed(deployment), storage: .init(defaults: defaults, tokenStore: { _ in vault }), makeTransport: { wire })
    }
    func boot() async -> AppSession { let session = root.makeSession(); await session.bootstrap(); wire.requests = []; return session }
    func cleanup() { root.merchantMarketingConsentSelection.revoke(); defaults.removePersistentDomain(forName: suite) }
    func configuration(writes: Bool = false) throws -> MerchantMarketingConsentRuntimeConfiguration {
        let reviewed = try XCTUnwrap(root.reviewed), api = try XCTUnwrap(reviewed.regional.apiConfiguration)
        let read = try OperationEndpointApproval(baseURL: api.baseURL, namespace: reviewed.storageScope.service, accountID: 7, paths: MerchantMarketingConsentRuntimeConfiguration.readPaths)
        let write: OperationEndpointApproval?
        if writes { write = try OperationEndpointApproval(baseURL: api.baseURL, namespace: reviewed.storageScope.service, accountID: 7, paths: [MerchantMarketingConsentOriginalClient.path]) }
        else { write = nil }
        let grants: Set<MerchantMarketingConsentOriginalGrant> = writes ? [try .init(merchantID: 41, ownerID: 7, channel: .inApp, optedIn: true), try .init(merchantID: 41, ownerID: 7, channel: .inApp, optedIn: false)] : []
        return try .init(read: read, write: write, grants: grants, issuanceID: UUID())
    }
    func context() throws -> RuntimeDependencyContext {
        let reviewed = try XCTUnwrap(root.reviewed), api = try XCTUnwrap(reviewed.regional.apiConfiguration)
        return .init(market: .china, baseURL: api.baseURL, role: "player", session: try .init(accountID: 7, epoch: 1, namespace: reviewed.storageScope.service, token: "synthetic-settings-7"))
    }
}

/// Authored normal-host tests with local synthetic wire only; no production or Apple runtime claim.
@MainActor final class MarketingOriginalSettingsHostTests: XCTestCase {
    private func fixture() throws -> MarketingSettingsFixture {
        let h = try MarketingSettingsFixture(); addTeardownBlock { @MainActor in h.cleanup() }; return h
    }
    func testDefaultSourceIsEmptyAndNormalSettingsCoordinatorMakesNoMarketingRequest() async throws {
        let h = try fixture(), session = await h.boot(), context = try h.context()
        XCTAssertNil(h.root.selectedMerchantMarketingConsentApproval(context))
        let flow = try XCTUnwrap(session.accountComplianceCoordinator); await flow.loadMarketing()
        XCTAssertEqual(flow.state.error, "compliance.unavailable"); XCTAssertTrue(h.wire.requests.isEmpty)
    }
    func testReadOnlySourceLoadsCurrentButCannotOfferEitherChannelChange() async throws {
        let h = try fixture(), session = await h.boot(); try h.root.merchantMarketingConsentSelection.replace(with: h.configuration())
        let flow = try XCTUnwrap(session.accountComplianceCoordinator), model = ComplianceViewModel(flow, isMarketing: true)
        await flow.loadMarketing(intent: try XCTUnwrap(model.marketingRead()))
        let row = try XCTUnwrap(model.state.marketing.first)
        XCTAssertTrue(model.state.marketingLoaded); XCTAssertNil(flow.reviewMarketing(row, channel: .inApp, optedIn: true)); XCTAssertNil(flow.reviewMarketing(row, channel: .coupon, optedIn: true))
        XCTAssertEqual(h.wire.requests.map(\.httpMethod), ["GET"])
    }
    func testNormalHostExplicitChoiceUsesOriginalReceiptWithoutBorrowingGenericGate() async throws {
        let h = try fixture(), session = await h.boot(); try h.root.merchantMarketingConsentSelection.replace(with: h.configuration(writes: true))
        let flow = try XCTUnwrap(session.accountComplianceCoordinator), model = ComplianceViewModel(flow, isMarketing: true)
        await flow.loadMarketing(intent: try XCTUnwrap(model.marketingRead()))
        let review = try XCTUnwrap(flow.reviewMarketing(XCTUnwrap(model.state.marketing.first), channel: .inApp, optedIn: true))
        await flow.setMarketing(review, explicitlyConfirmed: true)
        XCTAssertEqual(h.wire.requests.map(\.httpMethod), ["GET", "GET", "GET", "POST", "GET", "GET"])
        XCTAssertTrue(model.state.marketingOriginalResults.first?.recorded == true); XCTAssertTrue(model.state.marketing.first?.inAppOptedIn == true)
        XCTAssertTrue(h.wire.requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "synthetic-settings-7" })
    }
    func testRevokeImmediatelyClearsPrivateRowsAndDoesNotResumeOldOwner() async throws {
        let h = try fixture(), session = await h.boot(); try h.root.merchantMarketingConsentSelection.replace(with: h.configuration())
        let flow = try XCTUnwrap(session.accountComplianceCoordinator), model = ComplianceViewModel(flow, isMarketing: true)
        await flow.loadMarketing(intent: try XCTUnwrap(model.marketingRead())); XCTAssertFalse(model.state.marketing.isEmpty)
        h.root.merchantMarketingConsentSelection.revoke()
        XCTAssertTrue(model.state.marketing.isEmpty); XCTAssertNil(model.marketingRead(resume: true))
        XCTAssertEqual(h.wire.requests.count, 1)
    }
    func testOldMarketingModelCannotEndNewC08Model() async throws {
        let h = try fixture(), session = await h.boot(), flow = try XCTUnwrap(session.accountComplianceCoordinator)
        let old = ComplianceViewModel(flow, isMarketing: true), next = ComplianceViewModel(flow, isDeregistration: true)
        let intent = try XCTUnwrap(next.cancellationIntent()); old.endPresentation(); h.root.merchantMarketingConsentSelection.revoke()
        XCTAssertTrue(flow.isCurrentDeregistrationIntent(intent)); XCTAssertNotNil(next.cancellationIntent())
    }
    func testOldC08ModelCannotEndNewMarketingModel() async throws {
        let h = try fixture(), session = await h.boot(), flow = try XCTUnwrap(session.accountComplianceCoordinator)
        let old = ComplianceViewModel(flow, isDeregistration: true), next = ComplianceViewModel(flow, isMarketing: true)
        let intent = try XCTUnwrap(next.marketingRead()); old.endPresentation()
        XCTAssertTrue(flow.isCurrentMarketingRead(intent)); XCTAssertNotNil(next.marketingRead())
    }
    func testBackgroundPauseDropsQueuedReadAndForegroundRequiresFreshOriginalOwnerIntent() async throws {
        let h = try fixture(), session = await h.boot(); try h.root.merchantMarketingConsentSelection.replace(with: h.configuration())
        let flow = try XCTUnwrap(session.accountComplianceCoordinator), model = ComplianceViewModel(flow, isMarketing: true)
        let old = try XCTUnwrap(model.marketingRead()); model.pauseMarketing()
        await flow.loadMarketing(intent: old); XCTAssertTrue(h.wire.requests.isEmpty)
        await flow.loadMarketing(intent: try XCTUnwrap(model.marketingRead(resume: true)))
        XCTAssertEqual(h.wire.requests.count, 1)
    }
    func testReissueRetiresOldReviewAndCannotReuseRetiredIssuance() async throws {
        let h = try fixture(), session = await h.boot(), first = try h.configuration(writes: true)
        try h.root.merchantMarketingConsentSelection.replace(with: first)
        let flow = try XCTUnwrap(session.accountComplianceCoordinator), model = ComplianceViewModel(flow, isMarketing: true)
        await flow.loadMarketing(intent: try XCTUnwrap(model.marketingRead()))
        let review = try XCTUnwrap(flow.reviewMarketing(XCTUnwrap(model.state.marketing.first), channel: .inApp, optedIn: true))
        try h.root.merchantMarketingConsentSelection.replace(with: h.configuration(writes: true))
        await flow.setMarketing(review, explicitlyConfirmed: true)
        XCTAssertEqual(h.wire.requests.count, 1); XCTAssertNil(model.marketingRead(resume: true))
        XCTAssertThrowsError(try h.root.merchantMarketingConsentSelection.replace(with: first))
    }
    func testRoleRefreshRetiresOldScreenBeforeAQueuedRead() async throws {
        let h = try fixture(), session = await h.boot(); try h.root.merchantMarketingConsentSelection.replace(with: h.configuration())
        let flow = try XCTUnwrap(session.accountComplianceCoordinator), model = ComplianceViewModel(flow, isMarketing: true), intent = try XCTUnwrap(model.marketingRead())
        h.wire.role = "merchant"; await session.refreshOwnAccount(); h.wire.requests = []
        await flow.loadMarketing(intent: intent); XCTAssertTrue(h.wire.requests.isEmpty); XCTAssertNil(model.marketingRead(resume: true))
    }
    func testLateSourceRevoked401DoesNotExpireCurrentAccountOrVault() async throws {
        for status in [200, 401] {
            let h = try fixture(), session = await h.boot(); try h.root.merchantMarketingConsentSelection.replace(with: h.configuration())
            let flow = try XCTUnwrap(session.accountComplianceCoordinator)
            h.wire.code = 401; h.wire.status = status; h.wire.afterReply = { h.root.merchantMarketingConsentSelection.revoke() }
            await flow.loadMarketing()
            XCTAssertEqual(session.account?.id, 7); XCTAssertEqual(h.vault.value, "synthetic-settings-7"); XCTAssertTrue(flow.state.marketing.isEmpty)
        }
    }
    func testCompleteViewerRevisionFenceRejectsOldTransportAfterABA() async throws {
        let h = try fixture(), context = try h.context(), configuration = try h.configuration(), approval = try XCTUnwrap(configuration.approval(for: context)), host = h.root.transport()
        var viewer = CompositionHTTPTransport.SessionIdentity(epoch: 1, accountID: 7, role: "player", token: "synthetic-settings-7", viewerRevision: 1)
        host.current = { viewer }
        let scoped = try XCTUnwrap(host.makeMerchantMarketingConsentOriginalTransport(context: context, approval: approval, currentRuntime: { context }, stillApproved: { true }))
        viewer = .init(epoch: 1, accountID: 7, role: "player", token: "synthetic-settings-7", viewerRevision: 3)
        let client = MerchantMarketingConsentOriginalClient(context: context, approval: approval, transport: scoped, current: { context }, stillApproved: { true }, onUnauthorized: { XCTFail() })
        do { _ = try await client.list(session: .init(accountID: 7, epoch: 1, market: "CN", namespace: context.session.namespace)); XCTFail() } catch {}
        XCTAssertTrue(h.wire.requests.isEmpty)
    }
    func testGenericHostCannotBorrowOriginalMarketingSelection() async throws {
        let h = try fixture(), context = try h.context(), configuration = try h.configuration(writes: true)
        try h.root.merchantMarketingConsentSelection.replace(with: configuration)
        let host = h.root.transport(); host.current = { .init(epoch: 1, accountID: 7, role: "player", token: "synthetic-settings-7") }
        let approval = try XCTUnwrap(configuration.approval(for: context))
        let client = MerchantMarketingConsentOriginalClient(context: context, approval: approval, transport: host, current: { context }, stillApproved: { true })
        do { _ = try await client.list(session: .init(accountID: 7, epoch: 1, market: "CN", namespace: context.session.namespace)); XCTFail() } catch {}
        XCTAssertTrue(h.wire.requests.isEmpty)
    }
    func testIndependentWriteEndpointAndExactContextAreRequired() throws {
        let h = try fixture(), context = try h.context(), read = try h.configuration().read
        let grant = try MerchantMarketingConsentOriginalGrant(merchantID: 41, ownerID: 7, channel: .inApp, optedIn: true)
        XCTAssertThrowsError(try MerchantMarketingConsentRuntimeConfiguration(read: read, grants: [grant], issuanceID: UUID()))
        let foreign = RuntimeDependencyContext(market: .china, baseURL: URL(string: "https://other.example.test")!, role: context.role, session: context.session)
        XCTAssertNil(try h.configuration().approval(for: foreign))
    }
    func testOriginalFactsAndUnknownCopyHaveBilingualDedicatedResources() throws {
        let keys = ["marketingOriginal.scope", "marketingOriginal.receipt.historyOnly", "marketingOriginal.current.unconfirmed",
            "marketingOriginal.outcome.notObserved", "compliance.marketing.empty", "compliance.marketing.unknown", "compliance.marketing.review",
            "compliance.marketing.confirmOptIn", "compliance.marketing.confirmOptOut"]
        let app = Bundle(for: ComplianceViewModel.self)
        for language in ["en", "zh-Hans"] {
            let bundle = try XCTUnwrap(Bundle(path: XCTUnwrap(app.path(forResource: language, ofType: "lproj"))))
            for key in keys { XCTAssertNotEqual(bundle.localizedString(forKey: key, value: nil, table: "MarketingConsentOriginalPresentation"), key) }
        }
        XCTAssertEqual(MarketingConsentOriginalPresentation.outcomeKey("NOT_OBSERVED"), "marketingOriginal.outcome.notObserved")
        XCTAssertEqual(MarketingConsentOriginalPresentation.outcomeKey("unexpected"), "marketingOriginal.outcome.unknown")
    }
}
