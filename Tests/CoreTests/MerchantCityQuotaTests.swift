import Foundation
import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class MerchantCityQuotaTests: XCTestCase {
    private func value(_ raw: String) throws -> MerchantContentValue {
        try JSONDecoder().decode(MerchantContentValue.self, from: Data(raw.utf8))
    }
    private func quota(_ raw: String) throws -> MerchantCityQuota { .init(catalog: try value(raw)) }
    private func draft() -> MerchantCityPlacementDraft {
        var draft = MerchantCityPlacementDraft(); draft.templateID = 4; draft.addressConfirmed = true; return draft
    }
    private func snapshot(_ catalog: String, query: MerchantContentQuery = .cityPlacement, templates: String = "[{\"id\":4}]") throws -> MerchantContentSnapshot {
        .init(query: query, scope: UUID(), access: try value(MerchantContentFixtureData.access).decoded(MerchantAccess.self),
              value: try value("{\"catalog\":" + catalog + ",\"templates\":" + templates + "}"), observedAt: Date())
    }
    func testZeroQuotaRemainsKnownAndHasNoPlacementCapacity() throws {
        let result = try quota(#"{"used":0,"max":0}"#)
        XCTAssertEqual(result.used, 0); XCTAssertEqual(result.maximum, 0)
        XCTAssertEqual(result.state, .none); XCTAssertFalse(result.canPlace)
    }
    func testReportedUsageIsPreservedWhenMaximumBecomesZero() throws {
        let result = try quota(#"{"used":3,"max":0}"#)
        XCTAssertEqual(result.used, 3); XCTAssertEqual(result.maximum, 0); XCTAssertEqual(result.state, .none)
    }
    func testOnlyKnownCapacityAboveUsageAllowsPlacement() throws {
        for raw in [#"{"used":0,"max":1}"#, #"{"used":2,"max":3}"#] {
            let result = try quota(raw); XCTAssertEqual(result.state, .available); XCTAssertTrue(result.canPlace)
        }
    }
    func testEqualOrExcessUsageIsFullWithoutClampingServerCounts() throws {
        for used in [3, 4] {
            let result = try quota("{\"used\":\(used),\"max\":3}")
            XCTAssertEqual(result.used, used); XCTAssertEqual(result.state, .full); XCTAssertFalse(result.canPlace)
        }
    }
    func testMissingOrNullCountsAreUnknownAsAPair() throws {
        for raw in ["null", "{}", #"{"used":0}"#, #"{"max":5}"#, #"{"used":null,"max":5}"#] {
            let result = try quota(raw); XCTAssertEqual(result.state, .unknown)
            XCTAssertNil(result.used); XCTAssertNil(result.maximum); XCTAssertFalse(result.canPlace)
        }
    }
    func testStringsBooleansFractionsAndNegativeCountsNeverGrantCapacity() throws {
        for bad in [#""0""#, "true", "false", "0.5", "-1", "[]", "{}"] {
            for raw in ["{\"used\":\(bad),\"max\":5}", "{\"used\":0,\"max\":\(bad)}"] {
                let result = try quota(raw); XCTAssertEqual(result.state, .unknown); XCTAssertFalse(result.canPlace)
            }
        }
    }
    func testUnknownQuotaDoesNotDeleteAuthorizedNodesOrApplications() throws {
        let catalog = try value(#"{"nodes":[{"poiId":17}],"applications":[{"id":91}],"max":null}"#)
        XCTAssertEqual(MerchantCityQuota(catalog: catalog).state, .unknown)
        XCTAssertEqual(catalog["nodes"].array?.count, 1); XCTAssertEqual(catalog["applications"].array?.count, 1)
    }
    func testPlacementReviewRejectsUnknownNoneAndFullQuota() throws {
        for catalog in ["{}", #"{"used":0,"max":0}"#, #"{"used":2,"max":2}"#, #"{"used":"0","max":5}"#] {
            XCTAssertThrowsError(try MerchantContentCommand.place(draft()).validate(against: snapshot(catalog)))
        }
    }
    func testAvailableQuotaStillNeedsOwnedTemplateAndPlacementQuery() throws {
        let available = #"{"used":0,"max":1}"#
        let command = MerchantContentCommand.place(draft())
        XCTAssertNoThrow(try command.validate(against: snapshot(available)))
        XCTAssertThrowsError(try command.validate(against: snapshot(available, templates: "[]")))
        XCTAssertThrowsError(try command.validate(against: snapshot(available, query: .city)))
    }
    func testRevalidationRejectsQuotaThatChangedAfterInitialReview() throws {
        let command = MerchantContentCommand.place(draft())
        XCTAssertNoThrow(try command.validate(against: snapshot(#"{"used":0,"max":1}"#)))
        for changed in [#"{"used":1,"max":1}"#, #"{"used":0,"max":0}"#, "{}"] {
            XCTAssertThrowsError(try command.validate(against: snapshot(changed)))
        }
    }
    func testPlacementRequestFieldsDoNotIncludeQuotaOrNewAuthority() throws {
        let request = try MerchantContentCommand.place(draft()).request()
        XCTAssertEqual(request.path, "api/merchant/city-node/save")
        guard case .form(let fields) = request.body else { return XCTFail("Expected existing form contract") }
        XCTAssertEqual(fields, ["templateId": "4", "radius": "80"])
    }
}

private final class CityQuotaFixtureTransport: MerchantContentOfflineTransport {
    var catalog = #"{"nodes":[],"applications":[],"used":0,"max":1}"#
    var requests: [URLRequest] = []
    private let fixture = MerchantContentFixtureTransport()
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        if request.url?.path == "/api/merchant/city-node/list" {
            return (Data(("{\"code\":200,\"data\":" + catalog + "}").utf8), 200)
        }
        return try await fixture.send(request)
    }
}

@MainActor final class MerchantCityQuotaCoordinatorTests: XCTestCase {
    private func service(_ transport: CityQuotaFixtureTransport) throws -> MerchantContentService {
        let session = try MerchantContentSession(accountID: 1, epoch: 1, storageScope: "quota-test", token: "synthetic-token")
        return .init(configuration: try APIConfiguration(baseURL: URL(string: "https://city-quota.example")!),
                     transport: transport, currentSession: { session }, journal: MerchantContentMemoryPendingStorage(),
                     execution: .injectedOfflineHarness)
    }
    private func command() -> MerchantContentCommand {
        var draft = MerchantCityPlacementDraft(); draft.templateID = 4; draft.addressConfirmed = true; return .place(draft)
    }
    func testReloadClearsOldFrozenReviewAndZeroQuotaCannotPrepareAnother() async throws {
        let transport = CityQuotaFixtureTransport(), service = try service(transport)
        let coordinator = MerchantContentCoordinator(service: service, query: .cityPlacement)
        await coordinator.load(); coordinator.prepare(command())
        let frozen = try XCTUnwrap(coordinator.review)
        transport.catalog = #"{"nodes":[],"applications":[],"used":0,"max":0}"#
        await coordinator.load(); XCTAssertNil(coordinator.review)
        coordinator.prepare(command()); XCTAssertNil(coordinator.review)
        await coordinator.confirm(frozen)
        XCTAssertFalse(transport.requests.contains { $0.url?.path == "/api/merchant/city-node/save" })
    }
    func testConfirmationRereadsQuotaAndRejectsChangedFrozenBaselineBeforeDispatch() async throws {
        let transport = CityQuotaFixtureTransport(), service = try service(transport)
        let coordinator = MerchantContentCoordinator(service: service, query: .cityPlacement)
        await coordinator.load(); coordinator.prepare(command())
        let frozen = try XCTUnwrap(coordinator.review)
        transport.catalog = #"{"nodes":[],"applications":[],"used":1,"max":1}"#
        await coordinator.confirm(frozen)
        XCTAssertNil(coordinator.receipt); XCTAssertTrue(try service.pending().isEmpty)
        XCTAssertEqual(transport.requests.filter { $0.url?.path == "/api/merchant/city-node/list" }.count, 2)
        XCTAssertFalse(transport.requests.contains { $0.url?.path == "/api/merchant/city-node/save" })
    }
}
