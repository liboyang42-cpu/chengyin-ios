import Foundation
import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private func npcCharacter(_ status: Int? = 1, name: String = "Lantern", reason: String? = nil) throws -> MerchantStoreCharacter {
    var object: [String: Any] = ["name": name, "avatar": "px1:p01", "greeting": "Welcome",
                               "persona": "Fictional shop guide", "knowledge": "Approved public shop facts", "enabled": 0]
    if let status { object["auditStatus"] = status }
    if let reason { object["auditReason"] = reason }
    return try JSONDecoder().decode(MerchantStoreCharacter.self, from: JSONSerialization.data(withJSONObject: object))
}

@MainActor private final class NPCCharacterReader: MerchantOperationsReading {
    var scope = UUID(), isConfigured = true, isAuthenticated = true, canSave = true
    var isOfflineExample = false
    var initial: MerchantOperationsDraft
    var returned: MerchantOperationsDocument
    var readFailure: Error?, saveFailure: Error?
    var readCount = 0, saveCount = 0
    var pending = false
    var onRead: ((Int) async -> Void)?
    init(initial: MerchantStoreCharacter, returned: MerchantStoreCharacter) {
        self.initial = .character(initial); self.returned = .draft(.character(returned))
    }
    func access() async throws -> MerchantOperationsAccess { throw APIError.notConfigured }
    func document(_ destination: MerchantOperationsDestination) async throws -> MerchantOperationsDocument {
        XCTAssertEqual(destination, .character)
        readCount += 1
        let number = readCount
        await onRead?(number)
        if number >= 3 {
            if let readFailure { throw readFailure }
            return returned
        }
        return .draft(initial)
    }
    func saveExample(_ draft: MerchantOperationsDraft) async throws { throw MerchantOperationsFailure.liveWritesDisabled }
    func saveReviewed(_ draft: MerchantOperationsDraft, baseline: MerchantOperationsDraft) async throws {
        saveCount += 1
        if let saveFailure { pending = true; throw saveFailure }
    }
    func hasPending(_ destination: MerchantOperationsDestination) -> Bool { pending }
}

