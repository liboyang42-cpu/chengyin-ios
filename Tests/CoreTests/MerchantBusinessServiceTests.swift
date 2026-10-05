import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

private actor BusinessRecordingTransport: MerchantBusinessTestTransport {
    var requests: [URLRequest] = []
    let response: String
    let status: Int
    init(_ response: String, status: Int = 200) { self.response = response; self.status = status }
    func send(_ request: URLRequest) async throws -> (Data, Int) { requests.append(request); return (Data(response.utf8), status) }
}
final class MerchantBusinessServiceTests: XCTestCase {
    private func service(_ transport: BusinessRecordingTransport, writes: Bool = false) throws -> MerchantBusinessService {
        try .init(configuration: .init(baseURL: URL(string: "https://example.com/test")!), readTransport: transport, testingMutationTransport: writes ? transport : nil)
    }
    func testReadAdapterDecodesSourceEnvelope() async throws {
        let fake = BusinessRecordingTransport("{\"code\":200,\"data\":\(MerchantBusinessSyntheticFixtures.access)}")
        let access = try await service(fake).access(token: "synthetic-token")
        XCTAssertEqual(access.merchantID, 610)
        let requests = await fake.requests
        XCTAssertEqual(requests.count, 1); XCTAssertNil(requests[0].httpBody)
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Authorization"), "synthetic-token")
        XCTAssertEqual(requests[0].url?.path, "/test/api/merchant/access/me")
    }
    func testDefaultMutationStopsBeforeTransport() async throws {
        let fake = BusinessRecordingTransport(#"{"code":200,"data":{}}"#)
        do { _ = try await service(fake).execute(.addNote(customer: .init(61001), content: "Note", correctsNoteID: nil), requestID: "synthetic-1", token: "synthetic-token"); XCTFail() }
        catch { XCTAssertEqual(error as? MerchantBusinessFailure, .disabled) }
        let requests = await fake.requests; XCTAssertTrue(requests.isEmpty)
    }
    func testDormantCRMAdapterActuallyDispatchesAndDecodes() async throws {
        let fake = BusinessRecordingTransport(#"{"code":200,"msg":"Synthetic saved","data":{"id":901}}"#)
        let result = try await service(fake, writes: true).execute(.addNote(customer: .init(61001), content: " Note ", correctsNoteID: nil), requestID: "synthetic-1", token: "synthetic-token")
        XCTAssertEqual(result.message, "Synthetic saved")
        let requests = await fake.requests; let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.httpMethod, "POST"); XCTAssertEqual(request.url?.path, "/test/api/merchant/crm/customers/61001/notes")
        let object = try JSONDecoder().decode(MerchantBusinessValue.self, from: XCTUnwrap(request.httpBody)).object
        XCTAssertEqual(object?["content"], .string("Note")); XCTAssertEqual(object?["correctsNoteId"], .null)
    }
    func testAftercareRespondUsesJSONAndRefundQuery() async throws {
        let raw = #"{"code":200,"data":{"id":1,"refundId":62001,"decision":"REJECT","processing":"WAITING_PLATFORM_REVIEW","merchantOpinion":"REJECT","refunded":false}}"#
        let fake = BusinessRecordingTransport(raw)
        _ = try await service(fake, writes: true).execute(.aftercare(refund: .init(62001), decision: .reject, content: "Reason", evidenceKey: nil), requestID: "synthetic-1", token: "synthetic-token")
        let requests = await fake.requests; let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems, [URLQueryItem(name: "refundId", value: "62001")])
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }
    func testBusinessRejectionPreservesSourceMessage() async throws {
        let fake = BusinessRecordingTransport(#"{"code":409,"msg":"Version changed","data":null}"#)
        do { _ = try await service(fake).access(token: "synthetic-token"); XCTFail() }
        catch { XCTAssertEqual(error as? MerchantBusinessFailure, .rejected(409, "Version changed")) }
    }
    func testHTTP401DoesNotDecodeAsMalformed() async throws {
        let fake = BusinessRecordingTransport("", status: 401)
        do { _ = try await service(fake).access(token: "synthetic-token"); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .unauthorized) }
    }
    func testMalformedMutationReceiptDoesNotBecomeLocalSuccess() async throws {
        let fake = BusinessRecordingTransport(#"{"code":200,"data":null}"#)
        do { _ = try await service(fake, writes: true).execute(.assignTag(customer: .init(61001), name: "Tag", color: "#123456"), requestID: "synthetic-1", token: "synthetic-token"); XCTFail() }
        catch { XCTAssertEqual(error as? MerchantBusinessFailure, .malformed) }
    }
    func testVerificationRecordMultipartSeparateFromFinancialJSON() throws {
        let fake = BusinessRecordingTransport("{}"), service = try service(fake)
        let verification = try service.makeRequest(MerchantBusinessQuery.verificationRecords.request(), token: "synthetic-token")
        let financial = try service.makeRequest(MerchantBusinessQuery.redemptions(filter: "all", page: 1).request(), token: "synthetic-token")
        XCTAssertTrue(verification.value(forHTTPHeaderField: "Content-Type")!.hasPrefix("multipart/form-data"))
        XCTAssertEqual(financial.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertNotEqual(verification.url, financial.url)
    }
    func testRequestBuilderNeverIncludesMerchantOwnerOrMemberScope() throws {
        let fake = BusinessRecordingTransport("{}"), service = try service(fake)
        let request = try service.makeRequest(MerchantBusinessQuery.batches(page: 1).request(), token: "synthetic-token")
        let body = String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self)
        XCTAssertFalse(body.contains("merchantId")); XCTAssertFalse(body.contains("memberId"))
    }
}

@MainActor private final class BusinessTestReader: MerchantBusinessReading {
    var scope: MerchantBusinessScope? = .init(realm: "test://merchant", accountID: 99001, epoch: 1)
    let isConfigured = true
    let isOfflineExample = true
    var canExecuteSyntheticMutation = true
    var calls = 0
    var mutationError: Error?
    var preflightError: Error?
    var drift = false
    var changedSessionDuringSend = false
    var records: MerchantBusinessSnapshot
    init() throws {
        let access = try MerchantBusinessAccess(MerchantBusinessSyntheticFixtures.decode(MerchantBusinessSyntheticFixtures.access).object!)
        records = try .init(access: access, document: .init(query: .customer(.init(61001)), payload: MerchantBusinessSyntheticFixtures.decode(MerchantBusinessSyntheticFixtures.customer)))
    }
    func access() async throws -> MerchantBusinessAccess { records.access }
    func snapshot(_ query: MerchantBusinessQuery) async throws -> MerchantBusinessSnapshot {
        if let preflightError { throw preflightError }; if drift { throw MerchantBusinessFailure.conflict }; return records
    }
    func execute(_ mutation: MerchantBusinessMutation, requestID: String, scope: MerchantBusinessScope) async throws -> MerchantBusinessReceipt {
        calls += 1
        if changedSessionDuringSend { self.scope = .init(realm: scope.realm, accountID: 99002, epoch: scope.epoch + 1) }
        if let mutationError { throw mutationError }
        return try .init(mutation: mutation, message: "Synthetic saved", data: .object(["id": .int(901)]))
    }
}
@MainActor final class MerchantBusinessCoordinatorTests: XCTestCase {
    private func setup() async throws -> (BusinessTestReader, MerchantBusinessMemoryIntentStore, MerchantBusinessCoordinator) {
        let reader = try BusinessTestReader(), journal = MerchantBusinessMemoryIntentStore()
        let coordinator = MerchantBusinessCoordinator(reader: reader, journal: journal)
        await coordinator.load(.customer(try .init(61001))); return (reader, journal, coordinator)
    }
    private func review(_ coordinator: MerchantBusinessCoordinator) throws -> MerchantBusinessConfirmation {
        coordinator.prepare(.addNote(customer: try .init(61001), content: "Immutable draft", correctsNoteID: nil))
        return try XCTUnwrap(coordinator.confirmation)
    }
    func testCancelReviewDoesNotSend() async throws {
        let (reader, _, coordinator) = try await setup(); _ = try review(coordinator); coordinator.cancelConfirmation()
        XCTAssertNil(coordinator.confirmation); XCTAssertEqual(reader.calls, 0)
    }
    func testSuccessfulSyntheticSaveClearsOnlyItsIntent() async throws {
        let (reader, journal, coordinator) = try await setup(); let frozen = try review(coordinator)
        await coordinator.confirm(frozen)
        XCTAssertEqual(reader.calls, 1); XCTAssertTrue(try journal.intents().isEmpty); XCTAssertNotNil(coordinator.receipt)
    }
    func testDoubleConfirmCannotDispatchTwice() async throws {
        let (reader, _, coordinator) = try await setup(); let frozen = try review(coordinator)
        await coordinator.confirm(frozen); await coordinator.confirm(frozen); XCTAssertEqual(reader.calls, 1)
    }
    func testFreshTargetFailureStopsBeforeSend() async throws {
        let (reader, journal, coordinator) = try await setup(); let frozen = try review(coordinator); reader.drift = true
        await coordinator.confirm(frozen); XCTAssertEqual(reader.calls, 0); XCTAssertTrue(try journal.intents().isEmpty)
    }
    func testSessionSwitchInvalidatesFrozenConfirmation() async throws {
        let (reader, _, coordinator) = try await setup(); let frozen = try review(coordinator)
        reader.scope = .init(realm: "test://merchant", accountID: 99002, epoch: 2)
        await coordinator.confirm(frozen); XCTAssertEqual(reader.calls, 0)
    }
    func testUnknownOutcomeLocksAcrossCoordinatorRecreation() async throws {
        let (reader, journal, coordinator) = try await setup(); reader.mutationError = URLError(.timedOut)
        await coordinator.confirm(try review(coordinator)); XCTAssertTrue(coordinator.isLocked); XCTAssertEqual(try journal.intents().count, 1)
        let reopened = MerchantBusinessCoordinator(reader: reader, journal: journal); await reopened.load(.customer(try .init(61001)))
        reopened.prepare(.addNote(customer: try .init(61001), content: "New text", correctsNoteID: nil))
        XCTAssertNil(reopened.confirmation); XCTAssertEqual(reopened.failure, .pending); XCTAssertEqual(reader.calls, 1)
    }
    func testPostDispatchConflictCannotProveNoEffect() async throws {
        let (reader, journal, coordinator) = try await setup(); reader.mutationError = MerchantBusinessFailure.rejected(409, "Changed")
        await coordinator.confirm(try review(coordinator)); XCTAssertTrue(coordinator.isLocked); XCTAssertEqual(try journal.intents().count, 1)
    }
    func testPostDispatch5xx408And429KeepLocks() async throws {
        for code in [408, 429, 500, 502, 503] {
            let (reader, journal, coordinator) = try await setup(); reader.mutationError = MerchantBusinessFailure.rejected(code, "Uncertain")
            await coordinator.confirm(try review(coordinator)); XCTAssertTrue(coordinator.isLocked); XCTAssertEqual(try journal.intents().count, 1)
        }
    }
    func testPostDispatchAuthAndPermissionResponsesKeepLocks() async throws {
        let errors: [Error] = [APIError.unauthorized, MerchantBusinessFailure.denied]
        for error in errors {
            let (reader, journal, coordinator) = try await setup(); reader.mutationError = error
            await coordinator.confirm(try review(coordinator)); XCTAssertTrue(coordinator.isLocked); XCTAssertEqual(try journal.intents().count, 1)
        }
    }
    func testPreflightPermissionFailureIsDefinitelyUnsent() async throws {
        let (reader, journal, coordinator) = try await setup(); let frozen = try review(coordinator); reader.preflightError = MerchantBusinessFailure.denied
        await coordinator.confirm(frozen); XCTAssertEqual(reader.calls, 0); XCTAssertTrue(try journal.intents().isEmpty)
    }
    func testPreflightAuthenticationFailureIsDefinitelyUnsent() async throws {
        let (reader, journal, coordinator) = try await setup(); let frozen = try review(coordinator); reader.preflightError = APIError.unauthorized
        await coordinator.confirm(frozen); XCTAssertEqual(reader.calls, 0); XCTAssertTrue(try journal.intents().isEmpty)
    }
    func testTypedLocalDisabledResultCanClearUnsentReservation() async throws {
        let (reader, journal, coordinator) = try await setup(); reader.mutationError = MerchantBusinessFailure.disabled
        await coordinator.confirm(try review(coordinator)); XCTAssertFalse(coordinator.isLocked); XCTAssertTrue(try journal.intents().isEmpty)
    }
    func testSessionChangeAfterDispatchKeepsJournalAndHidesReceipt() async throws {
        let (reader, journal, coordinator) = try await setup(); reader.changedSessionDuringSend = true
        await coordinator.confirm(try review(coordinator)); XCTAssertNil(coordinator.receipt); XCTAssertEqual(try journal.intents().count, 1)
    }
    func testDisabledProductionReviewDoesNotReserveOrSend() async throws {
        let (reader, journal, coordinator) = try await setup(); reader.canExecuteSyntheticMutation = false
        await coordinator.confirm(try review(coordinator)); XCTAssertEqual(reader.calls, 0); XCTAssertTrue(try journal.intents().isEmpty); XCTAssertEqual(coordinator.failure, .disabled)
    }
    func testPersistentFileJournalSurvivesReinstantiationAndDoesNotStoreDraft() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("intents.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let scope = MerchantBusinessScope(realm: "https://example.com", accountID: 1, epoch: 1)
        let intent = MerchantBusinessIntent(scope: scope, merchantID: 2, target: "customer:3", requestID: "example-1")
        try MerchantBusinessFileIntentStore(url: url).reserve(intent)
        XCTAssertEqual(try MerchantBusinessFileIntentStore(url: url).intents(), [intent])
        let raw = try String(contentsOf: url); XCTAssertFalse(raw.contains("token")); XCTAssertFalse(raw.contains("content"))
    }
    func testCorruptJournalFailsClosed() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not-json".utf8).write(to: url)
        XCTAssertThrowsError(try MerchantBusinessFileIntentStore(url: url).intents())
    }
    func testJournalScopeDoesNotExpireWithEpoch() throws {
        let a = MerchantBusinessIntent(scope: .init(realm: "x", accountID: 1, epoch: 1), merchantID: 2, target: "customer:3", requestID: "one")
        let b = MerchantBusinessIntent(scope: .init(realm: "x", accountID: 1, epoch: 99), merchantID: 2, target: "customer:3", requestID: "two")
        XCTAssertTrue(a.sameTarget(as: b))
    }
}

