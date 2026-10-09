import Foundation
import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class MerchantCityClaimWithdrawalTests: XCTestCase {
    private let pending = #"{"id":91,"name":"Synthetic place","applicationType":2,"auditStatus":0}"#
    private func value(_ raw: String) throws -> MerchantContentValue { try MerchantContentFixtureData.value(raw) }
    private func snapshot(_ rows: String, query: MerchantContentQuery = .city, access: String = MerchantContentFixtureData.access) throws -> MerchantContentSnapshot {
        .init(query: query, scope: UUID(), access: try value(access).decoded(MerchantAccess.self),
              value: try value("{\"applications\":" + rows + "}"), observedAt: Date())
    }
    func testExactRoamPOIRowResolvesAndKeepsDisplayedName() throws {
        let s = try snapshot("[" + pending + "]")
        let target = try XCTUnwrap(MerchantCityClaimWithdrawal(poiID: 91, snapshot: s))
        XCTAssertEqual(target.poiID, 91); XCTAssertEqual(target.name, "Synthetic place")
        XCTAssertNoThrow(try MerchantContentCommand.cancelClaim(poiID: 91).validate(against: s))
    }
    func testMatchingExplicitPOIIDIsAcceptedButConflictAndAliasOnlyAreRejected() throws {
        let matching = pending.replacingOccurrences(of: #""id":91"#, with: #""id":91,"poiId":91"#)
        XCTAssertNotNil(MerchantCityClaimWithdrawal(poiID: 91, snapshot: try snapshot("[" + matching + "]")))
        for row in [pending.replacingOccurrences(of: #""id":91"#, with: #""id":91,"poiId":92"#),
                    pending.replacingOccurrences(of: #""id":91"#, with: #""poiId":91"#)] {
            XCTAssertNil(MerchantCityClaimWithdrawal(poiID: 91, snapshot: try snapshot("[" + row + "]")))
        }
    }
    func testMissingUnsafeAndMalformedIdentityCannotResolve() throws {
        for raw in ["0", "-1", "true", #""91""#, "91.5", "9007199254740992", "null"] {
            let row = pending.replacingOccurrences(of: #""id":91"#, with: #""id":"# + raw)
            let s = try snapshot("[" + row + "]")
            XCTAssertNil(MerchantCityClaimWithdrawal(row: try value(row), snapshot: s))
        }
    }
    func testNonClaimNonPendingAndVisibilityStatusDoNotAuthorizeWithdrawal() throws {
        let rows = [pending.replacingOccurrences(of: #""applicationType":2"#, with: #""applicationType":1"#),
                    pending.replacingOccurrences(of: #""auditStatus":0"#, with: #""status":0"#)]
            + [1, 2, 3].map { pending.replacingOccurrences(of: #""auditStatus":0"#, with: "\"auditStatus\":\($0)") }
        for row in rows { XCTAssertNil(MerchantCityClaimWithdrawal(poiID: 91, snapshot: try snapshot("[" + row + "]"))) }
    }
    func testDuplicateAndConflictingAliasRowsCannotSelectOneTarget() throws {
        for other in [pending, pending.replacingOccurrences(of: #""id":91"#, with: #""id":"91""#),
                      pending.replacingOccurrences(of: #""id":91"#, with: #""id":92,"poiId":91"#)] {
            XCTAssertNil(MerchantCityClaimWithdrawal(poiID: 91, snapshot: try snapshot("[" + pending + "," + other + "]")))
        }
    }
    func testOnlyCurrentAuthorizedCityApplicationRowsCanBeUsed() throws {
        let rows = "[" + pending + "]"
        XCTAssertNil(MerchantCityClaimWithdrawal(poiID: 91, snapshot: try snapshot(rows, query: .applications)))
        XCTAssertNil(MerchantCityClaimWithdrawal(poiID: 91, snapshot: try snapshot(rows, access: #"{"active":true,"merchant":{"id":31},"roleCode":"MERCHANT_OWNER","permissions":[]}"#)))
        XCTAssertNil(MerchantCityClaimWithdrawal(row: try value(pending), snapshot: try snapshot("[]")))
        let changed = pending.replacingOccurrences(of: "Synthetic place", with: "Old source")
        XCTAssertNil(MerchantCityClaimWithdrawal(row: try value(changed), snapshot: try snapshot(rows)))
    }
    func testAnAssignedNodeOrForeignApplicantCannotBeWithdrawn() throws {
        for field in [#""merchantId":31"#, #""applicantMerchantId":32"#] {
            let row = String(pending.dropLast()) + "," + field + "}"
            XCTAssertNil(MerchantCityClaimWithdrawal(poiID: 91, snapshot: try snapshot("[" + row + "]")))
        }
        let own = String(pending.dropLast()) + #", "applicantMerchantId":31, "merchantId":null}"#
        XCTAssertNotNil(MerchantCityClaimWithdrawal(poiID: 91, snapshot: try snapshot("[" + own + "]")))
    }
    func testRequestKeepsTheExistingPOIFieldAndNoNewPermissionOrEndpoint() throws {
        let request = try MerchantContentCommand.cancelClaim(poiID: 91).request()
        XCTAssertEqual(request.path, "api/merchant/city-node/claim/cancel")
        guard case .form(let fields) = request.body else { return XCTFail("Existing form expected") }
        XCTAssertEqual(fields, ["poiId": "91"])
    }
}

private final class CityClaimWithdrawalFixtureTransport: MerchantContentOfflineTransport {
    var catalog = #"{"nodes":[],"applications":[{"id":91,"applicationType":2,"auditStatus":0}],"used":0,"max":0}"#
    var requests: [URLRequest] = []
    private let fixture = MerchantContentFixtureTransport()
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        if request.url?.path == "/api/merchant/city-node/list" { return (Data(("{\"code\":200,\"data\":" + catalog + "}").utf8), 200) }
        return try await fixture.send(request)
    }
}
@MainActor final class MerchantCityClaimWithdrawalCoordinatorTests: XCTestCase {
    private func makeService(_ transport: CityClaimWithdrawalFixtureTransport) throws -> MerchantContentService {
        let session = try MerchantContentSession(accountID: 1, epoch: 1, storageScope: "withdraw-test", token: "synthetic-token")
        return .init(configuration: try APIConfiguration(baseURL: URL(string: "https://city-withdrawal.example")!), transport: transport,
                     currentSession: { session }, journal: MerchantContentMemoryPendingStorage(), execution: .injectedOfflineHarness)
    }
    func testCancellingReviewDispatchesNothingEvenWithZeroQuota() async throws {
        let transport = CityClaimWithdrawalFixtureTransport(), service = try makeService(transport)
        let coordinator = MerchantContentCoordinator(service: service, query: .city)
        await coordinator.load(); coordinator.prepare(.cancelClaim(poiID: 91))
        let review = try XCTUnwrap(coordinator.review)
        coordinator.cancelReview(); await coordinator.confirm(review)
        XCTAssertFalse(transport.requests.contains { $0.url?.path.hasSuffix("claim/cancel") == true })
    }
    func testChangedReviewStatusStopsConfirmationBeforeDispatch() async throws {
        let transport = CityClaimWithdrawalFixtureTransport(), service = try makeService(transport)
        let coordinator = MerchantContentCoordinator(service: service, query: .city)
        await coordinator.load(); coordinator.prepare(.cancelClaim(poiID: 91))
        let review = try XCTUnwrap(coordinator.review)
        transport.catalog = transport.catalog.replacingOccurrences(of: #""auditStatus":0"#, with: #""auditStatus":3"#)
        await coordinator.confirm(review)
        XCTAssertNil(coordinator.receipt); XCTAssertTrue(try service.pending().isEmpty)
        XCTAssertFalse(transport.requests.contains { $0.url?.path.hasSuffix("claim/cancel") == true })
    }
    func testReloadInvalidatesOldReviewAndResolvedApplicationCannotBeReused() async throws {
        let transport = CityClaimWithdrawalFixtureTransport(), service = try makeService(transport)
        let coordinator = MerchantContentCoordinator(service: service, query: .city)
        await coordinator.load(); coordinator.prepare(.cancelClaim(poiID: 91))
        let review = try XCTUnwrap(coordinator.review)
        transport.catalog = #"{"nodes":[],"applications":[],"used":0,"max":0}"#
        await coordinator.load(); coordinator.prepare(.cancelClaim(poiID: 91)); XCTAssertNil(coordinator.review)
        await coordinator.confirm(review)
        XCTAssertFalse(transport.requests.contains { $0.url?.path.hasSuffix("claim/cancel") == true })
    }
}
