import Foundation
import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private let readOnlyPointJSON = #"{"id":31,"locationLat":31.2,"locationLng":121.4,"address":"Synthetic shop"}"#
private func readOnlyAccessData(_ permissions: [String] = ["merchant:coop:manage"],
                                role: String = "MERCHANT_MARKETING", active: Bool = true,
                                merchantID: Int = 31) throws -> Data {
    try JSONSerialization.data(withJSONObject: ["active": active, "merchant": ["id": merchantID],
                                               "roleCode": role, "permissions": permissions])
}
private func readOnlyAccess(_ permissions: [String] = ["merchant:coop:manage"],
                            role: String = "MERCHANT_MARKETING", active: Bool = true,
                            merchantID: Int = 31) throws -> MerchantOperationsAccess {
    try JSONDecoder().decode(MerchantOperationsAccess.self, from: readOnlyAccessData(permissions, role: role, active: active, merchantID: merchantID))
}
private func readOnlyEnvelope(_ data: Data) -> String { "{\"code\":200,\"data\":\(String(decoding: data, as: UTF8.self))}" }
private final class ReadOnlyPointTransport: HTTPTransport {
    var replies: [String] = []
    var requests: [URLRequest] = []
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        guard !replies.isEmpty else { throw APIError.malformedResponse }
        return (Data(replies.removeFirst().utf8), 200)
    }
}
@MainActor private final class ReadOnlyPointJournal: OperationPendingJournal {
    var record: OperationPendingRecord?
    var writeCount = 0, clearCount = 0
    func pending(ownerKey: String, targetKey: String) throws -> OperationPendingRecord? { record }
    func write(_ record: OperationPendingRecord) throws { writeCount += 1; self.record = record }
    func clear(_ record: OperationPendingRecord) throws { clearCount += 1; self.record = nil }
}

