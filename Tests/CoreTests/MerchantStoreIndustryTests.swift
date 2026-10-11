import Foundation
import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private let industryJSON = #"[{"id":8,"categoryName":"Café","type":1},{"id":9,"categoryName":"Bookshop","type":1},{"id":10,"categoryName":"Workshop","type":1}]"#
private func industryCatalog(_ raw: String = industryJSON) throws -> MerchantStoreIndustryCatalog {
    try JSONDecoder().decode(MerchantStoreIndustryCatalog.self, from: Data(raw.utf8))
}
private func industryDecor() throws -> MerchantStoreDecor {
    try JSONDecoder().decode(MerchantStoreDecor.self, from: Data(MerchantOperationsFixtureData.storeJSON.utf8))
}

final class MerchantStoreIndustryContractTests: XCTestCase {
    func testTypeOneCatalogIsDistinctFromGameplayAndAcceptsRealEmpty() throws {
        XCTAssertEqual(try industryCatalog().rows.map(\.id), [8, 9, 10]); XCTAssertTrue(try industryCatalog("[]").rows.isEmpty)
        for raw in ["null", "{}", #"[{"id":1,"categoryName":"A","type":4}]"#,
                    #"[{"id":0,"categoryName":"A","type":1}]"#, #"[{"id":2147483648,"categoryName":"A"}]"#,
                    #"[{"id":1,"categoryName":"  "}]"#, #"[{"id":1,"categoryName":"A"},{"id":1,"categoryName":"B"}]"#] {
            XCTAssertThrowsError(try industryCatalog(raw))
        }
    }
    func testIndustryAloneMakesNewDecorChoiceReviewable() throws {
        var empty = try JSONDecoder().decode(MerchantStoreDecor.self, from: Data("{}".utf8))
        XCTAssertEqual(empty.blocker, "merchant.operations.decorEmpty")
        empty.categoryID = 0; XCTAssertEqual(empty.blocker, "merchant.operations.decorEmpty")
        empty.categoryID = 9; XCTAssertNil(empty.blocker)
        XCTAssertNoThrow(try MerchantOperationsDraft.decor(empty).previews())
    }
    func testChangeReviewExistsOnlyForChangedDecorIndustry() throws {
        let before = try industryDecor(); var after = before
        XCTAssertNil(MerchantStoreIndustryChange(baseline: .decor(before), draft: .decor(after)))
        after.categoryID = 9
        let change = try XCTUnwrap(MerchantStoreIndustryChange(baseline: .decor(before), draft: .decor(after)))
        XCTAssertEqual(change.previousID, 8); XCTAssertEqual(change.selectedID, 9)
        XCTAssertNil(MerchantStoreIndustryChange(baseline: .gallery(before), draft: .gallery(after)))
        XCTAssertNil(MerchantStoreIndustryChange(baseline: nil, draft: .decor(after)))
    }
    func testExistingDecorWireFieldAndOtherFactsArePreserved() throws {
        let before = try industryDecor(); var after = before; after.categoryID = 9
        let request = try XCTUnwrap(MerchantOperationsDraft.decor(after).previews().first)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.json) as? [String: Any])
        XCTAssertEqual(request.path, "api/merchant/decor/save"); XCTAssertEqual(body["categoryId"] as? Int, 9)
        XCTAssertEqual(body["featuredId"] as? Int, before.featuredID); XCTAssertEqual(body["gallery"] as? String, try MerchantStoreDecor.listString(before.gallery))
        XCTAssertEqual(body["tags"] as? String, try MerchantStoreDecor.listString(before.tags)); XCTAssertNil(body["categoryName"])
        XCTAssertNil(body["categoryIds"]); XCTAssertNil(body["activityCategoryids"]); XCTAssertNil(body["type"])
    }
}

