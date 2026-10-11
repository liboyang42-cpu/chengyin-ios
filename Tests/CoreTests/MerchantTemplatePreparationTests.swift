import Foundation
import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private func preparationTemplate(_ venue: String = "博物馆", materials: String = "Guide card") -> MerchantNodeTemplate {
    var value = MerchantNodeTemplate(); value.id = 71; value.title = "Preparation"; value.method = .photo
    value.usageLocation = venue; value.requiredMaterials = materials
    return value
}

final class MerchantTemplatePreparationContractTests: XCTestCase {
    func testVenueChoicesMatchMiniWireValuesWithoutDefaultingUnknowns() {
        XCTAssertEqual(MerchantTemplateVenueChoice.allCases.map(\.rawValue), ["景区", "公园绿地", "商圈街区", "古镇老街", "博物馆", "校园", "室内场馆"])
        XCTAssertNil(MerchantTemplateVenueChoice(rawValue: "Legacy venue"))
        XCTAssertNil(MerchantTemplateVenueChoice(rawValue: ""))
        XCTAssertEqual(MerchantTemplateVenueChoice.museum.titleKey, "merchant.preparation.venue.museum")
    }
    func testDecodeExistingOptionalStringsAndPreserveUnfamiliarVenue() throws {
        let value = try JSONDecoder().decode(MerchantNodeTemplate.self, from: Data(#"{"usageLocation":" Legacy venue ","requiredMaterials":"Map\nPen"}"#.utf8))
        XCTAssertEqual(value.usageLocation, " Legacy venue "); XCTAssertEqual(value.requiredMaterials, "Map\nPen")
        XCTAssertEqual(value.fields["usageLocation"] as? String, " Legacy venue ")
        for raw in ["{}", #"{"usageLocation":null,"requiredMaterials":null}"#] {
            let empty = try JSONDecoder().decode(MerchantNodeTemplate.self, from: Data(raw.utf8))
            XCTAssertEqual(empty.usageLocation, ""); XCTAssertEqual(empty.requiredMaterials, "")
        }
    }
    func testMalformedPreparationTypesNeverBecomeBlankSuccess() {
        for raw in [#"{"usageLocation":42}"#, #"{"requiredMaterials":[]}"#, #"{"requiredMaterials":true}"#] {
            XCTAssertThrowsError(try JSONDecoder().decode(MerchantNodeTemplate.self, from: Data(raw.utf8)))
        }
    }
    func testExactPayloadTrimsEdgesRetainsMaterialLinesAndPreservesRewardReference() throws {
        var value = preparationTemplate("室内场馆", materials: " Map\nPen "); value.couponID = 19
        let preview = try XCTUnwrap(MerchantOperationsDraft.template(value).previews().first)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: preview.json) as? [String: Any])
        XCTAssertEqual(preview.path, "api/merchant/city-node/template/submit")
        XCTAssertEqual(body["usageLocation"] as? String, "室内场馆")
        XCTAssertEqual(body["requiredMaterials"] as? String, "Map\nPen")
        XCTAssertEqual(body["couponId"] as? Int, 19)
        XCTAssertNil(body["address"]); XCTAssertNil(body["capacity"]); XCTAssertNil(body["merchantId"])
    }
    func testBlankValuesOmitKeysAndDoNotInventClearOperations() throws {
        let value = preparationTemplate(" \n", materials: " \t")
        XCTAssertNil(value.fields["usageLocation"]); XCTAssertNil(value.fields["requiredMaterials"])
        XCTAssertNil(value.fields["clearUsageLocation"]); XCTAssertNil(value.blocker)
        XCTAssertNoThrow(try MerchantOperationsDraft.template(value).previews())
    }
    func testAIResultsCannotSelectVenueOrReplaceMerchantMaterials() throws {
        let value = preparationTemplate()
        let result = try MerchantTemplateAssistResult(.object(["questionName": .string("Generated question"),
            "usageLocation": .string("校园"), "requiredMaterials": .string("Unverified equipment")]))
        let merged = result.merge(into: value, captured: value, edits: .init(), capturedEdits: .init())
        XCTAssertEqual(merged.usageLocation, value.usageLocation); XCTAssertEqual(merged.requiredMaterials, value.requiredMaterials)
        XCTAssertTrue(result.unsupportedKeys.contains("usageLocation")); XCTAssertTrue(result.unsupportedKeys.contains("requiredMaterials"))
    }
    func testLocalPlanningStillBlocksSendingPreparationFields() {
        var value = preparationTemplate(); var plan = MerchantTemplateExitPlan()
        plan.offlineAlternative = "Use a printed card"; plan.failureExit = "Leave through the public entrance"
        value.exitPlan = plan; XCTAssertNil(value.blocker)
        XCTAssertThrowsError(try MerchantOperationsDraft.template(value).previews()) {
            XCTAssertEqual($0 as? MerchantOperationsFailure, .liveWritesDisabled)
        }
    }
}