@MainActor final class MerchantNPCCharacterReadbackTests: XCTestCase {
    private func reviewed(_ reader: NPCCharacterReader) async throws -> (MerchantOperationsCoordinator, MerchantOperationsConfirmation) {
        let coordinator = MerchantOperationsCoordinator(reader: reader, destination: .character)
        await coordinator.load()
        guard case .character(var character) = coordinator.draft else { throw APIError.malformedResponse }
        character.name = "  Edited lantern  "
        coordinator.edit(.character(character)); coordinator.prepare()
        return (coordinator, try XCTUnwrap(coordinator.confirmation))
    }
    func testAcknowledgmentUsesAuthoritativePendingProfileAndCanonicalText() async throws {
        let returned = try npcCharacter(0, name: "Edited lantern", reason: "Historical review reason")
        let reader = NPCCharacterReader(initial: try npcCharacter(1), returned: returned)
        let (coordinator, review) = try await reviewed(reader)
        await coordinator.confirm(review)
        XCTAssertEqual(reader.readCount, 3); XCTAssertEqual(reader.saveCount, 1)
        XCTAssertEqual(coordinator.baseline, .character(returned)); XCTAssertEqual(coordinator.draft, .character(returned))
        XCTAssertEqual(coordinator.document, .draft(.character(returned)))
        XCTAssertNil(returned.rejectionReason); XCTAssertEqual(returned.reviewKey, "merchant.operations.review.pending")
        XCTAssertEqual(coordinator.issue, .key("merchantNPCCharacter.readback"))
        XCTAssertFalse(coordinator.isDirty); XCTAssertFalse(coordinator.isLocked); XCTAssertFalse(coordinator.canReview)
        await coordinator.confirm(review)
        XCTAssertEqual(reader.saveCount, 1)
    }
    func testReadbackDoesNotInventPendingOrApprovalAndRemovesOldRejection() async throws {
        for status in [nil, 1, 99] as [Int?] {
            let returned = try npcCharacter(status, name: "Server profile")
            let reader = NPCCharacterReader(initial: try npcCharacter(2, reason: "Old rejection"), returned: returned)
            let (coordinator, review) = try await reviewed(reader)
            await coordinator.confirm(review)
            XCTAssertEqual(coordinator.draft, .character(returned))
            guard case .character(let loaded) = coordinator.draft else { return XCTFail() }
            XCTAssertEqual(loaded.auditStatus, status); XCTAssertNil(loaded.auditReason)
            XCTAssertNil(loaded.rejectionReason)
        }
    }
    func testReadbackFailureClearsOldAuditAndOnlyReloadsOnRetry() async throws {
        let returned = try npcCharacter(0, name: "Edited lantern")
        let reader = NPCCharacterReader(initial: try npcCharacter(2, reason: "Old rejection"), returned: returned)
        reader.readFailure = APIError.malformedResponse
        let (coordinator, review) = try await reviewed(reader)
        await coordinator.confirm(review)
        XCTAssertNil(coordinator.document); XCTAssertNil(coordinator.baseline); XCTAssertNil(coordinator.draft)
        XCTAssertNil(coordinator.confirmation); XCTAssertFalse(coordinator.isLocked); XCTAssertFalse(coordinator.isBusy)
        XCTAssertFalse(coordinator.canReview); XCTAssertFalse(coordinator.exampleSaved)
        XCTAssertEqual(coordinator.issue, .key("merchantNPCCharacter.readbackFailed"))
        await coordinator.confirm(review)
        reader.readFailure = nil
        await coordinator.load()
        XCTAssertEqual(coordinator.draft, .character(returned)); XCTAssertEqual(reader.saveCount, 1)
        XCTAssertEqual(reader.readCount, 4)
    }
    func testUnexpectedReadbackDocumentCannotBecomeCharacterBaseline() async throws {
        let reader = NPCCharacterReader(initial: try npcCharacter(), returned: try npcCharacter(0))
        reader.returned = .draft(.template(.init()))
        let (coordinator, review) = try await reviewed(reader)
        await coordinator.confirm(review)
        XCTAssertNil(coordinator.document); XCTAssertNil(coordinator.baseline); XCTAssertNil(coordinator.draft)
        XCTAssertEqual(coordinator.issue, .key("merchantNPCCharacter.readbackFailed"))
        XCTAssertFalse(coordinator.isLocked); XCTAssertEqual(reader.saveCount, 1)
    }
    func testAbsentOwnerProfileDoesNotRestoreTheSubmittedProfile() async throws {
        let reader = NPCCharacterReader(initial: try npcCharacter(), returned: .init())
        let (coordinator, review) = try await reviewed(reader)
        await coordinator.confirm(review)
        XCTAssertEqual(coordinator.draft, .character(.init()))
        XCTAssertFalse(coordinator.canReview); XCTAssertEqual(reader.saveCount, 1)
    }
    func testStaleFieldsAreGoneWhileReadbackIsInFlightAndRepeatedSaveIsIgnored() async throws {
        let reader = NPCCharacterReader(initial: try npcCharacter(1), returned: try npcCharacter(0))
        let (coordinator, review) = try await reviewed(reader)
        reader.onRead = { number in
            guard number == 3 else { return }
            XCTAssertNil(coordinator.document); XCTAssertNil(coordinator.baseline); XCTAssertNil(coordinator.draft)
            XCTAssertTrue(coordinator.isBusy); XCTAssertFalse(coordinator.isLocked)
            XCTAssertNil(coordinator.confirmation); XCTAssertFalse(coordinator.canReview)
            await coordinator.confirm(review)
        }
        await coordinator.confirm(review)
        XCTAssertEqual(reader.readCount, 3); XCTAssertEqual(reader.saveCount, 1)
    }
    func testAccountScopeChangeDuringReadbackDropsLateProfile() async throws {
        let reader = NPCCharacterReader(initial: try npcCharacter(), returned: try npcCharacter(0))
        let (coordinator, review) = try await reviewed(reader)
        reader.onRead = { number in if number == 3 { reader.scope = UUID() } }
        await coordinator.confirm(review)
        XCTAssertFalse(coordinator.isCurrent); XCTAssertNil(coordinator.document)
        XCTAssertNil(coordinator.baseline); XCTAssertNil(coordinator.draft); XCTAssertNil(coordinator.issue)
        XCTAssertEqual(reader.saveCount, 1)
    }
    func testSignOutDuringReadbackDropsLateProfile() async throws {
        let reader = NPCCharacterReader(initial: try npcCharacter(), returned: try npcCharacter(0))
        let (coordinator, review) = try await reviewed(reader)
        reader.onRead = { number in if number == 3 { reader.isAuthenticated = false } }
        await coordinator.confirm(review)
        XCTAssertFalse(coordinator.isCurrent); XCTAssertNil(coordinator.document); XCTAssertNil(coordinator.draft)
        XCTAssertNil(coordinator.issue); XCTAssertEqual(reader.saveCount, 1)
    }
    func testLeaveDuringReadbackDropsLateProfile() async throws {
        let reader = NPCCharacterReader(initial: try npcCharacter(), returned: try npcCharacter(0))
        let (coordinator, review) = try await reviewed(reader)
        reader.onRead = { number in if number == 3 { coordinator.leaveScreen() } }
        await coordinator.confirm(review)
        XCTAssertNil(coordinator.loadedScope); XCTAssertNil(coordinator.document); XCTAssertNil(coordinator.draft)
        XCTAssertNil(coordinator.issue); XCTAssertFalse(coordinator.isBusy); XCTAssertEqual(reader.saveCount, 1)
    }
    func testUnknownWriteNeverEntersPostSaveReadbackOrUnlocksOnReload() async throws {
        let reader = NPCCharacterReader(initial: try npcCharacter(), returned: try npcCharacter(0))
        reader.saveFailure = MerchantOperationsFailure.outcomeUnknown
        let (coordinator, review) = try await reviewed(reader)
        await coordinator.confirm(review)
        XCTAssertEqual(reader.readCount, 2); XCTAssertEqual(reader.saveCount, 1)
        XCTAssertTrue(coordinator.isLocked); XCTAssertEqual(coordinator.issue, .key("merchant.operations.unknownOutcome"))
        await coordinator.load()
        XCTAssertTrue(coordinator.isLocked); XCTAssertFalse(coordinator.canReview)
        await coordinator.confirm(review)
        XCTAssertEqual(reader.saveCount, 1)
    }
    func testRejectedWriteDoesNotUseSuccessReadback() async throws {
        let reader = NPCCharacterReader(initial: try npcCharacter(), returned: try npcCharacter(0))
        reader.saveFailure = MerchantOperationsFailure.rejected(code: 403, message: "Revoked")
        let (coordinator, review) = try await reviewed(reader)
        await coordinator.confirm(review)
        XCTAssertEqual(reader.readCount, 2); XCTAssertEqual(reader.saveCount, 1)
        XCTAssertFalse(coordinator.isLocked)
        XCTAssertEqual(coordinator.issue, .server("Revoked"))
    }
}