@MainActor private final class IndustryReader: MerchantOperationsReading {
    let fixture = MerchantOperationsFixtureReader()
    var scope: UUID { fixture.scope }
    var isConfigured: Bool { true }
    var isAuthenticated: Bool { fixture.isAuthenticated }
    var isOfflineExample: Bool { true }
    var catalog = try! industryCatalog()
    var failure: APIError?
    var suspend = false
    var pending: [CheckedContinuation<MerchantStoreIndustryCatalog, Error>] = []
    func access() async throws -> MerchantOperationsAccess { try await fixture.access() }
    func document(_ destination: MerchantOperationsDestination) async throws -> MerchantOperationsDocument { try await fixture.document(destination) }
    func saveExample(_ draft: MerchantOperationsDraft) async throws { try await fixture.saveExample(draft) }
    func storeIndustries() async throws -> MerchantStoreIndustryCatalog {
        if let failure { throw failure }
        if suspend { return try await withCheckedThrowingContinuation { pending.append($0) } }
        return catalog
    }
}
@MainActor final class MerchantStoreIndustrySelectionTests: XCTestCase {
    private func setup(id: Int? = 8) async throws -> (IndustryReader, MerchantOperationsCoordinator, MerchantStoreIndustrySelection) {
        let reader = IndustryReader(); var decor = try industryDecor(); decor.categoryID = id
        reader.fixture.replace(.decor, with: .draft(.decor(decor)))
        let owner = MerchantOperationsCoordinator(reader: reader, destination: .decor); await owner.load()
        return (reader, owner, try XCTUnwrap(MerchantStoreIndustrySelection(owner: owner)))
    }
    func testCancelNeverEditsOrSaves() async throws {
        let (reader, owner, flow) = try await setup(); let original = owner.draft
        await flow.reload(); flow.select(9); XCTAssertTrue(flow.canApply); flow.cancel()
        XCTAssertNil(flow.apply()); XCTAssertEqual(owner.draft, original); XCTAssertEqual(reader.fixture.saveCount, 0)
    }
    func testSingleSelectionChangesOnlyIndustryAndAppliesOnce() async throws {
        let (reader, owner, flow) = try await setup(); await flow.reload(); flow.select(9); flow.select(10); flow.select(999)
        XCTAssertEqual(flow.selectedID, 10)
        let edited = try XCTUnwrap(flow.apply()); var expected = try industryDecor(); expected.categoryID = 10
        XCTAssertEqual(edited, expected); XCTAssertNil(flow.apply()); XCTAssertEqual(reader.fixture.saveCount, 0)
        owner.edit(.decor(edited)); XCTAssertTrue(owner.isDirty)
    }
    func testApplyingExistingChoiceIsExactNoOp() async throws {
        let (_, owner, flow) = try await setup(); await flow.reload()
        let edited = try XCTUnwrap(flow.apply()); owner.edit(.decor(edited)); XCTAssertFalse(owner.isDirty)
    }
    func testMissingSavedIndustryRemainsUntilUserChoosesReplacement() async throws {
        let (_, owner, flow) = try await setup(id: 999); let original = owner.draft
        await flow.reload(); XCTAssertTrue(flow.previousIsUnavailable); XCTAssertEqual(flow.selectedID, 999)
        XCTAssertFalse(flow.canApply); XCTAssertEqual(owner.draft, original)
        flow.select(9); XCTAssertEqual(try XCTUnwrap(flow.apply()).categoryID, 9)
    }
    func testNoSavedIndustryDoesNotAutoselectFirstCatalogEntry() async throws {
        let (_, _, flow) = try await setup(id: nil); await flow.reload()
        XCTAssertNil(flow.selectedID); XCTAssertFalse(flow.canApply); flow.select(9); XCTAssertTrue(flow.canApply)
    }
    func testErrorEmptyRetryAndReloadPreserveBufferedSelection() async throws {
        let (reader, _, flow) = try await setup(); reader.failure = .httpStatus(503)
        await flow.reload(); XCTAssertNotNil(flow.issue); XCTAssertFalse(flow.loaded)
        reader.failure = nil; reader.catalog = try industryCatalog("[]"); await flow.reload()
        XCTAssertTrue(flow.loaded); XCTAssertNil(flow.issue); XCTAssertTrue(flow.rows.isEmpty); XCTAssertFalse(flow.canApply)
        reader.catalog = try industryCatalog(); await flow.reload(); flow.select(9); await flow.reload()
        XCTAssertEqual(flow.selectedID, 9); XCTAssertTrue(flow.canApply)
    }
    func testNewDocumentEditsInvalidateOldPicker() async throws {
        let (_, owner, flow) = try await setup(); await flow.reload()
        guard case .decor(var value) = owner.draft else { return XCTFail() }
        value.slogan = "New draft"; owner.edit(.decor(value)); XCTAssertFalse(flow.isCurrent); XCTAssertNil(flow.apply())
    }
    func testAccountChangeIgnoresLateCatalogAndCannotApply() async throws {
        let (reader, _, flow) = try await setup(); reader.suspend = true
        let task = Task { await flow.reload() }; while reader.pending.isEmpty { await Task.yield() }
        reader.fixture.switchAccount(); reader.pending[0].resume(returning: try industryCatalog()); await task.value
        XCTAssertFalse(flow.loaded); XCTAssertFalse(flow.isCurrent); XCTAssertNil(flow.apply())
    }
    func testCancelIgnoresLateCatalogResponse() async throws {
        let (reader, _, flow) = try await setup(); reader.suspend = true
        let task = Task { await flow.reload() }; while reader.pending.isEmpty { await Task.yield() }
        flow.cancel(); reader.pending[0].resume(returning: try industryCatalog()); await task.value
        XCTAssertTrue(flow.rows.isEmpty); XCTAssertFalse(flow.loaded); XCTAssertFalse(flow.loading)
    }
    func testNewerReloadWinsOverOutOfOrderCatalog() async throws {
        let (reader, _, flow) = try await setup(); reader.suspend = true
        let first = Task { await flow.reload() }; while reader.pending.count < 1 { await Task.yield() }
        let second = Task { await flow.reload() }; while reader.pending.count < 2 { await Task.yield() }
        reader.pending[1].resume(returning: try industryCatalog("[]")); await second.value
        reader.pending[0].resume(returning: try industryCatalog()); await first.value
        XCTAssertTrue(flow.loaded); XCTAssertTrue(flow.rows.isEmpty); XCTAssertFalse(flow.loading)
    }
}

