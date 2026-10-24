import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

private actor DeskPathTransport: MerchantBusinessTestTransport {
    var requests: [URLRequest] = []
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        let path = request.url?.path ?? ""
        let json: String
        if path.hasSuffix("/access/me") {
            let access = MerchantBusinessSyntheticFixtures.access.replacingOccurrences(
                of: "\"merchant:operator:manage\"", with: "\"merchant:operator:manage\",\"merchant:project:manage\"")
            json = "{\"code\":200,\"data\":\(access)}"
        } else if path.hasSuffix("/products/detail") {
            json = #"{"code":200,"data":{"productId":3,"skus":[{"skuId":44,"skuName":"door","price":88,"stock":2,"bookable":false,"slotMinutes":60,"capacityPerSlot":0}]}}"#
        } else if path.hasSuffix("/sku/save") {
            json = #"{"code":200,"msg":"Synthetic saved","data":{"skuId":44}}"#
        } else if path.hasSuffix("/receipt") {
            json = #"{"code":200,"data":{"requestId":"desk-req-01","state":"APPLIED","action":"SKU_SAVE","targetType":"pms_sku","targetId":44}}"#
        } else {
            json = #"{"code":404,"msg":"missing","data":null}"#
        }
        return (Data(json.utf8), 200)
    }
}
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
    func testDeskSkuSaveDispatchesOriginalPath() async throws {
        let fake = BusinessRecordingTransport(#"{"code":200,"msg":"Synthetic saved","data":{"skuId":44}}"#)
        let sent = try await service(fake, writes: true).execute(
            .saveSku(productID: 3, skuID: 44, name: "door", price: "1", stock: 2,
                    originalPrice: nil, pic: nil, bookable: false, slotMinutes: 60,
                    capacityPerSlot: 0, ruleVersion: 4),
            requestID: "desk-req-01", token: "synthetic-token")
        XCTAssertEqual(sent.data.object?["skuId"], .int(44))
        let recorded = await fake.requests
        let request = try XCTUnwrap(recorded.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/test/api/merchant/desk/products/sku/save")
        let body = String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self)
        XCTAssertTrue(body.contains("\"skuName\":\"door\""))
        XCTAssertTrue(body.contains("\"price\":\"1\""))
        XCTAssertFalse(body.contains("ownerMemberId"))
        XCTAssertFalse(body.contains("\"action\""))
        XCTAssertTrue(body.contains("\"ruleVersion\":4"))
        XCTAssertTrue(body.contains("\"slotMinutes\":60"))
    }
    func testDeskDetailSaveAndReceiptUseTheOriginalPaths() async throws {
        let transport = DeskPathTransport()
        let service = try MerchantBusinessService(configuration: .init(baseURL: URL(string: "https://example.com/test")!),
                                                  readTransport: transport, testingMutationTransport: transport)
        let access = try await service.access(token: "synthetic-token")
        let journey = MerchantSkuSaveJourney()
        let detail = try await service.read(.productDetail(productID: 3), access: access, token: "synthetic-token")
        let frozen = try XCTUnwrap(journey.freeze(access: access, accountID: 7, productID: 3, skuID: 44,
                                                  requestID: "desk-req-01", skuName: "door", price: "88.00", stock: 2))
        XCTAssertEqual(journey.readBack(detail: detail, intent: frozen, laterFormPrice: "99.00")?.price, "88.00")
        _ = try await service.execute(.saveSku(productID: 3, skuID: 44, name: frozen.skuName, price: frozen.price,
                                               stock: frozen.stock, originalPrice: frozen.originalPrice, pic: frozen.pic,
                                               bookable: frozen.bookable, slotMinutes: frozen.slotMinutes,
                                               capacityPerSlot: frozen.capacityPerSlot, ruleVersion: frozen.ruleVersion),
                                     requestID: frozen.requestID, token: "synthetic-token")
        let receipt = try await service.read(.receipt(requestID: frozen.requestID), access: access, token: "synthetic-token")
        let recovered = journey.recover(requestID: frozen.requestID, receipt: receipt, currentForm: "price=99.00")
        XCTAssertEqual(recovered.outcome, "APPLIED")
        XCTAssertEqual(recovered.skuID, 44)
        XCTAssertNil(recovered.payload)
        let paths = await transport.requests.compactMap { $0.url?.path }
        XCTAssertEqual(paths, [
            "/test/api/merchant/access/me",
            "/test/api/merchant/desk/products/detail",
            "/test/api/merchant/desk/products/sku/save",
            "/test/api/merchant/desk/receipt"
        ])
    }
    func testDeskReadRejectsAWriteBeforeTransport() async throws {
        let fake = BusinessRecordingTransport(#"{"code":200,"data":{"skuId":44}}"#)
        let idle = try service(fake)
        do {
            _ = try await idle.execute(.saveSku(productID: 3, skuID: 44, name: "door", price: "1", stock: 2,
                                                originalPrice: nil, pic: nil, bookable: false, slotMinutes: 60,
                                                capacityPerSlot: 0, ruleVersion: nil),
                                      requestID: "desk-req-01", token: "synthetic-token")
            XCTFail("save stays disabled")
        } catch {
            XCTAssertEqual(error as? MerchantBusinessFailure, .disabled)
        }
        let denied = try MerchantBusinessAccess(MerchantBusinessObject([
            "active": .bool(true),
            "merchant": .object(["id": .int(9), "name": .string("synthetic-shop")]),
            "roleCode": .string("MERCHANT_OWNER"),
            "permissions": .array([.string("merchant:basic:read")]),
            "canManageOperators": .bool(false)
        ]))
        do {
            _ = try await idle.read(.productDetail(productID: 3), access: denied, token: "synthetic-token")
            XCTFail("detail needs project manage")
        } catch {
            XCTAssertEqual(error as? MerchantBusinessFailure, .denied)
        }
        let allowed = try MerchantBusinessAccess(MerchantBusinessObject([
            "active": .bool(true),
            "merchant": .object(["id": .int(9)]),
            "roleCode": .string("MERCHANT_OWNER"),
            "permissions": .array([.string("merchant:project:manage"), .string("merchant:basic:read")]),
            "canManageOperators": .bool(false)
        ]))
        do {
            _ = try await idle.read(.productDetail(productID: 0), access: allowed, token: "synthetic-token")
            XCTFail("product id")
        } catch {
            XCTAssertEqual(error as? MerchantBusinessFailure, .invalid)
        }
        do {
            _ = try await idle.read(.receipt(requestID: "short"), access: allowed, token: "synthetic-token")
            XCTFail("request id")
        } catch {
            XCTAssertEqual(error as? MerchantBusinessFailure, .invalid)
        }
        do {
            _ = try await idle.read(.receipt(requestID: "desk-req-01\u{2028}"), access: allowed, token: "synthetic-token")
            XCTFail("line separator")
        } catch {
            XCTAssertEqual(error as? MerchantBusinessFailure, .invalid)
        }
        let trimmed = try MerchantDeskRead.receipt(requestID: "desk-req-01\n").request()
        guard case .json(let fields) = trimmed.body else {
            XCTFail("json")
            return
        }
        XCTAssertEqual(fields["requestId"], .string("desk-req-01"))
        let recorded = await fake.requests
        XCTAssertTrue(recorded.isEmpty)
    }
    func testDeskDetailAndReceiptUseOriginalPaths() async throws {
        let fake = BusinessRecordingTransport("{}")
        let service = try service(fake)
        let journey = MerchantSkuSaveJourney()
        let detail = try service.makeRequest(XCTUnwrap(journey.detailRequest(productID: 3)), token: "synthetic-token")
        XCTAssertEqual(detail.url?.path, "/test/api/merchant/desk/products/detail")
        let receipt = try service.makeRequest(XCTUnwrap(journey.receiptRequest(requestID: "desk-req-01")), token: "synthetic-token")
        XCTAssertEqual(receipt.httpMethod, "POST")
        XCTAssertEqual(receipt.url?.path, "/test/api/merchant/desk/receipt")
        let access = try service.makeRequest(journey.accessRequest(), token: "synthetic-token")
        XCTAssertEqual(access.url?.path, "/test/api/merchant/access/me")
        XCTAssertNil(access.httpBody)
        let requests = await fake.requests
        XCTAssertTrue(requests.isEmpty)
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

    func testDeskSkuConfirmSavesOnceAndReopenReadsTheReceipt() async throws {
        let transport = DeskSkuEntryTransport()
        let service = try MerchantBusinessService(configuration: .init(baseURL: URL(string: "https://example.com/test")!),
                                                  readTransport: transport, testingMutationTransport: transport)
        let journal = MerchantBusinessMemoryIntentStore()
        let scope = MerchantBusinessScope(realm: "desk", accountID: 7, epoch: 1)
        let access = try MerchantBusinessAccess(MerchantBusinessObject([
            "active": .bool(true),
            "merchant": .object(["id": .int(9)]),
            "roleCode": .string("MERCHANT_OWNER"),
            "permissions": .array([.string("merchant:project:manage"), .string("merchant:basic:read")]),
            "canManageOperators": .bool(false)
        ]))
        let session = try MerchantBusinessSession(accountID: 7, epoch: 1, token: "synthetic-token")
        let desk = MerchantDeskSkuDesk(service: service, journal: journal, scope: scope, currentSession: { session })
        let edit = MerchantDeskSkuDesk.Edit(skuName: "door", price: "88.00", stock: 2)
        await desk.present(productID: 3, skuID: 44, access: access, accountID: 7, token: "synthetic-token")
        guard case .editing(let shown) = desk.phase else {
            XCTFail("editing")
            return
        }
        XCTAssertEqual(shown.skuName, "door")
        XCTAssertEqual(shown.price, "88")
        XCTAssertEqual(shown.originalPrice, "100.00")
        XCTAssertEqual(shown.pic, "media-asset:1")
        XCTAssertEqual(shown.slotMinutes, 30)
        let savesAfterPresent = await transport.paths.filter { $0.hasSuffix("/sku/save") }
        XCTAssertEqual(savesAfterPresent.count, 0)
        await desk.load(productID: 3, skuID: 44, edit: edit, access: access, accountID: 7, token: "synthetic-token")
        guard case .frozen(let intent) = desk.phase else {
            XCTFail("frozen")
            return
        }
        XCTAssertEqual(intent.price, "88.00")
        XCTAssertEqual(intent.originalPrice, "100.00")
        XCTAssertEqual(intent.pic, "media-asset:1")
        XCTAssertEqual(intent.slotMinutes, 30)
        XCTAssertEqual(intent.ruleVersion, 3)
        XCTAssertFalse(intent.requestID.hasPrefix("desk-req"))
        await desk.confirm(access: access, token: "synthetic-token")
        guard case .applied(let requestID, let skuID) = desk.phase else {
            XCTFail("applied")
            return
        }
        XCTAssertEqual(requestID, intent.requestID)
        XCTAssertEqual(skuID, 44)
        let saved = await transport.paths.filter { $0.hasSuffix("/sku/save") }
        XCTAssertEqual(saved.count, 1)
        let body = await transport.saveBody
        XCTAssertTrue(body.contains("\"price\":\"88.00\""))
        XCTAssertTrue(body.contains("\"originalPrice\":\"100.00\""))
        XCTAssertTrue(body.contains("\"pic\":\"media-asset:1\""))
        XCTAssertTrue(body.contains("\"slotMinutes\":30"))
        XCTAssertTrue(body.contains("\"ruleVersion\":3"))
        XCTAssertTrue(body.contains("\"requestId\":\"\(intent.requestID)\""))
        let remaining = try journal.intents()
        XCTAssertTrue(remaining.isEmpty)
        await transport.setDetailRuleVersion(5)
        await desk.noteLater(productID: 3, skuID: 44, access: access, token: "synthetic-token")
        XCTAssertEqual(desk.laterRuleVersion, 5)
        XCTAssertEqual(desk.phase, .applied(requestID: requestID, skuID: 44))
        let savesAfterLater = await transport.paths.filter { $0.hasSuffix("/sku/save") }
        XCTAssertEqual(savesAfterLater.count, 1)

        await transport.setReceiptApplied(false)
        let lost = MerchantDeskSkuDesk(service: service, journal: journal, scope: scope, currentSession: { session })
        await lost.load(productID: 3, skuID: 44, edit: MerchantDeskSkuDesk.Edit(skuName: "door", price: "88.00", stock: 2),
                        access: access, accountID: 7, token: "synthetic-token")
        await transport.setFailSave(true)
        await lost.confirm(access: access, token: "synthetic-token")
        guard case .unknown(let unknownID) = lost.phase else {
            XCTFail("unknown")
            return
        }
        XCTAssertEqual(try journal.intents().count, 1)
        let savesBeforeReopen = await transport.paths.filter { $0.hasSuffix("/sku/save") }.count
        let readsBeforeSwitch = await transport.paths.filter { $0.hasSuffix("/receipt") }.count
        let switched = MerchantDeskSkuDesk(service: service, journal: journal, scope: MerchantBusinessScope(realm: "desk", accountID: 8, epoch: 1))
        await switched.reopen(productID: 3, skuID: 44, access: access, token: "synthetic-token")
        XCTAssertEqual(switched.phase, .idle)
        XCTAssertEqual(try journal.intents().count, 1)
        let readsAfterSwitch = await transport.paths.filter { $0.hasSuffix("/receipt") }
        XCTAssertEqual(readsAfterSwitch.count, readsBeforeSwitch)
        await lost.reopen(productID: 3, skuID: 44, access: access, token: "synthetic-token")
        XCTAssertEqual(lost.phase, .unknown(requestID: unknownID))
        let savesAfterUnknown = await transport.paths.filter { $0.hasSuffix("/sku/save") }
        XCTAssertEqual(savesAfterUnknown.count, savesBeforeReopen)
        await transport.setReceiptApplied(true)
        await transport.setReceiptRequestID(unknownID)
        await lost.reopen(productID: 3, skuID: 44, access: access, token: "synthetic-token")
        XCTAssertEqual(lost.phase, .applied(requestID: unknownID, skuID: 44))
        XCTAssertTrue(try journal.intents().isEmpty)
        let savesAfterApplied = await transport.paths.filter { $0.hasSuffix("/sku/save") }
        XCTAssertEqual(savesAfterApplied.count, savesBeforeReopen)
    }

    func testWrongSkuTargetAndUnauthorizedSaveDoNotClearTheJournal() async throws {
        let transport = DeskSkuEntryTransport()
        let service = try MerchantBusinessService(configuration: .init(baseURL: URL(string: "https://example.com/test")!),
                                                  readTransport: transport, testingMutationTransport: transport)
        let journal = MerchantBusinessMemoryIntentStore()
        let scope = MerchantBusinessScope(realm: "desk", accountID: 7, epoch: 1)
        let access = try MerchantBusinessAccess(MerchantBusinessObject([
            "active": .bool(true),
            "merchant": .object(["id": .int(9)]),
            "roleCode": .string("MERCHANT_OWNER"),
            "permissions": .array([.string("merchant:project:manage"), .string("merchant:basic:read")]),
            "canManageOperators": .bool(false)
        ]))
        let session = try MerchantBusinessSession(accountID: 7, epoch: 1, token: "synthetic-token")
        let desk = MerchantDeskSkuDesk(service: service, journal: journal, scope: scope, currentSession: { session })
        await desk.load(productID: 3, skuID: 44, edit: MerchantDeskSkuDesk.Edit(skuName: "door", price: "88.00", stock: 2),
                        access: access, accountID: 7, token: "synthetic-token")
        await transport.setSaveTarget(45)
        await desk.confirm(access: access, token: "synthetic-token")
        let afterWrongTarget = try journal.intents()
        XCTAssertEqual(afterWrongTarget.count, 1)
        guard case .unknown = desk.phase else {
            XCTFail("wrong target stays unknown")
            return
        }
        let restartedSession = try MerchantBusinessSession(accountID: 7, epoch: 9, token: "synthetic-token")
        let restarted = MerchantDeskSkuDesk(service: service, journal: journal,
                                            scope: MerchantBusinessScope(realm: "desk", accountID: 7, epoch: 9),
                                            currentSession: { restartedSession })
        await restarted.reopen(productID: 3, skuID: 44, access: access, token: "synthetic-token")
        let afterRestart = try journal.intents()
        XCTAssertTrue(afterRestart.isEmpty)
        guard case .applied = restarted.phase else {
            XCTFail("original receipt clears the row")
            return
        }
        await transport.setReceiptTarget(45)
        let held = MerchantBusinessMemoryIntentStore()
        let blocked = MerchantDeskSkuDesk(service: service, journal: held, scope: scope, currentSession: { session })
        await blocked.load(productID: 3, skuID: 44, edit: MerchantDeskSkuDesk.Edit(skuName: "door", price: "88.00", stock: 2),
                           access: access, accountID: 7, token: "synthetic-token")
        await blocked.confirm(access: access, token: "synthetic-token")
        XCTAssertEqual(try held.intents().count, 1)
        let blockedSession = try MerchantBusinessSession(accountID: 7, epoch: 3, token: "synthetic-token")
        let blockedDesk = MerchantDeskSkuDesk(service: service, journal: held,
                                              scope: MerchantBusinessScope(realm: "desk", accountID: 7, epoch: 3),
                                              currentSession: { blockedSession })
        await blockedDesk.reopen(productID: 3, skuID: 44, access: access, token: "synthetic-token")
        XCTAssertEqual(try held.intents().count, 1)
        guard case .unknown = blockedDesk.phase else {
            XCTFail("other receipt target stays")
            return
        }
        let deniedJournal = MerchantBusinessMemoryIntentStore()
        let denied = MerchantDeskSkuDesk(service: service, journal: deniedJournal, scope: scope, currentSession: { session })
        await denied.load(productID: 3, skuID: 44, edit: MerchantDeskSkuDesk.Edit(skuName: "door", price: "88.00", stock: 2),
                          access: access, accountID: 7, token: "synthetic-token")
        await transport.setSaveStatus(401)
        await transport.setSaveTarget(44)
        await denied.confirm(access: access, token: "synthetic-token")
        let deniedRows = try deniedJournal.intents()
        XCTAssertEqual(deniedRows.count, 1)
        guard case .unknown = denied.phase else {
            XCTFail("unauthorized stays unknown")
            return
        }
    }

    func testProductionDeskSkuUsesTheReviewedTransport() async throws {
        let url = URL(string: "https://example.com")!
        let token = "test-token"
        let context = RuntimeDependencyContext(market: .china, baseURL: url, role: "merchant",
                                               session: try .init(accountID: 7, epoch: 1, namespace: "merchant-cn", token: token))
        let mutation = MerchantBusinessMutation.saveSku(productID: 3, skuID: 44, name: "door", price: "88.00", stock: 2,
                                                        originalPrice: "100.00", pic: "media-asset:1", bookable: false,
                                                        slotMinutes: 30, capacityPerSlot: 2, ruleVersion: 3)
        let path = try mutation.request(requestID: "grant-validation").path
        let approval = try MerchantBusinessProductionApproval(
            market: .china,
            endpoints: .init(baseURL: url, namespace: "merchant-cn", accountID: 7, paths: [path]),
            grants: [try .init(merchantID: 9, mutation: mutation)],
            reviewedPolicyVersion: "policy-1")
        let wire = DeskProductionWire()
        let factory = MerchantBusinessProductionFactory(api: try .init(baseURL: url), approval: approval, transport: wire, current: { context })
        let produced = try XCTUnwrap(factory.service(for: mutation, merchantID: 9))
        let access = try MerchantBusinessAccess(MerchantBusinessObject([
            "active": .bool(true),
            "merchant": .object(["id": .int(9)]),
            "roleCode": .string("MERCHANT_OWNER"),
            "permissions": .array([.string("merchant:project:manage"), .string("merchant:basic:read")]),
            "canManageOperators": .bool(false)
        ]))
        let scope = MerchantBusinessScope(realm: "desk", accountID: 7, epoch: 1)
        do {
            _ = try await produced.execute(mutation, requestID: "desk-req-0007", token: token)
            XCTFail("direct execute")
        } catch {
            XCTAssertEqual(error as? MerchantBusinessFailure, .disabled)
        }
        let idle = await wire.requests
        XCTAssertTrue(idle.isEmpty)
        let detail = MerchantBusinessValue.object(["productId": .int(3), "editable": .bool(true), "skus": .array([])])
        let other = MerchantBusinessMutation.saveSku(productID: 3, skuID: 44, name: "door", price: "99.00", stock: 2,
                                                     originalPrice: "100.00", pic: "media-asset:1", bookable: false,
                                                     slotMinutes: 30, capacityPerSlot: 2, ruleVersion: 3)
        let reserved = MerchantBusinessIntent(scope: scope, merchantID: 9, target: "sku:44", requestID: "desk-req-0007")
        do {
            _ = try await produced.executeDeskSku(other, requestID: "desk-req-0007", token: token, access: access, scope: scope,
                                                 reserved: reserved, detail: detail, authorizationGeneration: UUID(), check: {})
            XCTFail("empty detail")
        } catch {
            XCTAssertEqual(error as? MerchantBusinessFailure, .invalid)
        }
        let stillIdle = await wire.requests
        XCTAssertTrue(stillIdle.isEmpty)
        let present = MerchantBusinessValue.object([
            "productId": .int(3), "editable": .bool(true),
            "skus": .array([.object(["skuId": .int(44), "skuName": .string("door")])])
        ])
        do {
            _ = try await produced.executeDeskSku(mutation, requestID: "desk-req-0007", token: token,
                                                 access: access, scope: scope, reserved: reserved, detail: present,
                                                 authorizationGeneration: UUID(), check: {})
            XCTFail("production entry does not mint a ticket")
        } catch {
            XCTAssertEqual(error as? MerchantBusinessFailure, .disabled)
        }
        let afterPresent = await wire.requests
        XCTAssertTrue(afterPresent.isEmpty)
    }

    func testDeskConfirmSendsTheFrozenSkuOnTheReviewedTransport() async throws {
        let url = URL(string: "https://example.com")!
        let token = "test-token"
        let reads = DeskSkuEntryTransport()
        let readService = try MerchantBusinessService(configuration: .init(baseURL: url), readTransport: reads)
        let context = RuntimeDependencyContext(market: .china, baseURL: url, role: "merchant",
                                               session: try .init(accountID: 7, epoch: 1, namespace: "merchant-cn", token: token))
        let mutation = MerchantBusinessMutation.saveSku(productID: 3, skuID: 44, name: "door", price: "88.00", stock: 2,
                                                        originalPrice: "100.00", pic: "media-asset:1", bookable: false,
                                                        slotMinutes: 30, capacityPerSlot: 2, ruleVersion: 3)
        let path = try mutation.request(requestID: "grant-validation").path
        let approval = try MerchantBusinessProductionApproval(
            market: .china,
            endpoints: .init(baseURL: url, namespace: "merchant-cn", accountID: 7, paths: [path]),
            grants: [try .init(merchantID: 9, mutation: mutation)],
            reviewedPolicyVersion: "policy-1")
        let wire = DeskProductionWire()
        let factory = MerchantBusinessProductionFactory(api: try .init(baseURL: url), approval: approval, transport: wire, current: { context })
        let access = try MerchantBusinessAccess(MerchantBusinessObject([
            "active": .bool(true),
            "merchant": .object(["id": .int(9)]),
            "roleCode": .string("MERCHANT_OWNER"),
            "permissions": .array([.string("merchant:project:manage"), .string("merchant:basic:read")]),
            "canManageOperators": .bool(false)
        ]))
        let journal = MerchantBusinessMemoryIntentStore()
        let desk = MerchantDeskSkuDesk(service: readService, journal: journal,
                                      scope: MerchantBusinessScope(realm: "desk", accountID: 7, epoch: 1),
                                      production: { change, merchantID in
            factory.service(for: change, merchantID: merchantID)
        })
        await desk.load(productID: 3, skuID: 44, edit: MerchantDeskSkuDesk.Edit(skuName: "door", price: "88.00", stock: 2),
                        access: access, accountID: 7, token: token)
        guard case .frozen = desk.phase else {
            XCTFail("frozen")
            return
        }
        await desk.confirm(access: access, token: token)
        guard case .failed(.disabled) = desk.phase else {
            XCTFail("memory journal cannot produce")
            return
        }
        let sent = await wire.requests
        XCTAssertTrue(sent.isEmpty)
        XCTAssertTrue(try journal.intents().isEmpty)
    }

    func testDurableJournalDeskConfirmSendsTheReviewedSave() async throws {
        let url = URL(string: "https://example.com")!
        let token = "test-token"
        let reads = DeskSkuEntryTransport()
        let readService = try MerchantBusinessService(configuration: .init(baseURL: url), readTransport: reads)
        let session = try MerchantBusinessSession(accountID: 7, epoch: 1, token: token)
        let ticket = UUID()
        let context = RuntimeDependencyContext(market: .china, baseURL: url, role: "merchant",
                                               session: try .init(accountID: 7, epoch: 1, namespace: "merchant-cn", token: token))
        let mutation = MerchantBusinessMutation.saveSku(productID: 3, skuID: 44, name: "new door", price: "88.00", stock: 2,
                                                        originalPrice: "100.00", pic: "media-asset:1", bookable: false,
                                                        slotMinutes: 30, capacityPerSlot: 2, ruleVersion: 3)
        let path = try mutation.request(requestID: "grant-validation").path
        let approval = try MerchantBusinessProductionApproval(
            market: .china,
            endpoints: .init(baseURL: url, namespace: "merchant-cn", accountID: 7, paths: [path]),
            grants: [try .init(merchantID: 9, mutation: mutation)],
            reviewedPolicyVersion: "policy-1")
        let wire = DeskProductionWire()
        let factory = MerchantBusinessProductionFactory(api: try .init(baseURL: url), approval: approval, transport: wire, current: { context })
        let access = try MerchantBusinessAccess(MerchantBusinessObject([
            "active": .bool(true),
            "merchant": .object(["id": .int(9)]),
            "roleCode": .string("MERCHANT_OWNER"),
            "permissions": .array([.string("merchant:project:manage"), .string("merchant:basic:read")]),
            "canManageOperators": .bool(false)
        ]))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let journal = MerchantBusinessFileIntentStore(url: folder.appendingPathComponent("intents.json"))
        let desk = MerchantDeskSkuDesk(service: readService, journal: journal,
                                      scope: MerchantBusinessScope(realm: "desk", accountID: 7, epoch: 1),
                                      production: { change, merchantID in
            factory.service(for: change, merchantID: merchantID)
        }, currentSession: { session }, authorizationGeneration: { ticket })
        await desk.load(productID: 3, skuID: 44, edit: MerchantDeskSkuDesk.Edit(skuName: "new door", price: "88.00", stock: 2),
                        access: access, accountID: 7, token: token)
        await desk.confirm(access: access, token: token)
        guard case .applied(_, 44) = desk.phase else {
            XCTFail("durable applied")
            return
        }
        let sent = await wire.requests
        XCTAssertEqual(sent.count, 1)
        let saved = String(decoding: sent[0].httpBody ?? Data(), as: UTF8.self)
        XCTAssertTrue(saved.contains("\"skuName\":\"new door\""))
        XCTAssertTrue(try journal.intents().isEmpty)
    }

    func testLegalSkuRenameSendsTheEditedName() async throws {
        let transport = DeskSkuEntryTransport()
        let service = try MerchantBusinessService(configuration: .init(baseURL: URL(string: "https://example.com/test")!),
                                                  readTransport: transport, testingMutationTransport: transport)
        let journal = MerchantBusinessMemoryIntentStore()
        let scope = MerchantBusinessScope(realm: "desk", accountID: 7, epoch: 1)
        let access = try MerchantBusinessAccess(MerchantBusinessObject([
            "active": .bool(true),
            "merchant": .object(["id": .int(9)]),
            "roleCode": .string("MERCHANT_OWNER"),
            "permissions": .array([.string("merchant:project:manage"), .string("merchant:basic:read")]),
            "canManageOperators": .bool(false)
        ]))
        let session = try MerchantBusinessSession(accountID: 7, epoch: 1, token: "synthetic-token")
        let desk = MerchantDeskSkuDesk(service: service, journal: journal, scope: scope, currentSession: { session })
        await desk.load(productID: 3, skuID: 44, edit: MerchantDeskSkuDesk.Edit(skuName: "new door", price: "88.00", stock: 2),
                        access: access, accountID: 7, token: "synthetic-token")
        guard case .frozen(let intent) = desk.phase else {
            XCTFail("frozen rename")
            return
        }
        XCTAssertEqual(intent.skuName, "new door")
        await desk.confirm(access: access, token: "synthetic-token")
        guard case .applied = desk.phase else {
            XCTFail("rename applied")
            return
        }
        let body = await transport.saveBody
        XCTAssertTrue(body.contains("\"skuName\":\"new door\""))
        XCTAssertTrue(try journal.intents().isEmpty)
        let saves = await transport.paths.filter { $0.hasSuffix("/sku/save") }
        XCTAssertEqual(saves.count, 1)
    }

    func testReadUnauthorizedRetiresOnlyTheCapturedSession() async throws {
        let transport = DeskSkuEntryTransport()
        let service = try MerchantBusinessService(configuration: .init(baseURL: URL(string: "https://example.com/test")!),
                                                  readTransport: transport, testingMutationTransport: transport)
        let journal = MerchantBusinessMemoryIntentStore()
        let scope = MerchantBusinessScope(realm: "desk", accountID: 7, epoch: 1)
        let access = try MerchantBusinessAccess(MerchantBusinessObject([
            "active": .bool(true),
            "merchant": .object(["id": .int(9)]),
            "roleCode": .string("MERCHANT_OWNER"),
            "permissions": .array([.string("merchant:project:manage"), .string("merchant:basic:read")]),
            "canManageOperators": .bool(false)
        ]))
        let held = SessionHold()
        held.session = try MerchantBusinessSession(accountID: 7, epoch: 1, token: "synthetic-token")
        let retired = SessionHold()
        let desk = MerchantDeskSkuDesk(service: service, journal: journal, scope: scope,
                                      currentSession: { held.session },
                                      onUnauthorized: { retired.session = $0 })
        await transport.setReadUnauthorized(true)
        await desk.present(productID: 3, skuID: 44, access: access, accountID: 7, token: "synthetic-token")
        XCTAssertEqual(desk.phase, .idle)
        XCTAssertEqual(retired.session?.accountID, 7)
        retired.session = nil
        let pending = MerchantBusinessIntent(scope: scope, merchantID: 9, target: "sku:44", requestID: "desk-req-401401")
        try journal.reserve(pending)
        await desk.reopen(productID: 3, skuID: 44, access: access, token: "synthetic-token")
        guard case .unknown(let pendingID) = desk.phase else {
            XCTFail("reopen 401 stays unknown")
            return
        }
        XCTAssertEqual(pendingID, "desk-req-401401")
        XCTAssertEqual(try journal.intents().count, 1)
        XCTAssertEqual(retired.session?.accountID, 7)
        let original = try MerchantBusinessSession(accountID: 7, epoch: 1, token: "synthetic-token")
        let replacement = try MerchantBusinessSession(accountID: 7, epoch: 2, token: "synthetic-token-2")
        held.session = original
        retired.session = nil
        let laterJournal = MerchantBusinessMemoryIntentStore()
        let later = MerchantDeskSkuDesk(service: service, journal: laterJournal, scope: scope,
                                       currentSession: { held.session },
                                       onUnauthorized: { retired.session = $0 })
        await transport.setSwapSessionBeforeRead { held.session = replacement }
        await later.present(productID: 3, skuID: 44, access: access, accountID: 7, token: "synthetic-token")
        XCTAssertNil(retired.session)
        XCTAssertEqual(held.session?.epoch, 2)
        XCTAssertEqual(later.phase, .idle)
        XCTAssertEqual(try journal.intents().count, 1)
        XCTAssertTrue(try laterJournal.intents().isEmpty)
    }

    func testStalePageTokenIsNotSentAndDoesNotRetireTheCurrentSession() async throws {
        let transport = DeskSkuEntryTransport()
        let service = try MerchantBusinessService(configuration: .init(baseURL: URL(string: "https://example.com/test")!),
                                                  readTransport: transport, testingMutationTransport: transport)
        let journal = MerchantBusinessMemoryIntentStore()
        let scope = MerchantBusinessScope(realm: "desk", accountID: 7, epoch: 1)
        let access = try MerchantBusinessAccess(MerchantBusinessObject([
            "active": .bool(true),
            "merchant": .object(["id": .int(9)]),
            "roleCode": .string("MERCHANT_OWNER"),
            "permissions": .array([.string("merchant:project:manage"), .string("merchant:basic:read")]),
            "canManageOperators": .bool(false)
        ]))
        let current = try MerchantBusinessSession(accountID: 7, epoch: 1, token: "synthetic-token-b")
        let retired = SessionHold()
        let desk = MerchantDeskSkuDesk(service: service, journal: journal, scope: scope,
                                      currentSession: { current }, onUnauthorized: { retired.session = $0 })
        await desk.present(productID: 3, skuID: 44, access: access, accountID: 7, token: "synthetic-token")
        let idle = await transport.requests
        XCTAssertEqual(desk.phase, .failed(.stale))
        XCTAssertNil(retired.session)
        XCTAssertTrue(idle.isEmpty)
        let older = try MerchantBusinessSession(accountID: 7, epoch: 1, token: "synthetic-token")
        let moved = MerchantDeskSkuDesk(service: service, journal: journal,
                                       scope: MerchantBusinessScope(realm: "desk", accountID: 7, epoch: 2),
                                       currentSession: { older })
        await moved.present(productID: 3, skuID: 44, access: access, accountID: 7, token: "synthetic-token")
        let stillIdle = await transport.requests
        XCTAssertEqual(moved.phase, .failed(.stale))
        XCTAssertTrue(stillIdle.isEmpty)
    }

    func testCancelledSaveDoesNotClearTheJournalOrMarkApplied() async throws {
        let transport = DeskSkuEntryTransport()
        let service = try MerchantBusinessService(configuration: .init(baseURL: URL(string: "https://example.com/test")!),
                                                  readTransport: transport, testingMutationTransport: transport)
        let journal = MerchantBusinessMemoryIntentStore()
        let scope = MerchantBusinessScope(realm: "desk", accountID: 7, epoch: 1)
        let access = try MerchantBusinessAccess(MerchantBusinessObject([
            "active": .bool(true),
            "merchant": .object(["id": .int(9)]),
            "roleCode": .string("MERCHANT_OWNER"),
            "permissions": .array([.string("merchant:project:manage"), .string("merchant:basic:read")]),
            "canManageOperators": .bool(false)
        ]))
        let session = try MerchantBusinessSession(accountID: 7, epoch: 1, token: "synthetic-token")
        let desk = MerchantDeskSkuDesk(service: service, journal: journal, scope: scope, currentSession: { session })
        await desk.load(productID: 3, skuID: 44, edit: MerchantDeskSkuDesk.Edit(skuName: "new door", price: "88.00", stock: 2),
                        access: access, accountID: 7, token: "synthetic-token")
        await transport.setCancelDuringSend(true)
        await desk.confirm(access: access, token: "synthetic-token")
        guard case .applied = desk.phase else {
            XCTAssertEqual(try journal.intents().count, 1)
            return
        }
        XCTFail("cancelled result must not mark applied")
    }
}

private actor DeskSkuEntryTransport: MerchantBusinessTestTransport {
    var requests: [URLRequest] = []
    var failSave = false
    var receiptApplied = true
    var receiptRequestID = ""
    var saveBody = ""
    var detailRuleVersion = 3
    var saveTarget = 44
    var receiptTarget = 44
    var saveStatus = 200
    var readUnauthorized = false
    var cancelDuringSend = false
    var swapSession: (@MainActor () -> Void)?
    var paths: [String] { requests.compactMap { $0.url?.path } }
    func setFailSave(_ value: Bool) { failSave = value }
    func setReceiptApplied(_ value: Bool) { receiptApplied = value }
    func setReceiptRequestID(_ value: String) { receiptRequestID = value }
    func setDetailRuleVersion(_ value: Int) { detailRuleVersion = value }
    func setSaveTarget(_ value: Int) { saveTarget = value }
    func setReceiptTarget(_ value: Int) { receiptTarget = value }
    func setSaveStatus(_ value: Int) { saveStatus = value }
    func setReadUnauthorized(_ value: Bool) { readUnauthorized = value }
    func setCancelDuringSend(_ value: Bool) { cancelDuringSend = value }
    func setSwapSessionBeforeRead(_ value: (@MainActor () -> Void)?) { swapSession = value }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        let path = request.url?.path ?? ""
        if cancelDuringSend, path.hasSuffix("/sku/save") { withUnsafeCurrentTask { $0?.cancel() } }
        requests.append(request)
        if path.hasSuffix("/access/me") {
            let json = #"{"code":200,"data":{"active":true,"merchant":{"id":9},"roleCode":"MERCHANT_OWNER","permissions":["merchant:project:manage","merchant:basic:read"],"canManageOperators":false}}"#
            return (Data(json.utf8), 200)
        }
        if path.hasSuffix("/products/detail") {
            if let swapSession { await swapSession() }
            if readUnauthorized { return (Data(#"{"code":401,"msg":"expired","data":null}"#.utf8), 401) }
            let json = #"{"code":200,"data":{"productId":3,"editable":true,"skus":[{"skuId":44,"skuName":"door","price":88,"originalPrice":"100.00","pic":"media-asset:1","stock":2,"bookable":false,"slotMinutes":30,"capacityPerSlot":2,"ruleVersion":\#(detailRuleVersion)}]}}"#
            return (Data(json.utf8), 200)
        }
        if path.hasSuffix("/sku/save") {
            saveBody = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
            if failSave { throw URLError(.timedOut) }
            let fields = try JSONDecoder().decode(MerchantBusinessObject.self, from: request.httpBody ?? Data())
            let requestID = fields["requestId"]?.string ?? ""
            let json = #"{"code":200,"data":{"requestId":"\#(requestID)","state":"APPLIED","action":"SKU_SAVE","targetType":"pms_sku","targetId":\#(saveTarget)}}"#
            return (Data(json.utf8), saveStatus)
        }
        if path.hasSuffix("/receipt") {
            if readUnauthorized { return (Data(#"{"code":401,"msg":"expired","data":null}"#.utf8), 401) }
            let fields = try JSONDecoder().decode(MerchantBusinessObject.self, from: request.httpBody ?? Data())
            let requestID = fields["requestId"]?.string ?? receiptRequestID
            let state = receiptApplied ? "APPLIED" : "NOT_FOUND"
            let extra = receiptApplied ? #","action":"SKU_SAVE","targetType":"pms_sku","targetId":\#(receiptTarget)"# : ""
            let json = #"{"code":200,"data":{"requestId":"\#(requestID)","state":"\#(state)"\#(extra)}}"#
            return (Data(json.utf8), 200)
        }
        return (Data(#"{"code":404,"msg":"missing","data":null}"#.utf8), 200)
    }
}

private final class SessionHold: @unchecked Sendable {
    var session: MerchantBusinessSession?
}

private actor DeskProductionWire: HTTPTransport {
    var requests: [URLRequest] = []
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        let fields = try JSONDecoder().decode(MerchantBusinessObject.self, from: request.httpBody ?? Data())
        let requestID = fields["requestId"]?.string ?? ""
        let json = #"{"code":200,"data":{"requestId":"\#(requestID)","state":"APPLIED","action":"SKU_SAVE","targetType":"pms_sku","targetId":44}}"#
        return (Data(json.utf8), 200)
    }
}
