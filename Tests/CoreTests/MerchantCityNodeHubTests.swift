import Foundation
import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class MerchantCityNodeHubTests: XCTestCase {
    private func value(_ raw: String) throws -> MerchantContentValue { try JSONDecoder().decode(MerchantContentValue.self, from: Data(raw.utf8)) }

    func testListProjectionFollowsMiniRowRules() throws {
        let p = MerchantCityNodeHubProjection(list: try value(#"""
        {"nodes":[{"poiId":701,"name":"A","status":1,"templateTitle":"T","tags":"Night","validationMethod":4},
                  {"poiId":702,"name":"B","status":0,"validationMethod":"4"},{"poiId":703,"status":1},{"name":"no id"}],
         "applications":[{"id":81,"name":"P","applicationType":1,"auditStatus":2,"auditReason":"R"},{"id":83,"applicationType":2,"auditStatus":0},
                         {"id":84,"applicationType":2,"auditStatus":3},{"id":85,"applicationType":1,"auditStatus":1},{"applicationType":2}],
         "used":1,"max":3}
        """#))
        XCTAssertEqual(p.nodes.map(\.id), [701, 702])
        XCTAssertEqual(p.nodes[0].isOnline, true); XCTAssertEqual(p.nodes[0].tags, "Night"); XCTAssertTrue(p.nodes[0].usesPosterCode)
        XCTAssertFalse(p.nodes[1].isOnline); XCTAssertNil(p.nodes[1].templateTitle); XCTAssertFalse(p.nodes[1].usesPosterCode)
        XCTAssertEqual(p.applications.map(\.id), [81, 83, 84, 85])
        XCTAssertEqual(p.applications.map(\.audit), [.rejected, .reviewing, .reviewing, .approved])
        XCTAssertEqual(p.applications.map(\.kind), [.placement, .claim, .claim, .placement])
        XCTAssertEqual(p.applications[0].auditReason, "R")
        XCTAssertEqual(p.applications.map(\.withdrawable), [false, true, false, false])
        XCTAssertEqual(p.itemCount, 6); XCTAssertFalse(p.isEmpty); XCTAssertTrue(p.showsEmptyPlacementAction)
    }
    func testEmptyListKeepsQuotaAndUnknownQuotaHidesEmptyAction() throws {
        let known = MerchantCityNodeHubProjection(list: try value(#"{"nodes":[],"applications":[],"used":0,"max":3}"#))
        XCTAssertTrue(known.isEmpty); XCTAssertTrue(known.showsEmptyPlacementAction)
        let unknown = MerchantCityNodeHubProjection(list: try value(#"{"nodes":[],"applications":[],"used":"0","max":3}"#))
        XCTAssertEqual(unknown.quota.state, .unknown); XCTAssertFalse(unknown.showsEmptyPlacementAction)
        XCTAssertFalse(MerchantCityNodeHubProjection(list: try value(#"{"nodes":[],"applications":[],"used":3,"max":3}"#)).showsEmptyPlacementAction)
    }
    func testClaimableIsAllOrNothingAndFallsBackToCityCode() throws {
        let rows = try XCTUnwrap(MerchantCityClaimableProjection.rows(try value(#"[{"id":801,"name":"A","description":"D"},{"id":802,"name":"B","cityCode":"C1"},{"id":803,"name":"E"}]"#)))
        XCTAssertEqual(rows.map(\.detail), ["D", "C1", nil])
        XCTAssertNil(MerchantCityClaimableProjection.rows(try value(#"[{"id":801,"name":"A"},{"id":0,"name":"B"}]"#)))
        XCTAssertNil(MerchantCityClaimableProjection.rows(try value(#"{"rows":[]}"#)))
        XCTAssertEqual(MerchantCityClaimableProjection.rows(try value("[]")), [])
    }
    func testVerifyGrantNeedsSameMerchantAndRawPermission() {
        XCTAssertTrue(MerchantCityNodeVerifyGrant.allows(permissions: ["merchant:verify"], accessMerchantID: 31, contentMerchantID: 31))
        XCTAssertFalse(MerchantCityNodeVerifyGrant.allows(permissions: ["merchant:verify"], accessMerchantID: 32, contentMerchantID: 31))
        XCTAssertFalse(MerchantCityNodeVerifyGrant.allows(permissions: ["merchant:project:manage"], accessMerchantID: 31, contentMerchantID: 31))
        XCTAssertFalse(MerchantCityNodeVerifyGrant.allows(permissions: ["merchant:verify"], accessMerchantID: 31, contentMerchantID: nil))
    }
    func testWritesStayDormantOutsideTheOfflineHarness() {
        let path = "api/merchant/city-node/save"
        XCTAssertFalse(MerchantCityNodeWriteGate.enabled(permitsWrites: false, isOfflineExample: true, path: path))
        XCTAssertFalse(MerchantCityNodeWriteGate.enabled(permitsWrites: true, isOfflineExample: false, path: path))
        var gates = MerchantCityNPCParityGates(); gates.cityNodeWrites = true
        for market in RegionalMarket.allCases {
            XCTAssertFalse(MerchantCityNodeWriteGate.enabled(permitsWrites: true, isOfflineExample: false, path: path, gates: gates, market: market))
        }
        XCTAssertTrue(MerchantCityNodeWriteGate.enabled(permitsWrites: true, isOfflineExample: true, path: path))
        XCTAssertFalse(MerchantCityNodeWriteGate.enabled(permitsWrites: true, isOfflineExample: true, path: "api/merchant/city-node/poster-code"))
        XCTAssertFalse(MerchantCityNPCParityGates.disabled.cityNodeWrites)
    }
    func testPlacementReceiptAcceptsBareIntegerOrObjectID() throws {
        XCTAssertEqual(MerchantCityPlacementReceipt.applicationID(.integer(92)), 92)
        XCTAssertEqual(MerchantCityPlacementReceipt.applicationID(try value(#"{"id":93}"#)), 93)
        XCTAssertNil(MerchantCityPlacementReceipt.applicationID(.integer(0)))
        XCTAssertNil(MerchantCityPlacementReceipt.applicationID(.null))
        XCTAssertNil(MerchantCityPlacementReceipt.applicationID(try value(#"{"id":-1}"#)))
        let catalog = try value(#"{"applications":[{"id":92,"applicationType":1,"auditStatus":0}]}"#)
        XCTAssertTrue(MerchantCityPlacementReceipt.contains(applicationID: 92, catalog: catalog))
        XCTAssertFalse(MerchantCityPlacementReceipt.contains(applicationID: 93, catalog: catalog))
        XCTAssertTrue(MerchantCityPlacementReceipt.hasPendingPlacement(catalog))
        XCTAssertFalse(MerchantCityPlacementReceipt.hasPendingPlacement(try value(#"{"applications":[{"id":81,"applicationType":1,"auditStatus":2}]}"#)))
    }
    func testProfileAddressRejectsMissingAndZeroCoordinates() throws {
        let address = try XCTUnwrap(MerchantCityNodeProfileAddress(profile: try value(#"{"name":"S","address":"1 Street","locationLat":12.3,"locationLng":45.6}"#)))
        XCTAssertEqual([address.latitude, address.longitude, address.name, address.address], ["12.3", "45.6", "S", "1 Street"])
        XCTAssertNil(MerchantCityNodeProfileAddress(profile: try value(#"{"locationLat":0,"locationLng":0}"#)))
        XCTAssertNil(MerchantCityNodeProfileAddress(profile: try value(#"{"locationLat":12.3}"#)))
        XCTAssertNil(MerchantCityNodeProfileAddress(profile: try value(#"{"locationLat":"x","locationLng":1}"#)))
        XCTAssertNotNil(MerchantCityNodeProfileAddress(profile: try value(#"{"locationLat":0,"locationLng":1}"#)))
    }
    func testTemplateSummaryOnlyNamesKnownCodes() throws {
        let rows = try value(#"[{"id":71,"title":"T","interactionType":"hidden_menu","validationMethod":3},{"id":72,"title":"U","interactionType":"other","validationMethod":9}]"#)
        let known = MerchantCityNodeTemplateSummary(templateID: 71, templates: rows)
        XCTAssertEqual(known.title, "T"); XCTAssertEqual(known.interaction, "hidden_menu"); XCTAssertEqual(known.validationMethod, 3)
        let unknown = MerchantCityNodeTemplateSummary(templateID: 72, templates: rows)
        XCTAssertNil(unknown.interaction); XCTAssertNil(unknown.validationMethod)
        XCTAssertNil(MerchantCityNodeTemplateSummary(templateID: 99, templates: rows).title)
    }
    func testTimelineUsesEachStationsOwnFlagAndNeverCompletesReview() {
        XCTAssertEqual(MerchantCityNodeTimeline.states(templateReady: false, addressConfirmed: false, submitted: false), [.doing, .todo, .todo, .todo])
        XCTAssertEqual(MerchantCityNodeTimeline.states(templateReady: false, addressConfirmed: true, submitted: false), [.doing, .done, .todo, .todo])
        XCTAssertEqual(MerchantCityNodeTimeline.states(templateReady: true, addressConfirmed: true, submitted: false), [.done, .done, .doing, .todo])
        XCTAssertEqual(MerchantCityNodeTimeline.states(templateReady: true, addressConfirmed: true, submitted: true), [.done, .done, .done, .doing])
    }
    func testPosterCodeNeedsAnHTTPImageAndDropsTheRawCode() throws {
        let code = try MerchantCityNodePosterCode(try value(#"{"code":"SECRET","qrcodeUrl":" https://example.invalid/p.png ","nodeName":"N"}"#))
        XCTAssertEqual(code.imageURL.absoluteString, "https://example.invalid/p.png"); XCTAssertEqual(code.nodeName, "N")
        XCTAssertThrowsError(try MerchantCityNodePosterCode(try value(#"{"nodeName":"N"}"#)))
        XCTAssertThrowsError(try MerchantCityNodePosterCode(try value(#"{"qrcodeUrl":"javascript:alert(1)"}"#)))
        XCTAssertThrowsError(try MerchantCityNodePosterCode(try value(#"{"qrcodeUrl":"   "}"#)))
    }
}

private final class CityNodeSaveTransport: MerchantContentOfflineTransport {
    var saveData = "92"
    var requests: [URLRequest] = []
    private let fixture = MerchantContentFixtureTransport()
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        switch request.url?.path {
        case "/api/merchant/city-node/save": return (Data(("{\"code\":200,\"msg\":\"ok\",\"data\":" + saveData + "}").utf8), 200)
        case "/api/merchant/city-node/poster-code": return (Data(#"{"code":200,"data":{"code":"SECRET","qrcodeUrl":"https://example.invalid/p.png","nodeName":"N"}}"#.utf8), 200)
        default: return try await fixture.send(request)
        }
    }
}

@MainActor final class MerchantCityNodeServiceTests: XCTestCase {
    private func service(_ transport: CityNodeSaveTransport) throws -> MerchantContentService {
        let session = try MerchantContentSession(accountID: 1, epoch: 1, storageScope: "city-node-test", token: "synthetic-token")
        return .init(configuration: try APIConfiguration(baseURL: URL(string: "https://city-node.example")!), transport: transport,
                     currentSession: { session }, journal: MerchantContentMemoryPendingStorage(), execution: .injectedOfflineHarness)
    }
    private func place() -> MerchantContentCommand {
        var draft = MerchantCityPlacementDraft(); draft.templateID = 4; draft.addressConfirmed = true; return .place(draft)
    }
    private func submit(_ saveData: String) async throws -> (MerchantContentCoordinator, MerchantContentService) {
        let transport = CityNodeSaveTransport(); transport.saveData = saveData
        let service = try service(transport)
        let coordinator = MerchantContentCoordinator(service: service, query: .cityPlacement)
        await coordinator.load(); coordinator.prepare(place())
        await coordinator.confirm(try XCTUnwrap(coordinator.review))
        return (coordinator, service)
    }
    func testBareIntegerSaveReceiptIsAcknowledgedAndUnlocked() async throws {
        let (coordinator, service) = try await submit("92")
        XCTAssertEqual(coordinator.receipt.flatMap { MerchantCityPlacementReceipt.applicationID($0.data) }, 92)
        XCTAssertFalse(coordinator.locked); XCTAssertTrue(try service.pending().isEmpty)
    }
    func testObjectSaveReceiptStillWorks() async throws {
        let (coordinator, _) = try await submit(#"{"id":93}"#)
        XCTAssertEqual(coordinator.receipt.flatMap { MerchantCityPlacementReceipt.applicationID($0.data) }, 93)
    }
    func testMissingApplicationIDStaysUnknownAndLocked() async throws {
        let (coordinator, service) = try await submit("null")
        XCTAssertNil(coordinator.receipt); XCTAssertTrue(coordinator.locked); XCTAssertFalse(try service.pending().isEmpty)
    }
    func testPosterCodeUsesTheExistingFormEndpoint() async throws {
        let transport = CityNodeSaveTransport(), service = try service(transport)
        let code = try MerchantCityNodePosterCode(try await service.cityPosterCode(poiID: 701))
        XCTAssertEqual(code.nodeName, "N")
        let request = try XCTUnwrap(transport.requests.last)
        XCTAssertEqual(request.url?.path, "/api/merchant/city-node/poster-code")
        XCTAssertTrue(String(decoding: request.httpBody ?? Data(), as: UTF8.self).contains("name=\"poiId\"\r\n\r\n701"))
        do { _ = try await service.cityPosterCode(poiID: 0); XCTFail("Expected invalid") } catch { XCTAssertEqual(error as? MerchantContentFailure, .invalid) }
    }
}
