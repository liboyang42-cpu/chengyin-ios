import Foundation
import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private let pointAccessJSON = #"{"active":true,"merchant":{"id":31},"roleCode":"MERCHANT_OWNER","permissions":["merchant:profile:write","merchant:coop:manage"]}"#
private let pointJSON = #"{"id":31,"locationLat":31.2,"locationLng":121.4,"address":"Synthetic shop"}"#
private func decodePoint(_ json: String = pointJSON) throws -> MerchantNPCMapPoint {
    try JSONDecoder().decode(MerchantNPCMapPoint.self, from: Data(json.utf8))
}
private func pointEnvelope(_ json: String) -> String { "{\"code\":200,\"data\":\(json)}" }
private final class MapPointTransport: HTTPTransport {
    var replies: [String] = []
    var requests: [URLRequest] = []
    var afterSend: (() -> Void)?
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); afterSend?()
        guard !replies.isEmpty else { throw APIError.malformedResponse }
        return (Data(replies.removeFirst().utf8), 200)
    }
}
@MainActor private final class MapPointJournal: OperationPendingJournal {
    var record: OperationPendingRecord?
    func pending(ownerKey: String, targetKey: String) throws -> OperationPendingRecord? { record }
    func write(_ record: OperationPendingRecord) throws { self.record = record }
    func clear(_ record: OperationPendingRecord) throws { self.record = nil }
}

final class MerchantNPCMapPointContractTests: XCTestCase {
    func testOnlyBothCoordinatesMakeAddressSelected() throws {
        for json in [#"{"id":31,"address":"Address only"}"#, #"{"id":31,"locationLat":31.2,"address":"Half point"}"#, #"{"id":31,"locationLng":121.4}"#, #"{"id":31,"locationLat":"","locationLng":null}"#] {
            let value = try decodePoint(json)
            XCTAssertNil(value.coordinate); XCTAssertEqual(value.statusKey, "merchantMapPoint.unset")
            XCTAssertThrowsError(try value.fields)
        }
    }
    func testZeroAndNegativeCoordinatesAreNotDiscarded() throws {
        for coordinates in [(0.0, 0.0), (-90.0, -180.0), (90.0, 180.0)] {
            let value = try decodePoint("{\"id\":31,\"locationLat\":\(coordinates.0),\"locationLng\":\(coordinates.1)}")
            XCTAssertNotNil(value.coordinate); XCTAssertEqual(value.statusKey, "merchantMapPoint.selected")
        }
    }
    func testNumericStringsUseTheSourceGCJ02Contract() throws {
        let value = try decodePoint(#"{"id":"31","locationLat":" 31.2 ","locationLng":"121.4","locationVerified":1}"#)
        XCTAssertEqual(value.merchantID, 31); XCTAssertEqual(value.datum, .gcj02)
        XCTAssertEqual(value.coordinate?.latitude, 31.2)
    }
    func testInvalidCoordinatesNeverCountAsSelected() throws {
        for latitude in ["nan", "inf", "-inf", "91", "-91", "abc", "1,2"] {
            let value = try decodePoint("{\"id\":31,\"locationLat\":\"\(latitude)\",\"locationLng\":1}")
            XCTAssertNil(value.coordinate); XCTAssertNotNil(value.blocker)
        }
        for longitude in ["181", "-181", "NaN"] {
            XCTAssertNil(try decodePoint("{\"id\":31,\"locationLat\":1,\"locationLng\":\"\(longitude)\"}").coordinate)
        }
    }
    func testMalformedIdentityOrCoordinateTypeFailsRead() {
        for json in [#"{}"#, #"{"id":0}"#, #"{"id":true}"#, #"{"id":31,"locationLat":true}"#, #"{"id":31,"locationLng":{}}"#] {
            XCTAssertThrowsError(try decodePoint(json))
        }
    }
    func testManualEntryRequiresExplicitGCJ02AndNeverConverts() throws {
        let original = try decodePoint()
        for datum in [nil, WalkingCoordinateDatum.wgs84] {
            XCTAssertThrowsError(try original.replacing(latitude: "32", longitude: "122", address: "Test", confirmedDatum: datum))
        }
        let value = try original.replacing(latitude: "32", longitude: "122", address: " Test ", confirmedDatum: .gcj02)
        XCTAssertEqual(value.coordinate?.latitude, 32); XCTAssertEqual(value.coordinate?.longitude, 122)
        XCTAssertEqual(value.address, "Test"); XCTAssertEqual(value.merchantID, original.merchantID)
    }
    func testAddressLimitUsesBackendUTF16AndEmptyAddressIsSupported() throws {
        let original = try decodePoint()
        XCTAssertNoThrow(try original.replacing(latitude: "0", longitude: "0", address: "", confirmedDatum: .gcj02))
        XCTAssertNoThrow(try original.replacing(latitude: "0", longitude: "0", address: String(repeating: "a", count: 255), confirmedDatum: .gcj02))
        XCTAssertThrowsError(try original.replacing(latitude: "0", longitude: "0", address: String(repeating: "🙂", count: 128), confirmedDatum: .gcj02))
    }
    func testExactThreeFieldPatchNeverSendsOwnerOrVerification() throws {
        let value = try decodePoint()
        let draft = MerchantOperationsDraft.npcMapPoint(value)
        let preview = try XCTUnwrap(draft.previews().first)
        XCTAssertEqual(preview.path, "api/merchant/decor/save"); XCTAssertNil(preview.form)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: preview.json) as? [String: Any])
        XCTAssertEqual(Set(body.keys), ["locationLat", "locationLng", "address"])
        XCTAssertEqual(body["locationLat"] as? Double, 31.2); XCTAssertEqual(body["locationLng"] as? Double, 121.4)
        XCTAssertEqual(draft.reviewLines.map(\.value), ["31.2", "121.4", "Synthetic shop", "GCJ-02"])
        XCTAssertEqual(draft.destination, .npcMapPoint)
    }
    func testReadAndWritePermissionMustBothBePresent() throws {
        for permissions in [[], ["merchant:profile:write"], ["merchant:coop:manage"]] {
            let data = try JSONSerialization.data(withJSONObject: ["active": true, "merchant": ["id": 31], "roleCode": "MERCHANT_OWNER", "permissions": permissions])
            let access = try JSONDecoder().decode(MerchantOperationsAccess.self, from: data)
            XCTAssertFalse(access.allows(.npcMapPoint))
        }
        let access = try JSONDecoder().decode(MerchantOperationsAccess.self, from: Data(pointAccessJSON.utf8))
        XCTAssertTrue(access.allows(.npcMapPoint))
    }
    func testPointSharesStorefrontReplayTarget() {
        for destination in [MerchantOperationsDestination.profile, .decor, .gallery, .story, .businessStatus] {
            XCTAssertEqual(MerchantOperationsDestination.npcMapPoint.pendingTarget, destination.pendingTarget)
        }
    }
}