@MainActor final class MerchantTemplatePreparationFlowTests: XCTestCase {
    func testCancelReviewRetainsEditsAndDiscardRestoresSourcePreparation() async throws {
        let reader = MerchantOperationsFixtureReader(); let initial = preparationTemplate()
        reader.replace(.template(71), with: .draft(.template(initial)))
        let coordinator = MerchantOperationsCoordinator(reader: reader, destination: .template(71))
        await coordinator.load(); var draft = initial; draft.usageLocation = "公园绿地"; draft.requiredMaterials = "Map"
        coordinator.edit(.template(draft)); coordinator.prepare(); let review = try XCTUnwrap(coordinator.confirmation)
        coordinator.cancelConfirmation(); XCTAssertEqual(coordinator.draft, .template(draft)); XCTAssertTrue(coordinator.isDirty)
        draft.requiredMaterials = "New materials"; coordinator.edit(.template(draft)); XCTAssertNil(coordinator.confirmation)
        if case .template(let frozen) = review.draft { XCTAssertEqual(frozen.requiredMaterials, "Map") }
        else { XCTFail() }
        await coordinator.confirm(review); XCTAssertEqual(reader.saveCount, 0)
        coordinator.discardChanges(); XCTAssertEqual(coordinator.draft, .template(initial))
    }
    func testEmptyEditsReadBackExistingValuesInsteadOfClaimingDeletion() async throws {
        let reader = MerchantOperationsFixtureReader(); let initial = preparationTemplate()
        reader.replace(.template(71), with: .draft(.template(initial)))
        let coordinator = MerchantOperationsCoordinator(reader: reader, destination: .template(71))
        await coordinator.load(); var draft = initial; draft.usageLocation = ""; draft.requiredMaterials = " \n"
        coordinator.edit(.template(draft)); coordinator.prepare(); let review = try XCTUnwrap(coordinator.confirmation)
        await coordinator.confirm(review)
        XCTAssertEqual(reader.saveCount, 1); XCTAssertEqual(coordinator.draft, .template(initial)); XCTAssertFalse(coordinator.isDirty)
        await coordinator.confirm(review); XCTAssertEqual(reader.saveCount, 1)
    }
}

private final class PreparationTransport: HTTPTransport {
    var replies: [String] = [], requests: [URLRequest] = []
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); guard !replies.isEmpty else { throw APIError.malformedResponse }
        return (Data(replies.removeFirst().utf8), 200)
    }
}
@MainActor private final class PreparationJournal: OperationPendingJournal {
    var record: OperationPendingRecord?
    func pending(ownerKey: String, targetKey: String) throws -> OperationPendingRecord? { record }
    func write(_ record: OperationPendingRecord) throws { self.record = record }
    func clear(_ record: OperationPendingRecord) throws { self.record = nil }
}
@MainActor final class MerchantTemplatePreparationServiceTests: XCTestCase {
    func testApprovedSyntheticUpdateWritesExactPreparationKeysAndReadbackWins() async throws {
        let access = #"{"code":200,"data":{"active":true,"merchant":{"id":31},"roleCode":"MERCHANT_OWNER","permissions":["merchant:project:manage"]}}"#
        let initial = #"{"code":200,"data":{"id":71,"title":"Preparation","validationMethod":2,"usageLocation":"博物馆","requiredMaterials":"Old card"}}"#
        let returned = #"{"code":200,"data":{"id":71,"title":"Preparation","validationMethod":2,"usageLocation":"室内场馆","requiredMaterials":"Canonical materials"}}"#
        let transport = PreparationTransport()
        transport.replies = [access, initial, access, initial, access, initial, #"{"code":200,"data":71}"#, access, returned]
        let api = try APIConfiguration(baseURL: URL(string: "https://example.test/prod-api")!)
        let session = try MerchantOperationsSession(accountID: 7, epoch: 1, token: "synthetic-token", storageNamespace: "preparation-test")
        let approval = try OperationEndpointApproval(baseURL: api.baseURL, namespace: session.storageNamespace, accountID: session.accountID, paths: ["api/merchant/city-node/template/submit"])
        let journal = PreparationJournal()
        let reader = MerchantOperationsSessionReader(service: MerchantOperationsService(configuration: api, transport: transport), currentSession: { session }, approval: approval, journal: journal)
        let coordinator = MerchantOperationsCoordinator(reader: reader, destination: .template(71))
        await coordinator.load(); coordinator.edit(.template(preparationTemplate("公园绿地", materials: " Map\nPen "))); coordinator.prepare()
        let review = try XCTUnwrap(coordinator.confirmation); await coordinator.confirm(review)
        let saves = transport.requests.filter { $0.url?.path.hasSuffix("/template/submit") == true }
        XCTAssertEqual(saves.count, 1)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(saves.first?.httpBody)) as? [String: Any])
        XCTAssertEqual(payload["usageLocation"] as? String, "公园绿地"); XCTAssertEqual(payload["requiredMaterials"] as? String, "Map\nPen")
        guard case .template(let source) = coordinator.draft else { return XCTFail() }
        XCTAssertEqual(source.usageLocation, "室内场馆"); XCTAssertEqual(source.requiredMaterials, "Canonical materials")
        XCTAssertEqual(transport.requests.last?.url?.path, "/prod-api/api/template/myinfo")
        XCTAssertNil(journal.record); XCTAssertFalse(coordinator.isDirty)
        let count = transport.requests.count; await coordinator.confirm(review); XCTAssertEqual(transport.requests.count, count)
    }
}
