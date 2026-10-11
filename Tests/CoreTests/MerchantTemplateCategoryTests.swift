import Foundation
import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private let categoryJSON = #"[{"id":101,"categoryName":"Observation","type":4},{"id":102,"categoryName":"Puzzle","type":4}]"#
private func catalog(_ raw: String = categoryJSON) throws -> MerchantTemplateCategoryCatalog {
    try JSONDecoder().decode(MerchantTemplateCategoryCatalog.self, from: Data(raw.utf8))
}
private func categoryTemplate(raw: String? = "101", primary: Int? = 101) throws -> MerchantNodeTemplate {
    var value = MerchantNodeTemplate(); value.id = 71; value.title = "Categories"; value.method = .photo
    value.categories = .init(rawIDs: raw, primaryID: primary, labels: try catalog().rows)
    return value
}

final class MerchantTemplateCategoryContractTests: XCTestCase {
    func testExactCatalogAcceptsEmptyAndRejectsMalformedDuplicateOrWrongType() throws {
        XCTAssertEqual(try catalog().rows.map(\.id), [101, 102]); XCTAssertTrue(try catalog("[]").rows.isEmpty)
        for raw in ["null", "{}", #"[{"id":0,"categoryName":"A"}]"#, #"[{"id":101,"categoryName":""}]"#,
                    #"[{"id":101,"categoryName":"A","type":2}]"#,
                    #"[{"id":101,"categoryName":"A"},{"id":101,"categoryName":"B"}]"#,
                    #"[{"id":9007199254740992,"categoryName":"A"}]"#] {
            XCTAssertThrowsError(try catalog(raw))
        }
    }
    func testSourceFieldsAndLabelsDecodeButNamesAreNeverSent() throws {
        let raw = #"{"categoryId":101,"activityCategoryids":"101,102","sysCategoryList":[{"id":101,"categoryName":"Source name","type":4}]}"#
        let value = try JSONDecoder().decode(MerchantNodeTemplate.self, from: Data(raw.utf8))
        XCTAssertEqual(value.categories.name(101), "Source name"); XCTAssertEqual(value.categories.selectedIDs, [101, 102])
        XCTAssertEqual(value.fields["categoryId"] as? Int, 101); XCTAssertEqual(value.fields["activityCategoryids"] as? String, "101,102")
        XCTAssertNil(value.fields["sysCategoryList"]); XCTAssertNil(value.fields["categoryIds"])
    }
    func testMissingNullFieldsRemainOmittedAndMalformedOuterTypesFail() throws {
        for raw in ["{}", #"{"categoryId":null,"activityCategoryids":null,"sysCategoryList":null}"#] {
            let value = try JSONDecoder().decode(MerchantNodeTemplate.self, from: Data(raw.utf8))
            XCTAssertTrue(value.categories.fields.isEmpty); XCTAssertEqual(value.categories, MerchantTemplateCategories())
        }
        for raw in [#"{"categoryId":[]}"#, #"{"categoryId":"bad"}"#, #"{"activityCategoryids":[]}"#, #"{"sysCategoryList":{}}"#] {
            XCTAssertThrowsError(try JSONDecoder().decode(MerchantNodeTemplate.self, from: Data(raw.utf8)))
        }
    }
    func testNoOpSelectionKeepsExactRawCSVAndExistingPrimary() throws {
        var value = MerchantTemplateCategories(rawIDs: "101, 102", primaryID: 999)
        let before = value; try value.replace(with: catalog().rows)
        XCTAssertEqual(value, before); XCTAssertEqual(value.fields["activityCategoryids"] as? String, "101, 102")
        XCTAssertEqual(value.primaryID, 999)
    }
    func testChangedSelectionSynchronizesFirstIDWithPrimaryAndKeepsOrder() throws {
        var value = MerchantTemplateCategories(rawIDs: "101", primaryID: 101)
        try value.replace(with: Array(catalog().rows.reversed()))
        XCTAssertEqual(value.rawIDs, "102,101"); XCTAssertEqual(value.primaryID, 102)
        XCTAssertEqual(value.labels.map(\.id), [102, 101])
        XCTAssertThrowsError(try value.replace(with: []))
    }
    func testUnsupportedCSVIsPreservedUntilExplicitReplacement() throws {
        for raw in ["1,,2", "01", "101,101", "-1", "bad", "9007199254740992"] {
            var value = MerchantTemplateCategories(rawIDs: raw, primaryID: 101)
            XCTAssertFalse(value.isSupported); XCTAssertEqual(value.fields["activityCategoryids"] as? String, raw)
            try value.replace(with: [catalog().rows[1]])
            XCTAssertEqual(value.rawIDs, "102"); XCTAssertTrue(value.replacedUnsupportedSource)
        }
    }
    func testExactWritePayloadUsesExistingTwoFieldsAndRetainsRewardReference() throws {
        var value = try categoryTemplate(); value.couponID = 19; try value.categories.replace(with: [catalog().rows[1]])
        let preview = try XCTUnwrap(MerchantOperationsDraft.template(value).previews().first)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: preview.json) as? [String: Any])
        XCTAssertEqual(preview.path, "api/merchant/city-node/template/submit")
        XCTAssertEqual(body["activityCategoryids"] as? String, "102"); XCTAssertEqual(body["categoryId"] as? Int, 102)
        XCTAssertEqual(body["couponId"] as? Int, 19); XCTAssertNil(body["categoryIds"])
    }
    func testAIAndLocalPlanBoundariesAreUnchanged() throws {
        var value = try categoryTemplate()
        let result = try MerchantTemplateAssistResult(.object(["questionName": .string("Question"), "activityCategoryids": .string("999"), "categoryId": .number(999)]))
        let merged = result.merge(into: value, captured: value, edits: .init(), capturedEdits: .init())
        XCTAssertEqual(merged.categories, value.categories)
        var plan = MerchantTemplateExitPlan(); plan.offlineAlternative = "Card"; plan.failureExit = "Leave"
        value.exitPlan = plan
        XCTAssertThrowsError(try MerchantOperationsDraft.template(value).previews()) {
            XCTAssertEqual($0 as? MerchantOperationsFailure, .liveWritesDisabled)
        }
    }
}

