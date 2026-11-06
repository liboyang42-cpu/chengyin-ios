import Foundation
import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class KnowledgeDraftDenialWire: HTTPTransport {
    var requests: [URLRequest] = []
    var response: () throws -> (Data, Int) = {
        (Data(#"{"code":200,"data":{"active":true,"merchant":{"id":31},"roleCode":"MERCHANT_OWNER","permissions":["merchant:profile:write"]}}"#.utf8), 200)
    }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        return try response()
    }
}

@MainActor final class MerchantKnowledgeDraftAccessDenialTests: XCTestCase {
    private final class Identity { var value: MerchantOperationsSession? }
    private func fixture() throws -> (MerchantNPCKnowledgeDraftCoordinator, KnowledgeDraftDenialWire, Identity) {
        let identity = Identity()
        identity.value = try .init(accountID: 7, epoch: 1, token: "synthetic-token", storageNamespace: "fixture")
        let wire = KnowledgeDraftDenialWire()
        let service = MerchantOperationsService(configuration: try .init(baseURL: URL(string: "https://knowledge.example.test")!), transport: wire)
        let reader = MerchantOperationsSessionReader(service: service, currentSession: { identity.value })
        return (.init(reader: reader), wire, identity)
    }
    private func edited() -> MerchantNPCKnowledgeDraft {
        var value = MerchantNPCKnowledgeDraft()
        value.products = [.init(name: "Synthetic tea", priceMinor: "500", currency: "CNY")]
        return value
    }
    private func deny(_ wire: KnowledgeDraftDenialWire, business: Bool) {
        wire.response = { (Data(#"{"code":403}"#.utf8), business ? 200 : 403) }
    }
    func testOpenHTTPAndBusinessDenialUseExistingDeniedStateAndExplicitRetry() async throws {
        for business in [false, true] {
            let (flow, wire, _) = try fixture()
            let allowed = wire.response
            deny(wire, business: business)
            await flow.open()
            XCTAssertEqual(flow.phase, .unavailable)
            XCTAssertEqual(flow.failure, .accessDenied)
            XCTAssertNil(flow.savedDraft)
            XCTAssertFalse(flow.canEdit)
            wire.response = allowed
            await flow.open()
            XCTAssertTrue(flow.canEdit)
            XCTAssertNil(flow.failure)
            XCTAssertTrue(flow.draft.isEmpty)
            XCTAssertEqual(wire.requests.count, 2)
            XCTAssertTrue(wire.requests.allSatisfy { $0.url?.path == "/api/merchant/access/me" })
        }
    }
    func testLocalSaveDenialClearsBothSavedAndEditedMemoryWithoutWriter() async throws {
        for business in [false, true] {
            let (flow, wire, _) = try fixture()
            await flow.open()
            flow.edit(edited()); await flow.saveLocally()
            XCTAssertNotNil(flow.savedDraft)
            var replacement = edited(); replacement.products[0].name = "Changed"
            flow.edit(replacement)
            deny(wire, business: business)
            await flow.saveLocally()
            XCTAssertEqual(flow.failure, .accessDenied)
            XCTAssertNil(flow.savedDraft)
            XCTAssertTrue(flow.draft.isEmpty)
            XCTAssertFalse(flow.savedThisEdit)
            XCTAssertFalse(flow.canEdit)
            XCTAssertEqual(wire.requests.count, 3)
            XCTAssertTrue(wire.requests.allSatisfy { $0.url?.path == "/api/merchant/access/me" })
        }
    }
    func testNetworkStillUnavailableAndIdentityChangeTakesPrecedenceOverDenial() async throws {
        let (flow, wire, identity) = try fixture()
        wire.response = { throw URLError(.timedOut) }
        await flow.open()
        XCTAssertEqual(flow.failure, .unavailable)
        wire.response = {
            identity.value = nil
            return (Data(), 403)
        }
        await flow.open()
        XCTAssertEqual(flow.failure, .contextChanged)
        XCTAssertTrue(flow.draft.isEmpty)
        XCTAssertNil(flow.savedDraft)
    }
}