private final class IndustryTransport: HTTPTransport {
    var replies: [String] = [], requests: [URLRequest] = []
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); guard !replies.isEmpty else { throw APIError.malformedResponse }
        return (Data(replies.removeFirst().utf8), 200)
    }
}
@MainActor private final class IndustryJournal: OperationPendingJournal {
    var record: OperationPendingRecord?
    func pending(ownerKey: String, targetKey: String) throws -> OperationPendingRecord? { record }
    func write(_ record: OperationPendingRecord) throws { self.record = record }
    func clear(_ record: OperationPendingRecord) throws { self.record = nil }
}
@MainActor final class MerchantStoreIndustryServiceTests: XCTestCase {
    private let access = #"{"code":200,"data":{"active":true,"merchant":{"id":31},"roleCode":"MERCHANT_OWNER","permissions":["merchant:profile:write","merchant:coop:manage"]}}"#
    private var initial: String { "{\"code\":200,\"data\":" + MerchantOperationsFixtureData.storeJSON + "}" }
    private func setup(_ transport: IndustryTransport, approved: Bool = false) throws -> (MerchantOperationsSessionReader, IndustryJournal) {
        let config = try APIConfiguration(baseURL: URL(string: "https://example.test/prod-api")!)
        let session = try MerchantOperationsSession(accountID: 7, epoch: 1, token: "synthetic-token", storageNamespace: "industry-test")
        let approval = try OperationEndpointApproval(baseURL: config.baseURL, namespace: session.storageNamespace, accountID: session.accountID, paths: ["api/merchant/decor/save"])
        let journal = IndustryJournal()
        return (.init(service: .init(configuration: config, transport: transport), currentSession: { session }, approval: approved ? approval : nil, journal: journal), journal)
    }
    func testCatalogUsesIndustryTypeOneAndExistingProfileGrant() async throws {
        let transport = IndustryTransport(); transport.replies = [access, "{\"code\":200,\"data\":" + industryJSON + "}"]
        let (reader, _) = try setup(transport); let result = try await reader.storeIndustries()
        XCTAssertEqual(result.rows.count, 3); XCTAssertEqual(transport.requests.count, 2); XCTAssertFalse(reader.canSave)
        let request = try XCTUnwrap(transport.requests.last); XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/prod-api/api/category/list")
        let body = String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self)
        XCTAssertTrue(body.contains("name=\"type\"\r\n\r\n1\r\n")); XCTAssertTrue(body.contains("name=\"parentid\"\r\n\r\n0\r\n"))
    }
    func testProjectPermissionAloneCannotReadIndustryPicker() async throws {
        let transport = IndustryTransport(); transport.replies = [access.replacingOccurrences(of: "merchant:profile:write", with: "merchant:project:manage")]
        let (reader, _) = try setup(transport)
        do { _ = try await reader.storeIndustries(); XCTFail() } catch { XCTAssertEqual(error as? MerchantOperationsFailure, .accessDenied) }
        XCTAssertEqual(transport.requests.count, 1)
    }
    private func exerciseSave(readbackFails: Bool) async throws {
        let transport = IndustryTransport()
        let canonical = initial.replacingOccurrences(of: "\"categoryId\":8", with: "\"categoryId\":10")
        transport.replies = [access, initial, access, initial, access, initial, #"{"code":200,"msg":"Synthetic saved"}"#, access,
                             readbackFails ? #"{"code":200,"data":[]}"# : canonical]
        let (reader, journal) = try setup(transport, approved: true)
        let owner = MerchantOperationsCoordinator(reader: reader, destination: .decor); await owner.load()
        guard case .decor(var value) = owner.draft else { return XCTFail() }
        value.categoryID = 9; owner.edit(.decor(value)); owner.prepare(); let review = try XCTUnwrap(owner.confirmation)
        await owner.confirm(review)
        let saves = transport.requests.filter { $0.url?.path.hasSuffix("/decor/save") == true }; XCTAssertEqual(saves.count, 1)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(saves.first?.httpBody)) as? [String: Any])
        XCTAssertEqual(body["categoryId"] as? Int, 9); XCTAssertEqual(body["featuredId"] as? Int, 17)
        XCTAssertNil(body["categoryName"]); XCTAssertNil(body["type"]); XCTAssertNil(journal.record)
        XCTAssertEqual(transport.requests.last?.url?.path, "/prod-api/api/merchant/coop-profile")
        if readbackFails {
            XCTAssertNil(owner.draft); XCTAssertNil(owner.document); XCTAssertFalse(owner.isLocked)
            XCTAssertEqual(owner.issue, .key("merchant.industry.readbackFailed"))
        } else {
            guard case .decor(let saved) = owner.draft else { return XCTFail() }
            XCTAssertEqual(saved.categoryID, 10); XCTAssertFalse(owner.isDirty)
            XCTAssertEqual(owner.issue, .key("merchant.industry.readback"))
        }
        let count = transport.requests.count; await owner.confirm(review); XCTAssertEqual(transport.requests.count, count)
        if readbackFails {
            transport.replies += [access, canonical]; await owner.load()
            guard case .decor(let recovered) = owner.draft else { return XCTFail() }
            XCTAssertEqual(recovered.categoryID, 10)
            XCTAssertEqual(transport.requests.filter { $0.url?.path.hasSuffix("/decor/save") == true }.count, 1)
        }
    }
    func testApprovedSaveReadsAuthoritativeIndustryInsteadOfPromotingSubmittedID() async throws { try await exerciseSave(readbackFails: false) }
    func testAcknowledgedSaveWithFailedReadbackCannotBeReplayed() async throws { try await exerciseSave(readbackFails: true) }
    func testNoApprovalStillPreventsStoreWrite() async throws {
        let transport = IndustryTransport(); let (reader, _) = try setup(transport)
        let before = try industryDecor(); var after = before; after.categoryID = 9
        do { try await reader.saveReviewed(.decor(after), baseline: .decor(before)); XCTFail() }
        catch { XCTAssertEqual(error as? MerchantOperationsFailure, .liveWritesDisabled) }
        XCTAssertTrue(transport.requests.isEmpty)
    }
}