@MainActor final class MerchantNPCMapPointReadOnlyServiceTests: XCTestCase {
    private func service(_ transport: ReadOnlyPointTransport) throws -> MerchantOperationsService {
        try .init(configuration: .init(baseURL: URL(string: "https://example.test/api-root")!), transport: transport)
    }
    func testRecognizedRoleFixturesDecodeWithoutGrantingRoleDerivedPermissions() throws {
        for role in MerchantAccess.Role.allCases {
            let access = try readOnlyAccess([], role: role.rawValue)
            XCTAssertEqual(access.identity.role, role); XCTAssertFalse(access.cooperationManage)
            XCTAssertFalse(access.allows(.npcMapPoint))
        }
        for role in ["", "UNKNOWN_ROLE"] { XCTAssertThrowsError(try readOnlyAccess(role: role)) }
        let missingRole = #"{"active":true,"merchant":{"id":31},"permissions":["merchant:coop:manage"]}"#
        XCTAssertThrowsError(try JSONDecoder().decode(MerchantOperationsAccess.self, from: Data(missingRole.utf8)))
    }
    func testCoopOnlyReadsExactOwnerScopedPointWithoutAWrite() async throws {
        let transport = ReadOnlyPointTransport(); transport.replies = [readOnlyEnvelope(Data(readOnlyPointJSON.utf8))]
        let access = try readOnlyAccess()
        XCTAssertFalse(access.profileWrite); XCTAssertFalse(access.allows(.npcMapPoint))
        let document = try await service(transport).document(.npcMapPoint, access: access, token: "synthetic-token")
        guard case .draft(.npcMapPoint(let value)) = document else { return XCTFail() }
        XCTAssertEqual(value.merchantID, 31); XCTAssertEqual(value.address, "Synthetic shop")
        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertEqual(transport.requests[0].url?.path, "/api-root/api/merchant/coop-profile")
        XCTAssertEqual(transport.requests[0].httpMethod, "POST")
        XCTAssertEqual(transport.requests[0].httpBody, Data("{}".utf8))
        XCTAssertEqual(transport.requests[0].value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertFalse(transport.requests.contains { $0.url?.lastPathComponent == "save" })
    }
    func testReadWithoutCoopPermissionOrInactiveIdentityMakesNoRequest() async throws {
        for access in [try readOnlyAccess([]), try readOnlyAccess(["merchant:profile:write"]), try readOnlyAccess(active: false)] {
            let transport = ReadOnlyPointTransport()
            do { _ = try await service(transport).document(.npcMapPoint, access: access, token: "synthetic-token"); XCTFail() }
            catch { XCTAssertEqual(error as? MerchantOperationsFailure, .accessDenied) }
            XCTAssertTrue(transport.requests.isEmpty)
        }
    }
    func testCoopOnlyReadStillRejectsForeignMerchant() async throws {
        let transport = ReadOnlyPointTransport(); transport.replies = [readOnlyEnvelope(Data(#"{"id":99,"locationLat":1,"locationLng":2}"#.utf8))]
        do { _ = try await service(transport).document(.npcMapPoint, access: readOnlyAccess(), token: "synthetic-token"); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
        XCTAssertEqual(transport.requests.count, 1)
    }
    func testCoopOnlyCannotUseAnApprovedWriterOrMutateItsJournal() async throws {
        let transport = ReadOnlyPointTransport(); transport.replies = [readOnlyEnvelope(try readOnlyAccessData())]
        let original = try JSONDecoder().decode(MerchantNPCMapPoint.self, from: Data(readOnlyPointJSON.utf8))
        let proposed = try original.replacing(latitude: "32", longitude: "122", address: "Local proposal", confirmedDatum: .gcj02)
        let approval = try OperationEndpointApproval(baseURL: URL(string: "https://example.test/api-root")!, namespace: "synthetic", accountID: 7, paths: ["api/merchant/decor/save"])
        let journal = ReadOnlyPointJournal()
        do {
            _ = try await service(transport).save(.npcMapPoint(proposed), token: "synthetic-token", approval: approval,
                                                 namespace: "synthetic", accountID: 7, baseline: .npcMapPoint(original),
                                                 journal: journal, checkSession: {})
            XCTFail()
        } catch { XCTAssertEqual(error as? MerchantOperationsFailure, .accessDenied) }
        XCTAssertEqual(transport.requests.map { $0.url!.lastPathComponent }, ["me"])
        XCTAssertEqual(journal.writeCount, 0); XCTAssertEqual(journal.clearCount, 0); XCTAssertNil(journal.record)
    }
    func testSessionReaderReadOnlyFlowNeverSendsSaveOrMutatesJournal() async throws {
        let transport = ReadOnlyPointTransport(), journal = ReadOnlyPointJournal()
        let accessJSON = readOnlyEnvelope(try readOnlyAccessData())
        transport.replies = [accessJSON, accessJSON, readOnlyEnvelope(Data(readOnlyPointJSON.utf8)), accessJSON]
        let session = try MerchantOperationsSession(accountID: 7, epoch: 1, token: "synthetic-token", storageNamespace: "synthetic")
        let approval = try OperationEndpointApproval(baseURL: URL(string: "https://example.test/api-root")!, namespace: "synthetic", accountID: 7, paths: ["api/merchant/decor/save"])
        let reader = MerchantOperationsSessionReader(service: try service(transport), currentSession: { session }, approval: approval, journal: journal)
        let coordinator = MerchantNPCMapPointReadOnlyCoordinator(reader: reader)
        XCTAssertTrue(reader.canSave)
        await coordinator.load(); XCTAssertEqual(coordinator.point?.merchantID, 31); XCTAssertFalse(coordinator.canOpenEditor)
        coordinator.invalidate()
        XCTAssertEqual(transport.requests.map { $0.url!.lastPathComponent }, ["me", "me", "coop-profile", "me"])
        XCTAssertEqual(journal.writeCount, 0); XCTAssertEqual(journal.clearCount, 0); XCTAssertNil(journal.record)
    }
    func testReadGateDoesNotRelaxAnyOtherOperation() async throws {
        let transport = ReadOnlyPointTransport()
        for destination in [MerchantOperationsDestination.profile, .decor, .gallery, .story, .businessStatus] {
            do { _ = try await service(transport).document(destination, access: readOnlyAccess(), token: "synthetic-token"); XCTFail() }
            catch { XCTAssertEqual(error as? MerchantOperationsFailure, .accessDenied) }
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }
}

@MainActor private final class ReadOnlyPointReader: MerchantOperationsReading {
    var scope = UUID(), isAuthenticated = true
    var isConfigured = true, isOfflineExample = false, canSave = true
    var accessValue = try! readOnlyAccess()
    var point = try! JSONDecoder().decode(MerchantNPCMapPoint.self, from: Data(readOnlyPointJSON.utf8))
    var pending = false, readFailure = false
    var readCount = 0, accessCount = 0, saveCount = 0
    var afterRead: (() -> Void)?
    func access() async throws -> MerchantOperationsAccess { accessCount += 1; return accessValue }
    func hasPending(_ destination: MerchantOperationsDestination) -> Bool { pending }
    func document(_ destination: MerchantOperationsDestination) async throws -> MerchantOperationsDocument {
        readCount += 1; afterRead?()
        if readFailure { throw APIError.malformedResponse }
        return .draft(.npcMapPoint(point))
    }
    func saveReviewed(_ draft: MerchantOperationsDraft, baseline: MerchantOperationsDraft) async throws { saveCount += 1 }
    func saveExample(_ draft: MerchantOperationsDraft) async throws { saveCount += 1 }
}

@MainActor final class MerchantNPCMapPointReadOnlyCoordinatorTests: XCTestCase {
    func testReadOnlyLoadReloadAndDismissNeverExposeEditorOrSave() async throws {
        let reader = ReadOnlyPointReader()
        let coordinator = MerchantNPCMapPointReadOnlyCoordinator(reader: reader)
        await coordinator.load(); XCTAssertEqual(coordinator.point, reader.point); XCTAssertFalse(coordinator.canOpenEditor)
        await coordinator.load(); XCTAssertEqual(coordinator.point, reader.point); XCTAssertFalse(coordinator.canOpenEditor)
        coordinator.invalidate(); XCTAssertNil(coordinator.point); XCTAssertFalse(coordinator.canOpenEditor)
        XCTAssertEqual(reader.readCount, 2); XCTAssertEqual(reader.saveCount, 0)
    }
    func testOnlyBothPermissionsOfferExistingEditor() async throws {
        let reader = ReadOnlyPointReader(); reader.accessValue = try readOnlyAccess(["merchant:coop:manage", "merchant:profile:write"])
        let coordinator = MerchantNPCMapPointReadOnlyCoordinator(reader: reader); await coordinator.load()
        XCTAssertTrue(coordinator.canOpenEditor); XCTAssertEqual(reader.saveCount, 0)
        reader.accessValue = try readOnlyAccess(); await coordinator.load()
        XCTAssertFalse(coordinator.canOpenEditor); XCTAssertEqual(coordinator.point, reader.point)
    }
    func testProfileRevocationDuringReadKeepsReadOnlyVisibilityWithoutEditor() async throws {
        let reader = ReadOnlyPointReader(); reader.accessValue = try readOnlyAccess(["merchant:coop:manage", "merchant:profile:write"])
        reader.afterRead = { reader.accessValue = try! readOnlyAccess() }
        let coordinator = MerchantNPCMapPointReadOnlyCoordinator(reader: reader); await coordinator.load()
        XCTAssertEqual(coordinator.point, reader.point); XCTAssertFalse(coordinator.canOpenEditor)
        XCTAssertEqual(reader.accessCount, 2); XCTAssertEqual(reader.saveCount, 0)
    }
    func testCoopRevocationDuringReadDiscardsResultWithoutSaving() async throws {
        let reader = ReadOnlyPointReader(); reader.afterRead = { reader.accessValue = try! readOnlyAccess([]) }
        let coordinator = MerchantNPCMapPointReadOnlyCoordinator(reader: reader); await coordinator.load()
        XCTAssertNil(coordinator.point); XCTAssertNotNil(coordinator.issue); XCTAssertFalse(coordinator.canOpenEditor)
        XCTAssertEqual(reader.saveCount, 0)
    }
    func testForeignMerchantInReadOrLatestAccessDiscardsResult() async throws {
        for changeAccess in [false, true] {
            let reader = ReadOnlyPointReader()
            if changeAccess { reader.afterRead = { reader.accessValue = try! readOnlyAccess(merchantID: 99) } }
            else { reader.point = try JSONDecoder().decode(MerchantNPCMapPoint.self, from: Data(#"{"id":99}"#.utf8)) }
            let coordinator = MerchantNPCMapPointReadOnlyCoordinator(reader: reader); await coordinator.load()
            XCTAssertNil(coordinator.point); XCTAssertNotNil(coordinator.issue); XCTAssertFalse(coordinator.canOpenEditor)
            XCTAssertEqual(reader.saveCount, 0)
        }
    }
    func testSessionSwitchDuringReadDropsResultAndSkipsLaterAccessRead() async throws {
        let reader = ReadOnlyPointReader(); reader.afterRead = { reader.scope = UUID() }
        let coordinator = MerchantNPCMapPointReadOnlyCoordinator(reader: reader); await coordinator.load()
        XCTAssertNil(coordinator.point); XCTAssertFalse(coordinator.canOpenEditor); XCTAssertNil(coordinator.loadedScope)
        XCTAssertEqual(reader.accessCount, 1); XCTAssertEqual(reader.saveCount, 0)
    }
    func testLoadedPointImmediatelyDisappearsAfterSignOutOrScopeChange() async throws {
        let reader = ReadOnlyPointReader(); let coordinator = MerchantNPCMapPointReadOnlyCoordinator(reader: reader)
        await coordinator.load(); reader.isAuthenticated = false
        XCTAssertNil(coordinator.point); XCTAssertFalse(coordinator.canOpenEditor)
        reader.isAuthenticated = true; reader.scope = UUID()
        XCTAssertNil(coordinator.point); XCTAssertFalse(coordinator.canOpenEditor)
    }
    func testInvalidationDuringReadDiscardsLateResponse() async throws {
        let reader = ReadOnlyPointReader(); let coordinator = MerchantNPCMapPointReadOnlyCoordinator(reader: reader)
        reader.afterRead = { coordinator.invalidate() }; await coordinator.load()
        XCTAssertNil(coordinator.point); XCTAssertNil(coordinator.loadedScope); XCTAssertFalse(coordinator.isBusy)
        XCTAssertEqual(reader.saveCount, 0)
    }
    func testUnknownWriteCanBeReadButNeverClearedOrReopenedForEdit() async throws {
        let reader = ReadOnlyPointReader(); reader.accessValue = try readOnlyAccess(["merchant:coop:manage", "merchant:profile:write"])
        reader.pending = true
        let coordinator = MerchantNPCMapPointReadOnlyCoordinator(reader: reader); await coordinator.load()
        XCTAssertEqual(coordinator.point, reader.point); XCTAssertTrue(coordinator.hasPendingWrite); XCTAssertFalse(coordinator.canOpenEditor)
        await coordinator.load(); XCTAssertTrue(reader.pending); XCTAssertTrue(coordinator.hasPendingWrite)
        XCTAssertEqual(reader.saveCount, 0)
    }
    func testFailedReloadDoesNotKeepPreviouslySavedPoint() async throws {
        let reader = ReadOnlyPointReader(); let coordinator = MerchantNPCMapPointReadOnlyCoordinator(reader: reader)
        await coordinator.load(); reader.readFailure = true; await coordinator.load()
        XCTAssertNil(coordinator.point); XCTAssertNotNil(coordinator.issue); XCTAssertFalse(coordinator.canOpenEditor)
        XCTAssertEqual(reader.saveCount, 0)
    }
    func testMissingReadPermissionStopsBeforeDocumentRequest() async throws {
        let reader = ReadOnlyPointReader(); reader.accessValue = try readOnlyAccess([])
        let coordinator = MerchantNPCMapPointReadOnlyCoordinator(reader: reader); await coordinator.load()
        XCTAssertNil(coordinator.point); XCTAssertEqual(reader.readCount, 0); XCTAssertEqual(reader.saveCount, 0)
    }
}