@MainActor private final class CategoryReader: MerchantOperationsReading {
    let fixture = MerchantOperationsFixtureReader()
    var isConfigured: Bool { true }
    var isAuthenticated: Bool { fixture.isAuthenticated }
    var isOfflineExample: Bool { true }
    var scope: UUID { fixture.scope }
    var supplied = try! catalog()
    var failure: APIError?
    var calls = 0
    var suspend = false
    var pending: [CheckedContinuation<MerchantTemplateCategoryCatalog, Error>] = []
    func access() async throws -> MerchantOperationsAccess { try await fixture.access() }
    func document(_ destination: MerchantOperationsDestination) async throws -> MerchantOperationsDocument { try await fixture.document(destination) }
    func saveExample(_ draft: MerchantOperationsDraft) async throws { try await fixture.saveExample(draft) }
    func templateCategories() async throws -> MerchantTemplateCategoryCatalog {
        calls += 1
        if let failure { throw failure }
        if suspend { return try await withCheckedThrowingContinuation { pending.append($0) } }
        return supplied
    }
}
@MainActor final class MerchantTemplateCategorySelectionTests: XCTestCase {
    private func setup(raw: String? = "101", primary: Int? = 101) async throws -> (CategoryReader, MerchantOperationsCoordinator, MerchantTemplateCategorySelection) {
        let reader = CategoryReader(); reader.fixture.replace(.template(71), with: .draft(.template(try categoryTemplate(raw: raw, primary: primary))))
        let owner = MerchantOperationsCoordinator(reader: reader, destination: .template(71)); await owner.load()
        return (reader, owner, try XCTUnwrap(MerchantTemplateCategorySelection(owner: owner)))
    }
    func testLoadToggleCancelDoesNotEditOrSave() async throws {
        let (reader, owner, flow) = try await setup(); let original = owner.draft
        await flow.reload(); flow.toggle(102); XCTAssertEqual(flow.selectedIDs, [101, 102]); XCTAssertTrue(flow.canApply)
        XCTAssertEqual(owner.draft, original); flow.cancel(); XCTAssertNil(flow.apply())
        XCTAssertEqual(owner.draft, original); XCTAssertEqual(reader.fixture.saveCount, 0)
    }
    func testApplyReturnsOnlyChosenCatalogIDsAndIsSingleUse() async throws {
        let (reader, owner, flow) = try await setup(); await flow.reload()
        flow.toggle(999); XCTAssertEqual(flow.selectedIDs, [101])
        flow.toggle(101); XCTAssertFalse(flow.canApply); flow.toggle(102)
        let edited = try XCTUnwrap(flow.apply()); XCTAssertEqual(edited.categories.primaryID, 102)
        XCTAssertEqual(edited.categories.rawIDs, "102"); XCTAssertNil(flow.apply())
        XCTAssertEqual(reader.fixture.saveCount, 0); owner.edit(.template(edited)); XCTAssertTrue(owner.isDirty)
    }
    func testMalformedSelectionRequiresExplicitReplacement() async throws {
        let (_, owner, flow) = try await setup(raw: "101,,102"); let original = owner.draft
        await flow.reload(); flow.toggle(102); XCTAssertTrue(flow.needsReplacement); XCTAssertFalse(flow.canApply)
        flow.beginReplacement(); flow.toggle(102)
        let edited = try XCTUnwrap(flow.apply()); XCTAssertTrue(edited.categories.replacedUnsupportedSource)
        XCTAssertEqual(owner.draft, original)
    }
    func testUnavailableSavedIDsAreNeverSilentlyDropped() async throws {
        let (_, _, flow) = try await setup(raw: "101,999"); await flow.reload()
        XCTAssertEqual(flow.unavailableIDs, [999]); XCTAssertEqual(flow.selectedIDs, [101, 999]); XCTAssertFalse(flow.canApply)
        flow.removeUnavailable(101); XCTAssertEqual(flow.selectedIDs, [101, 999])
        flow.removeUnavailable(999); XCTAssertTrue(flow.canApply)
        XCTAssertEqual(try XCTUnwrap(flow.apply()).categories.rawIDs, "101")
    }
    func testErrorRetryAndGenuineEmptyCatalogRemainDistinct() async throws {
        let (reader, _, flow) = try await setup(); reader.failure = .malformedResponse
        await flow.reload(); XCTAssertNotNil(flow.issue); XCTAssertFalse(flow.loaded); XCTAssertFalse(flow.canApply)
        reader.failure = nil; reader.supplied = try catalog("[]"); await flow.reload()
        XCTAssertNil(flow.issue); XCTAssertTrue(flow.loaded); XCTAssertTrue(flow.rows.isEmpty); XCTAssertFalse(flow.canApply)
        reader.supplied = try catalog(); await flow.reload(); XCTAssertTrue(flow.canApply)
    }
    func testNewerDraftOrAccountPreventsApplyingOldSelection() async throws {
        let (reader, owner, flow) = try await setup(); await flow.reload()
        guard case .template(var value) = owner.draft else { return XCTFail() }
        value.title = "Changed"; owner.edit(.template(value)); XCTAssertNil(flow.apply())
        let next = try XCTUnwrap(MerchantTemplateCategorySelection(owner: owner)); await next.reload()
        reader.fixture.switchAccount(); XCTAssertNil(next.apply())
    }
    func testLateResponseAfterCancelCannotRestoreCatalog() async throws {
        let (reader, _, flow) = try await setup(); reader.suspend = true
        let load = Task { await flow.reload() }; while reader.pending.isEmpty { await Task.yield() }
        flow.cancel(); reader.pending.removeFirst().resume(returning: try catalog()); await load.value
        XCTAssertFalse(flow.loaded); XCTAssertTrue(flow.rows.isEmpty); XCTAssertFalse(flow.canApply)
    }
    func testNewerReloadWinsOverOutOfOrderResponse() async throws {
        let (reader, _, flow) = try await setup(); reader.suspend = true
        let first = Task { await flow.reload() }; while reader.pending.count < 1 { await Task.yield() }
        let second = Task { await flow.reload() }; while reader.pending.count < 2 { await Task.yield() }
        reader.pending[1].resume(returning: try catalog("[]")); await second.value
        reader.pending[0].resume(returning: try catalog()); await first.value
        XCTAssertTrue(flow.loaded); XCTAssertTrue(flow.rows.isEmpty); XCTAssertFalse(flow.loading)
    }
}