private final class NPCCharacterTransport: HTTPTransport {
    var replies: [String] = []
    var requests: [URLRequest] = []
    var onSend: ((Int) -> Void)?
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); onSend?(requests.count)
        guard !replies.isEmpty else { throw APIError.malformedResponse }
        return (Data(replies.removeFirst().utf8), 200)
    }
}
@MainActor private final class NPCCharacterJournal: OperationPendingJournal {
    var record: OperationPendingRecord?
    var clears = 0
    func pending(ownerKey: String, targetKey: String) throws -> OperationPendingRecord? { record }
    func write(_ record: OperationPendingRecord) throws { self.record = record }
    func clear(_ record: OperationPendingRecord) throws { self.record = nil; clears += 1 }
}

@MainActor final class MerchantNPCCharacterReadbackServiceTests: XCTestCase {
    private let baseURL = URL(string: "https://example.test/api-root")!
    private let access = #"{"code":200,"data":{"active":true,"merchant":{"id":31},"roleCode":"MERCHANT_OWNER","permissions":["merchant:profile:write"]}}"#
    private let profile = #"{"code":200,"data":{"scopeType":2,"scopeId":31,"name":"Lantern","avatar":"px1:p01","persona":"Shop guide","knowledge":"Public facts","auditStatus":1,"enabled":0}}"#
    private let pending = #"{"code":200,"data":{"scopeType":2,"scopeId":31,"name":"Edited","avatar":"px1:p01","persona":"Shop guide","knowledge":"Public facts","auditStatus":0,"enabled":0}}"#
    private func session(_ epoch: UInt64 = 1) throws -> MerchantOperationsSession {
        try .init(accountID: 7, epoch: epoch, token: "synthetic-token", storageNamespace: "synthetic", viewerRevision: epoch)
    }
    private func reader(_ transport: NPCCharacterTransport, _ journal: NPCCharacterJournal,
                        current: @escaping () -> MerchantOperationsSession?) throws -> MerchantOperationsSessionReader {
        let service = MerchantOperationsService(configuration: try .init(baseURL: baseURL), transport: transport)
        let approval = try OperationEndpointApproval(baseURL: baseURL, namespace: "synthetic", accountID: 7, paths: ["api/merchant/npc/save"])
        return .init(service: service, currentSession: current, approval: approval, journal: journal)
    }
    private func reviewed(_ reader: MerchantOperationsSessionReader) async throws -> (MerchantOperationsCoordinator, MerchantOperationsConfirmation) {
        let coordinator = MerchantOperationsCoordinator(reader: reader, destination: .character)
        await coordinator.load()
        guard case .character(var value) = coordinator.draft else { throw APIError.malformedResponse }
        value.name = "Edited"; coordinator.edit(.character(value)); coordinator.prepare()
        return (coordinator, try XCTUnwrap(coordinator.confirmation))
    }
    func testRealReaderRefreshesOwnerAccessAndProfileAfterExactlyOneSave() async throws {
        let transport = NPCCharacterTransport(), journal = NPCCharacterJournal(), current = try session()
        transport.replies = [access, profile, access, profile, access, profile, #"{"code":200}"#, access, pending]
        let (coordinator, review) = try await reviewed(reader(transport, journal, current: { current }))
        await coordinator.confirm(review)
        XCTAssertEqual(transport.requests.map { $0.url!.path }, [
            "/api-root/api/merchant/access/me", "/api-root/api/merchant/npc/profile",
            "/api-root/api/merchant/access/me", "/api-root/api/merchant/npc/profile",
            "/api-root/api/merchant/access/me", "/api-root/api/merchant/npc/profile",
            "/api-root/api/merchant/npc/save", "/api-root/api/merchant/access/me", "/api-root/api/merchant/npc/profile"])
        let save = transport.requests[6]
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(save.httpBody)) as? [String: Any])
        XCTAssertEqual(Set(fields.keys), ["name", "avatar", "greeting", "persona", "knowledge"])
        XCTAssertEqual(transport.requests[8].httpBody, Data("{}".utf8))
        guard case .character(let value) = coordinator.draft else { return XCTFail() }
        XCTAssertEqual(value.auditStatus, 0); XCTAssertEqual(value.enabled, 0)
        XCTAssertNil(journal.record); XCTAssertEqual(journal.clears, 1)
    }
    func testRevokedPostSaveAccessClearsDataWithoutRelockingAcknowledgedWrite() async throws {
        let transport = NPCCharacterTransport(), journal = NPCCharacterJournal(), current = try session()
        transport.replies = [access, profile, access, profile, access, profile, #"{"code":200}"#,
                             #"{"code":200,"data":{"active":false,"permissions":[]}}"#]
        let (coordinator, review) = try await reviewed(reader(transport, journal, current: { current }))
        await coordinator.confirm(review)
        XCTAssertEqual(transport.requests.count, 8)
        XCTAssertNil(coordinator.document); XCTAssertNil(coordinator.draft); XCTAssertNil(coordinator.baseline)
        XCTAssertFalse(coordinator.isLocked); XCTAssertNil(journal.record)
        XCTAssertEqual(coordinator.issue, .key("merchantNPCCharacter.readbackFailed"))
    }
    func testOwnerRevisionChangeDuringReadbackCannotInstallLateData() async throws {
        let transport = NPCCharacterTransport(), journal = NPCCharacterJournal()
        var current: MerchantOperationsSession? = try session()
        let replacement = try session(2)
        transport.replies = [access, profile, access, profile, access, profile, #"{"code":200}"#, access, pending]
        let (coordinator, review) = try await reviewed(reader(transport, journal, current: { current }))
        transport.onSend = { number in if number == 9 { current = replacement } }
        await coordinator.confirm(review)
        XCTAssertFalse(coordinator.isCurrent); XCTAssertNil(coordinator.document); XCTAssertNil(coordinator.draft)
        XCTAssertNil(coordinator.issue); XCTAssertNil(journal.record)
        XCTAssertEqual(transport.requests.filter { $0.url?.lastPathComponent == "save" }.count, 1)
    }
    func testAmbiguousSaveKeepsDurableJournalAndNeverRunsReadback() async throws {
        let transport = NPCCharacterTransport(), journal = NPCCharacterJournal(), current = try session()
        transport.replies = [access, profile, access, profile, access, profile, #"{"unexpected":"response"}"#]
        let (coordinator, review) = try await reviewed(reader(transport, journal, current: { current }))
        await coordinator.confirm(review)
        XCTAssertEqual(transport.requests.count, 7); XCTAssertNotNil(journal.record); XCTAssertEqual(journal.clears, 0)
        XCTAssertTrue(coordinator.isLocked); XCTAssertEqual(coordinator.issue, .key("merchant.operations.unknownOutcome"))
    }
}