@MainActor final class MerchantNPCMapPointServiceTests: XCTestCase {
    private func service(_ transport: MapPointTransport) throws -> MerchantOperationsService {
        try .init(configuration: .init(baseURL: URL(string: "https://example.test/api-root")!), transport: transport)
    }
    private func access() throws -> MerchantOperationsAccess {
        try JSONDecoder().decode(MerchantOperationsAccess.self, from: Data(pointAccessJSON.utf8))
    }
    func testReadIsExactOwnerScopedPostAndRejectsAnotherMerchant() async throws {
        let transport = MapPointTransport(); transport.replies = [pointEnvelope(pointJSON), pointEnvelope(#"{"id":99,"locationLat":1,"locationLng":2}"#)]
        let service = try service(transport)
        _ = try await service.document(.npcMapPoint, access: access(), token: "synthetic-token")
        XCTAssertEqual(transport.requests[0].url?.path, "/api-root/api/merchant/coop-profile")
        XCTAssertEqual(transport.requests[0].httpMethod, "POST"); XCTAssertEqual(transport.requests[0].httpBody, Data("{}".utf8))
        do { _ = try await service.document(.npcMapPoint, access: access(), token: "synthetic-token"); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
    }
    func testDefaultLiveSaveIsDisabledBeforeNetwork() async throws {
        let transport = MapPointTransport(); let value = try decodePoint()
        do { _ = try await service(transport).save(.npcMapPoint(value), token: "synthetic-token"); XCTFail() }
        catch { XCTAssertEqual(error as? MerchantOperationsFailure, .liveWritesDisabled) }
        XCTAssertTrue(transport.requests.isEmpty)
    }
    func testReviewedSaveRechecksAccessAndBaselineBeforeExactPatch() async throws {
        let transport = MapPointTransport(); transport.replies = [pointEnvelope(pointAccessJSON), pointEnvelope(pointJSON), #"{"code":200,"msg":"Saved"}"#]
        let original = try decodePoint(), edited = try original.replacing(latitude: "32", longitude: "122", address: "New", confirmedDatum: .gcj02)
        let approval = try OperationEndpointApproval(baseURL: URL(string: "https://example.test/api-root")!, namespace: "synthetic", accountID: 7, paths: ["api/merchant/decor/save"])
        let journal = MapPointJournal()
        _ = try await service(transport).save(.npcMapPoint(edited), token: "synthetic-token", approval: approval, namespace: "synthetic", accountID: 7, baseline: .npcMapPoint(original), journal: journal, checkSession: {})
        XCTAssertEqual(transport.requests.map { $0.url!.lastPathComponent }, ["me", "coop-profile", "save"])
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: transport.requests[2].httpBody!) as? [String: Any])
        XCTAssertEqual(Set(body.keys), ["locationLat", "locationLng", "address"])
        XCTAssertEqual(body["address"] as? String, "New"); XCTAssertNil(journal.record)
    }
    func testForeignOwnerCannotBeSubstitutedIntoReviewedDraft() async throws {
        let transport = MapPointTransport(), journal = MapPointJournal()
        let original = try decodePoint(), foreign = try decodePoint(#"{"id":99,"locationLat":1,"locationLng":2}"#)
        let approval = try OperationEndpointApproval(baseURL: URL(string: "https://example.test/api-root")!, namespace: "synthetic", accountID: 7, paths: ["api/merchant/decor/save"])
        do { _ = try await service(transport).save(.npcMapPoint(foreign), token: "synthetic-token", approval: approval, namespace: "synthetic", accountID: 7, baseline: .npcMapPoint(original), journal: journal, checkSession: {}); XCTFail() }
        catch { XCTAssertEqual(error as? MerchantOperationsFailure, .notSent) }
        XCTAssertTrue(transport.requests.isEmpty)
    }
    func testRoleRevocationBeforeWriteNeverSendsPatch() async throws {
        let transport = MapPointTransport(); transport.replies = [pointEnvelope(#"{"active":true,"merchant":{"id":31},"roleCode":"MERCHANT_OWNER","permissions":["merchant:profile:write"]}"#)]
        let original = try decodePoint(), journal = MapPointJournal()
        let approval = try OperationEndpointApproval(baseURL: URL(string: "https://example.test/api-root")!, namespace: "synthetic", accountID: 7, paths: ["api/merchant/decor/save"])
        do { _ = try await service(transport).save(.npcMapPoint(original), token: "synthetic-token", approval: approval, namespace: "synthetic", accountID: 7, baseline: .npcMapPoint(original), journal: journal, checkSession: {}); XCTFail() }
        catch { XCTAssertEqual(error as? MerchantOperationsFailure, .accessDenied) }
        XCTAssertEqual(transport.requests.count, 1); XCTAssertNil(journal.record)
    }
}

@MainActor private final class MapPointReader: MerchantOperationsReading {
    var scope = UUID(), isAuthenticated = true
    var isConfigured = true
    var isOfflineExample = false
    var canSave = true
    var pending = false
    var readCount = 0, saveCount = 0
    var beforeRead: (() -> Void)?
    var afterSave: (() -> Void)?
    var readbackFailure = false
    var readback: MerchantNPCMapPoint?
    var saveError: MerchantOperationsFailure?
    var value = try! decodePoint()
    func access() async throws -> MerchantOperationsAccess { try JSONDecoder().decode(MerchantOperationsAccess.self, from: Data(pointAccessJSON.utf8)) }
    func hasPending(_ destination: MerchantOperationsDestination) -> Bool { pending }
    func document(_ destination: MerchantOperationsDestination) async throws -> MerchantOperationsDocument {
        readCount += 1; beforeRead?()
        if saveCount > 0, readbackFailure { throw APIError.malformedResponse }
        return .draft(.npcMapPoint(saveCount > 0 ? (readback ?? value) : value))
    }
    func saveReviewed(_ draft: MerchantOperationsDraft, baseline: MerchantOperationsDraft) async throws {
        saveCount += 1; afterSave?()
        if let saveError { pending = true; throw saveError }
    }
    func saveExample(_ draft: MerchantOperationsDraft) async throws { throw MerchantOperationsFailure.liveWritesDisabled }
}
@MainActor final class MerchantNPCMapPointCoordinatorTests: XCTestCase {
    private func reviewed(_ reader: MapPointReader) async throws -> (MerchantOperationsCoordinator, MerchantOperationsConfirmation) {
        let coordinator = MerchantOperationsCoordinator(reader: reader, destination: .npcMapPoint)
        await coordinator.load()
        coordinator.edit(.npcMapPoint(try reader.value.replacing(latitude: "32", longitude: "122", address: "Proposed", confirmedDatum: .gcj02)))
        coordinator.prepare()
        return (coordinator, try XCTUnwrap(coordinator.confirmation))
    }
    func testSaveDisplaysAuthoritativeReadbackRatherThanLocalProposal() async throws {
        let reader = MapPointReader(); reader.readback = try reader.value.replacing(latitude: "33", longitude: "123", address: "Server point", confirmedDatum: .gcj02)
        let (coordinator, confirmation) = try await reviewed(reader)
        await coordinator.confirm(confirmation)
        XCTAssertEqual(coordinator.baseline, .npcMapPoint(reader.readback!)); XCTAssertEqual(reader.readCount, 3)
        XCTAssertFalse(coordinator.isDirty); XCTAssertFalse(coordinator.isLocked)
        XCTAssertEqual(coordinator.issue, .key("merchantMapPoint.readback"))
        await coordinator.confirm(confirmation); XCTAssertEqual(reader.saveCount, 1)
    }
    func testAcknowledgedSaveWithFailedReadbackDoesNotReplayOrInventSuccess() async throws {
        let reader = MapPointReader(); reader.readbackFailure = true
        let (coordinator, confirmation) = try await reviewed(reader)
        await coordinator.confirm(confirmation)
        XCTAssertNil(coordinator.document); XCTAssertNil(coordinator.draft); XCTAssertFalse(coordinator.isLocked)
        XCTAssertEqual(coordinator.issue, .key("merchantMapPoint.readbackFailed"))
        await coordinator.confirm(confirmation); XCTAssertEqual(reader.saveCount, 1)
    }
    func testForeignReadbackIsDiscarded() async throws {
        let reader = MapPointReader(); reader.readback = try decodePoint(#"{"id":99,"locationLat":1,"locationLng":2}"#)
        let (coordinator, confirmation) = try await reviewed(reader); await coordinator.confirm(confirmation)
        XCTAssertNil(coordinator.draft); XCTAssertEqual(coordinator.issue, .key("merchantMapPoint.readbackFailed"))
    }
    func testUnknownWriteStaysLockedAfterRefreshAndReentry() async throws {
        let reader = MapPointReader(); reader.saveError = .outcomeUnknown
        let (coordinator, confirmation) = try await reviewed(reader); await coordinator.confirm(confirmation)
        XCTAssertTrue(coordinator.isLocked); await coordinator.load(); XCTAssertTrue(coordinator.isLocked)
        let reopened = MerchantOperationsCoordinator(reader: reader, destination: .npcMapPoint)
        await reopened.load(); XCTAssertTrue(reopened.isLocked); XCTAssertFalse(reopened.canReview)
        await coordinator.confirm(confirmation); XCTAssertEqual(reader.saveCount, 1)
    }
    func testChangedBaselineIsConflictWithoutWriting() async throws {
        let reader = MapPointReader(); let (coordinator, confirmation) = try await reviewed(reader)
        reader.value = try reader.value.replacing(latitude: "34", longitude: "124", address: "Changed", confirmedDatum: .gcj02)
        await coordinator.confirm(confirmation)
        XCTAssertEqual(coordinator.issue, .key("merchant.operations.conflict")); XCTAssertEqual(reader.saveCount, 0)
    }
    func testAccountChangeBeforeConfirmAndDuringReadBlocksWrite() async throws {
        let reader = MapPointReader(); let (coordinator, confirmation) = try await reviewed(reader)
        reader.beforeRead = { reader.scope = UUID() }
        await coordinator.confirm(confirmation); XCTAssertEqual(reader.saveCount, 0)
        reader.beforeRead = nil; await coordinator.load(); coordinator.prepare()
        reader.scope = UUID(); await coordinator.confirm(confirmation); XCTAssertEqual(reader.saveCount, 0)
    }
    func testAccountChangeAfterSendDoesNotApplyStaleResponse() async throws {
        let reader = MapPointReader(); let (coordinator, confirmation) = try await reviewed(reader)
        reader.afterSave = { reader.scope = UUID() }
        await coordinator.confirm(confirmation)
        XCTAssertFalse(coordinator.isCurrent); XCTAssertNotEqual(coordinator.baseline, .npcMapPoint(try reader.value.replacing(latitude: "32", longitude: "122", address: "Proposed", confirmedDatum: .gcj02)))
    }
    func testCancelReviewDoesNotSendOrChangeBaseline() async throws {
        let reader = MapPointReader(); let (coordinator, confirmation) = try await reviewed(reader)
        coordinator.cancelConfirmation(); await coordinator.confirm(confirmation)
        XCTAssertEqual(reader.saveCount, 0); XCTAssertEqual(coordinator.baseline, .npcMapPoint(reader.value))
    }
}