private actor RedemptionSequenceTransport: MerchantBusinessTestTransport {
    var requests: [URLRequest] = []
    var replies: [String]
    var fail = false
    init(_ replies: [String]) { self.replies = replies }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        if request.url?.path.hasSuffix("access/me") == true { return (Data("{\"code\":200,\"data\":\(MerchantBusinessSyntheticFixtures.access)}".utf8), 200) }
        guard !replies.isEmpty else { throw URLError(.timedOut) }
        return (Data(replies.removeFirst().utf8), 200)
    }
}
@MainActor final class MerchantRedemptionAdapterTests: XCTestCase {
    func testSyntheticChoiceThenRedemptionDispatchesDistinctFields() async throws {
        let fake = RedemptionSequenceTransport([#"{"code":500,"data":{"needStationChoice":true,"stations":[{"registrationMerchantId":81,"name":"Example"}]}}"#, #"{"code":200,"data":{}}"#])
        let service = try MerchantBusinessService(configuration: .init(baseURL: URL(string: "https://example.com")!), readTransport: fake, testingMutationTransport: fake)
        let session = try MerchantBusinessSession(accountID: 99001, epoch: 1, token: "synthetic-token"), journal = MerchantBusinessMemoryIntentStore()
        let coordinator = MerchantRedemptionCoordinator(service: service, journal: journal, currentSession: { session })
        try await coordinator.begin(MerchantRedemptionContext.parse(#"{"type":"topic","code":"synthetic"}"#))
        XCTAssertEqual(coordinator.result?.outcome, .needsChoice); XCTAssertTrue(try journal.intents().isEmpty)
        try await coordinator.choose(.stationRegistration(.init(81)))
        XCTAssertEqual(coordinator.result?.outcome, .redeemed); XCTAssertTrue(try journal.intents().isEmpty)
        let requests = await fake.requests
        let last = try XCTUnwrap(requests.last), body = String(decoding: try XCTUnwrap(last.httpBody), as: UTF8.self)
        XCTAssertEqual(last.url?.path, "/api/registration/scan_qr_code_station")
        XCTAssertTrue(body.contains("registrationMerchantId")); XCTAssertFalse(body.contains("stationId"))
    }
    func testSelectionNotInServerChoicesNeverDispatches() async throws {
        let fake = RedemptionSequenceTransport([#"{"code":500,"data":{"needChapterChoice":true,"chapterIds":[71]}}"#])
        let service = try MerchantBusinessService(configuration: .init(baseURL: URL(string: "https://example.com")!), readTransport: fake, testingMutationTransport: fake)
        let session = try MerchantBusinessSession(accountID: 99001, epoch: 1, token: "synthetic-token")
        let coordinator = MerchantRedemptionCoordinator(service: service, journal: MerchantBusinessMemoryIntentStore(), currentSession: { session })
        try await coordinator.begin(MerchantRedemptionContext.parse(#"{"type":"topic","code":"synthetic"}"#))
        do { try await coordinator.choose(.chapter(.init(72))); XCTFail() } catch { XCTAssertEqual(error as? MerchantBusinessFailure, .stale) }
        let requests = await fake.requests; XCTAssertEqual(requests.count, 2)
    }
    func testUnknownRedemptionBlocksNextCodeAcrossRestart() async throws {
        let fake = RedemptionSequenceTransport([])
        let service = try MerchantBusinessService(configuration: .init(baseURL: URL(string: "https://example.com")!), readTransport: fake, testingMutationTransport: fake)
        let session = try MerchantBusinessSession(accountID: 99001, epoch: 1, token: "synthetic-token"), journal = MerchantBusinessMemoryIntentStore()
        let context = try MerchantRedemptionContext.parse("v1.synthetic.activity.untrusted")
        let first = MerchantRedemptionCoordinator(service: service, journal: journal, currentSession: { session })
        do { try await first.begin(context); XCTFail() } catch { XCTAssertEqual(error as? MerchantBusinessFailure, .unknown) }
        let reopened = MerchantRedemptionCoordinator(service: service, journal: journal, currentSession: { session })
        do { try await reopened.begin(context); XCTFail() } catch { XCTAssertEqual(error as? MerchantBusinessFailure, .pending) }
        let requests = await fake.requests
        XCTAssertEqual(requests.filter { $0.url?.path.hasSuffix("scan_dynamic_code") == true }.count, 1)
    }
    func testEvidenceUploadAdapterUsesSourceFileAndBizType() async throws {
        let key = "upload/merchant-aftercare-evidence/" + String(repeating: "a", count: 32) + ".png"
        let fake = BusinessRecordingTransport("{\"code\":200,\"fileName\":\"\(key)\"}")
        let adapter = try MerchantAftercareEvidenceAdapter(configuration: .init(baseURL: URL(string: "https://example.com")!), testingTransport: fake)
        let access = try MerchantBusinessAccess(MerchantBusinessSyntheticFixtures.decode(MerchantBusinessSyntheticFixtures.access).object!)
        let receipt = try await adapter.uploadSynthetic(bytes: Data([1,2,3]), filename: "example.png", mimeType: "image/png", access: access, token: "synthetic-token")
        XCTAssertEqual(receipt.objectKey, key)
        let requests = await fake.requests, request = try XCTUnwrap(requests.first)
        let body = String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self)
        XCTAssertEqual(request.url?.path, "/api/common/uploadOSS"); XCTAssertTrue(body.contains("merchant_aftercare_evidence")); XCTAssertTrue(body.contains("name=\"file\""))
    }
    func testEvidenceUploadDisabledByDefault() async throws {
        let adapter = try MerchantAftercareEvidenceAdapter(configuration: .init(baseURL: URL(string: "https://example.com")!))
        let access = try MerchantBusinessAccess(MerchantBusinessSyntheticFixtures.decode(MerchantBusinessSyntheticFixtures.access).object!)
        do { _ = try await adapter.uploadSynthetic(bytes: Data([1]), filename: "example.png", mimeType: "image/png", access: access, token: "synthetic-token"); XCTFail() }
        catch { XCTAssertEqual(error as? MerchantBusinessFailure, .disabled) }
    }
}
