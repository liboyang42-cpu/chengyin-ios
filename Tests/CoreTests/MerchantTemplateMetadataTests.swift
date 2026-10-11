import Foundation
import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private func metadataTemplate(_ id: Int? = 71, duration: String = "15", players: String = "2–6") -> MerchantNodeTemplate {
    var value = MerchantNodeTemplate(); value.id = id; value.title = "Template"; value.method = .photo
    value.gameDurationMinutes = duration; value.players = players
    return value
}

final class MerchantTemplateMetadataContractTests: XCTestCase {
    func testDecodeExactServerMetadataAndAbsenceWithoutCapacityInference() throws {
        for duration in ["15", "\"15\"", "0", "2147483647"] {
            let value = try JSONDecoder().decode(MerchantNodeTemplate.self, from: Data("{\"duration\":\(duration),\"players\":\"2–6\"}".utf8))
            XCTAssertEqual(value.players, "2–6"); XCTAssertNotNil(MerchantNodeTemplate.validDuration(value.gameDurationMinutes))
            XCTAssertNil(value.participationPlan); XCTAssertNil(value.exitPlan)
        }
        let missing = try JSONDecoder().decode(MerchantNodeTemplate.self, from: Data(#"{"duration":null,"players":null}"#.utf8))
        XCTAssertEqual(missing.gameDurationMinutes, ""); XCTAssertEqual(missing.players, "")
    }
    func testRejectMalformedOutOfRangeOrNegativeDurationReadback() {
        for duration in ["-1", "2147483648", "1.5", "true", "{}", "\"1e2\"", "\"\"", "\"+1\""] {
            XCTAssertThrowsError(try JSONDecoder().decode(MerchantNodeTemplate.self, from: Data("{\"duration\":\(duration)}".utf8)), duration)
        }
        XCTAssertThrowsError(try JSONDecoder().decode(MerchantNodeTemplate.self, from: Data(#"{"players":12}"#.utf8)))
    }
    func testWireUsesIntegerMinutesAndOrdinaryPlayersString() throws {
        var value = metadataTemplate(duration: " 0025 ", players: " 2–6 ")
        let request = try XCTUnwrap(MerchantOperationsDraft.template(value).previews().first)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: request.json) as? [String: Any])
        XCTAssertEqual(request.path, "api/merchant/city-node/template/submit")
        XCTAssertEqual(object["duration"] as? Int, 25); XCTAssertNil(object["duration"] as? String)
        XCTAssertEqual(object["players"] as? String, "2–6"); XCTAssertNil(object["maximumParticipants"])
        for invalid in ["-1", "+1", "1.5", "1e2", "2147483648", "１２"] {
            value.gameDurationMinutes = invalid
            XCTAssertEqual(value.blocker, "merchant.templateMetadata.durationInvalid")
            XCTAssertThrowsError(try MerchantOperationsDraft.template(value).previews())
        }
        value.gameDurationMinutes = "0"; XCTAssertNil(value.blocker)
    }
    func testBlankFieldsAreOmittedAndLocalGroupsRemainNonSubmittable() throws {
        var value = metadataTemplate(duration: " \n", players: " ")
        XCTAssertNil(value.fields["duration"]); XCTAssertNil(value.fields["players"])
        XCTAssertNil(value.blocker)
        var plan = MerchantTemplateParticipationPlan()
        plan.durationMinutes = "30"; plan.maximumParticipants = "8"; plan.staffing = .selfGuided
        value.participationPlan = plan
        XCTAssertNil(value.fields["duration"]); XCTAssertNil(value.fields["players"])
        XCTAssertThrowsError(try MerchantOperationsDraft.template(value).previews())
        value.participationPlan = nil; var exit = MerchantTemplateExitPlan()
        exit.offlineAlternative = "Ask the host"; exit.failureExit = "Use the public exit"; value.exitPlan = exit
        XCTAssertThrowsError(try MerchantOperationsDraft.template(value).previews())
    }
    func testAICannotSupplyOrReplaceTemplateMetadata() throws {
        let value = metadataTemplate()
        let result = try MerchantTemplateAssistResult(.object(["questionName": .string("Question"), "duration": .number(999), "players": .string("999")]))
        let merged = result.merge(into: value, captured: value, edits: .init(), capturedEdits: .init())
        XCTAssertEqual(merged.gameDurationMinutes, "15"); XCTAssertEqual(merged.players, "2–6")
        XCTAssertTrue(result.unsupportedKeys.contains("duration")); XCTAssertTrue(result.unsupportedKeys.contains("players"))
    }
}

@MainActor private final class MetadataReader: MerchantOperationsReading {
    var scope = UUID(), isConfigured = true, isAuthenticated = true, canSave = true
    let isOfflineExample = false
    var initial: MerchantNodeTemplate, returned: MerchantNodeTemplate
    var acknowledgedID: Int? = 71
    var destinations: [MerchantOperationsDestination] = []
    var saves = 0
    var readFailure: Error?, saveFailure: Error?
    var onReadback: (() -> Void)?
    init(initial: MerchantNodeTemplate = metadataTemplate(), returned: MerchantNodeTemplate = metadataTemplate(duration: "30", players: "4–8")) {
        self.initial = initial; self.returned = returned
    }
    func access() async throws -> MerchantOperationsAccess { throw APIError.notConfigured }
    func document(_ destination: MerchantOperationsDestination) async throws -> MerchantOperationsDocument {
        destinations.append(destination)
        if saves > 0 {
            onReadback?()
            if let readFailure { throw readFailure }
            return .draft(.template(returned))
        }
        return .draft(.template(initial))
    }
    func saveExample(_ draft: MerchantOperationsDraft) async throws { throw MerchantOperationsFailure.liveWritesDisabled }
    func saveTemplateReviewed(_ draft: MerchantNodeTemplate, baseline: MerchantNodeTemplate) async throws -> Int? {
        saves += 1
        if let saveFailure { throw saveFailure }
        return acknowledgedID
    }
}

@MainActor final class MerchantTemplateMetadataReadbackTests: XCTestCase {
    private func reviewed(_ reader: MetadataReader) async throws -> (MerchantOperationsCoordinator, MerchantOperationsConfirmation) {
        let coordinator = MerchantOperationsCoordinator(reader: reader, destination: .template(reader.initial.id))
        await coordinator.load(); var value = reader.initial; value.gameDurationMinutes = "25"; value.players = "2–4"
        coordinator.edit(.template(value)); coordinator.prepare()
        return (coordinator, try XCTUnwrap(coordinator.confirmation))
    }
    func testAcknowledgedUpdateUsesOnlyReturnedServerFields() async throws {
        let reader = MetadataReader(); let (coordinator, review) = try await reviewed(reader)
        await coordinator.confirm(review)
        XCTAssertEqual(reader.saves, 1); XCTAssertEqual(reader.destinations, [.template(71), .template(71), .template(71)])
        XCTAssertEqual(coordinator.baseline, .template(reader.returned)); XCTAssertEqual(coordinator.draft, .template(reader.returned))
        XCTAssertEqual(coordinator.issue, .key("merchant.templateMetadata.readback")); XCTAssertFalse(coordinator.isDirty)
        await coordinator.confirm(review); XCTAssertEqual(reader.saves, 1)
    }
    func testNewAcknowledgedIDBecomesReadbackAndNextEditDestination() async throws {
        let reader = MetadataReader(initial: metadataTemplate(nil), returned: metadataTemplate(88, duration: "30"))
        reader.acknowledgedID = 88
        let (coordinator, review) = try await reviewed(reader); await coordinator.confirm(review)
        XCTAssertEqual(reader.destinations, [.template(nil), .template(nil), .template(88)])
        XCTAssertEqual(coordinator.destination, .template(88)); XCTAssertEqual(coordinator.draft, .template(reader.returned))
        var next = reader.returned; next.players = "3–6"; coordinator.edit(.template(next))
        XCTAssertEqual(coordinator.draft, .template(next)); XCTAssertTrue(coordinator.canReview)
    }
    func testReadbackFailureClearsSubmittedCopyAndReloadNeverResends() async throws {
        let reader = MetadataReader(); reader.readFailure = APIError.malformedResponse
        let (coordinator, review) = try await reviewed(reader); await coordinator.confirm(review)
        XCTAssertNil(coordinator.document); XCTAssertNil(coordinator.draft); XCTAssertNil(coordinator.baseline)
        XCTAssertFalse(coordinator.isLocked); XCTAssertFalse(coordinator.isBusy); XCTAssertFalse(coordinator.canReview)
        XCTAssertEqual(coordinator.issue, .key("merchant.templateMetadata.readbackFailed"))
        await coordinator.confirm(review); XCTAssertEqual(reader.saves, 1)
        reader.readFailure = nil; await coordinator.load()
        XCTAssertEqual(reader.saves, 1); XCTAssertEqual(coordinator.draft, .template(reader.returned))
    }
    func testMismatchedAcknowledgmentOrReturnedIDCannotBecomeBaseline() async throws {
        let wrongAck = MetadataReader(); wrongAck.acknowledgedID = 99
        let (first, review) = try await reviewed(wrongAck); await first.confirm(review)
        XCTAssertEqual(wrongAck.destinations.count, 2); XCTAssertEqual(first.destination, .template(71)); XCTAssertNil(first.draft)
        let wrongReadback = MetadataReader(returned: metadataTemplate(99))
        let (second, secondReview) = try await reviewed(wrongReadback); await second.confirm(secondReview)
        XCTAssertNil(second.draft); XCTAssertNil(second.baseline)
        XCTAssertEqual(second.issue, .key("merchant.templateMetadata.readbackFailed"))
    }
    func testUnknownSaveStaysLockedAndNeverStartsReadbackOrRetries() async throws {
        let reader = MetadataReader(); reader.saveFailure = MerchantOperationsFailure.outcomeUnknown
        let (coordinator, review) = try await reviewed(reader); await coordinator.confirm(review)
        XCTAssertTrue(coordinator.isLocked); XCTAssertEqual(reader.destinations.count, 2)
        XCTAssertEqual(coordinator.draft, review.draft)
        await coordinator.confirm(review); XCTAssertEqual(reader.saves, 1)
    }
    func testChangedSessionDuringReadbackCannotPromoteResult() async throws {
        let reader = MetadataReader()
        reader.onReadback = { reader.scope = UUID(); reader.isAuthenticated = false }
        let (coordinator, review) = try await reviewed(reader); await coordinator.confirm(review)
        XCTAssertNil(coordinator.draft); XCTAssertNil(coordinator.baseline); XCTAssertFalse(coordinator.isCurrent)
    }
}

private final class MetadataTransport: HTTPTransport {
    var replies: [String] = [], requests: [URLRequest] = []
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        guard !replies.isEmpty else { throw APIError.malformedResponse }
        return (Data(replies.removeFirst().utf8), 200)
    }
}
@MainActor private final class MetadataJournal: OperationPendingJournal {
    var record: OperationPendingRecord?
    func pending(ownerKey: String, targetKey: String) throws -> OperationPendingRecord? { record }
    func write(_ record: OperationPendingRecord) throws { self.record = record }
    func clear(_ record: OperationPendingRecord) throws { self.record = nil }
}
@MainActor final class MerchantTemplateMetadataServiceTests: XCTestCase {
    func testApprovedSyntheticCreateCarriesMetadataAndReadsExactAcknowledgedID() async throws {
        let access = #"{"code":200,"data":{"active":true,"merchant":{"id":31},"roleCode":"MERCHANT_OWNER","permissions":["merchant:project:manage"]}}"#
        let transport = MetadataTransport()
        transport.replies = [access, access, access, #"{"code":200,"data":88}"#, access,
            #"{"code":200,"data":{"id":88,"title":"Server title","validationMethod":2,"duration":30,"players":"4–8"}}"#]
        let api = try APIConfiguration(baseURL: URL(string: "https://example.test/prod-api")!)
        let session = try MerchantOperationsSession(accountID: 7, epoch: 1, token: "synthetic-token", storageNamespace: "metadata-test")
        let approval = try OperationEndpointApproval(baseURL: api.baseURL, namespace: session.storageNamespace, accountID: session.accountID, paths: ["api/merchant/city-node/template/submit"])
        let journal = MetadataJournal()
        let reader = MerchantOperationsSessionReader(service: MerchantOperationsService(configuration: api, transport: transport), currentSession: { session }, approval: approval, journal: journal)
        let coordinator = MerchantOperationsCoordinator(reader: reader, destination: .template(nil))
        await coordinator.load(); coordinator.edit(.template(metadataTemplate(nil, duration: "25", players: "2–4"))); coordinator.prepare()
        let review = try XCTUnwrap(coordinator.confirmation); await coordinator.confirm(review)
        XCTAssertEqual(coordinator.destination, .template(88)); XCTAssertFalse(coordinator.isLocked); XCTAssertNil(journal.record)
        let saves = transport.requests.filter { $0.url?.path.hasSuffix("/template/submit") == true }
        XCTAssertEqual(saves.count, 1)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(saves.first?.httpBody)) as? [String: Any])
        XCTAssertEqual(payload["duration"] as? Int, 25); XCTAssertEqual(payload["players"] as? String, "2–4")
        let detail = try XCTUnwrap(transport.requests.last)
        XCTAssertEqual(detail.url?.path, "/prod-api/api/template/myinfo")
        XCTAssertTrue(String(decoding: try XCTUnwrap(detail.httpBody), as: UTF8.self).contains("name=\"id\"\r\n\r\n88\r\n"))
        guard case .template(let returned) = coordinator.draft else { return XCTFail() }
        XCTAssertEqual(returned.gameDurationMinutes, "30"); XCTAssertEqual(returned.players, "4–8")
        let count = transport.requests.count; await coordinator.confirm(review); XCTAssertEqual(transport.requests.count, count)
    }
    func testDefaultOffReaderCannotDispatchTemplateSave() async throws {
        let transport = MetadataTransport()
        let api = try APIConfiguration(baseURL: URL(string: "https://example.test/prod-api")!)
        let session = try MerchantOperationsSession(accountID: 7, epoch: 1, token: "synthetic-token")
        let reader = MerchantOperationsSessionReader(service: MerchantOperationsService(configuration: api, transport: transport), currentSession: { session })
        do { _ = try await reader.saveTemplateReviewed(metadataTemplate(), baseline: metadataTemplate()); XCTFail() }
        catch { XCTAssertEqual(error as? MerchantOperationsFailure, .liveWritesDisabled) }
        XCTAssertTrue(transport.requests.isEmpty)
    }
}