private final class CategoryTransport: HTTPTransport {
    var replies: [String] = [], requests: [URLRequest] = []
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); guard !replies.isEmpty else { throw APIError.malformedResponse }
        return (Data(replies.removeFirst().utf8), 200)
    }
}
@MainActor private final class CategoryJournal: OperationPendingJournal {
    var record: OperationPendingRecord?
    func pending(ownerKey: String, targetKey: String) throws -> OperationPendingRecord? { record }
    func write(_ record: OperationPendingRecord) throws { self.record = record }
    func clear(_ record: OperationPendingRecord) throws { self.record = nil }
}
@MainActor final class MerchantTemplateCategoryServiceTests: XCTestCase {
    private let access = #"{"code":200,"data":{"active":true,"merchant":{"id":31},"roleCode":"MERCHANT_OWNER","permissions":["merchant:project:manage"]}}"#
    private func setup(_ transport: CategoryTransport, approved: Bool = false) throws -> (MerchantOperationsSessionReader, CategoryJournal) {
        let api = try APIConfiguration(baseURL: URL(string: "https://example.test/prod-api")!)
        let session = try MerchantOperationsSession(accountID: 7, epoch: 1, token: "synthetic-token", storageNamespace: "category-test")
        let approval = try OperationEndpointApproval(baseURL: api.baseURL, namespace: session.storageNamespace, accountID: session.accountID, paths: ["api/merchant/city-node/template/submit"])
        let journal = CategoryJournal()
        return (MerchantOperationsSessionReader(service: MerchantOperationsService(configuration: api, transport: transport), currentSession: { session }, approval: approved ? approval : nil, journal: journal), journal)
    }
    func testCatalogReadUsesExactTypeParentFormAfterMerchantGrant() async throws {
        let transport = CategoryTransport(); transport.replies = [access, "{\"code\":200,\"data\":" + categoryJSON + "}"]
        let (reader, _) = try setup(transport); let result = try await reader.templateCategories()
        XCTAssertEqual(result.rows.map(\.id), [101, 102]); XCTAssertEqual(transport.requests.count, 2)
        let request = try XCTUnwrap(transport.requests.last)
        XCTAssertEqual(request.url?.path, "/prod-api/api/category/list"); XCTAssertEqual(request.httpMethod, "POST")
        let body = String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self)
        XCTAssertTrue(body.contains("name=\"type\"\r\n\r\n4")); XCTAssertTrue(body.contains("name=\"parentid\"\r\n\r\n0"))
        XCTAssertFalse(reader.canSave)
    }
    func testDeniedMerchantGrantNeverCallsCatalog() async throws {
        let transport = CategoryTransport(); transport.replies = [access.replacingOccurrences(of: "merchant:project:manage", with: "merchant:basic:read")]
        let (reader, _) = try setup(transport)
        do { _ = try await reader.templateCategories(); XCTFail() } catch { XCTAssertEqual(error as? MerchantOperationsFailure, .accessDenied) }
        XCTAssertEqual(transport.requests.count, 1)
    }
    func testApprovedSaveSendsOrderedIDsAndReadsCanonicalLabelsAndPrimary() async throws {
        let initial = #"{"code":200,"data":{"id":71,"title":"Categories","validationMethod":2,"categoryId":101,"activityCategoryids":"101","sysCategoryList":[{"id":101,"categoryName":"Observation","type":4},{"id":102,"categoryName":"Puzzle","type":4}]}}"#
        let returned = #"{"code":200,"data":{"id":71,"title":"Categories","validationMethod":2,"categoryId":102,"activityCategoryids":"102,101","sysCategoryList":[{"id":102,"categoryName":"Server canonical puzzle","type":4}]}}"#
        let transport = CategoryTransport(); transport.replies = [access, initial, access, initial, access, initial, #"{"code":200,"data":71}"#, access, returned]
        let (reader, journal) = try setup(transport, approved: true)
        let owner = MerchantOperationsCoordinator(reader: reader, destination: .template(71)); await owner.load()
        var value = try categoryTemplate(); try value.categories.replace(with: Array(catalog().rows.reversed()))
        owner.edit(.template(value)); owner.prepare(); let review = try XCTUnwrap(owner.confirmation); await owner.confirm(review)
        let saves = transport.requests.filter { $0.url?.path.hasSuffix("/template/submit") == true }; XCTAssertEqual(saves.count, 1)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(saves.first?.httpBody)) as? [String: Any])
        XCTAssertEqual(body["categoryId"] as? Int, 102); XCTAssertEqual(body["activityCategoryids"] as? String, "102,101")
        XCTAssertNil(body["categoryIds"]); XCTAssertNil(body["sysCategoryList"])
        guard case .template(let source) = owner.draft else { return XCTFail() }
        XCTAssertEqual(source.categories.name(102), "Server canonical puzzle"); XCTAssertEqual(source.categories.primaryID, 102)
        XCTAssertEqual(transport.requests.last?.url?.path, "/prod-api/api/template/myinfo"); XCTAssertNil(journal.record)
        let count = transport.requests.count; await owner.confirm(review); XCTAssertEqual(transport.requests.count, count)
    }
    func testNoApprovalStillPreventsCategorySave() async throws {
        let transport = CategoryTransport(); let (reader, _) = try setup(transport)
        let value = try categoryTemplate()
        do { _ = try await reader.saveTemplateReviewed(value, baseline: value); XCTFail() }
        catch { XCTAssertEqual(error as? MerchantOperationsFailure, .liveWritesDisabled) }
        XCTAssertTrue(transport.requests.isEmpty)
    }
}
