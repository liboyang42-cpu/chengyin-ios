import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class WalletRecordingTransport: HTTPTransport {
    var requests: [URLRequest] = []
    var handler: (URLRequest) async throws -> (Data, Int)
    init(_ handler: @escaping (URLRequest) async throws -> (Data, Int)) { self.handler = handler }
    convenience init(_ payload: String, status: Int = 200) {
        self.init { _ in (Data(payload.utf8), status) }
    }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); return try await handler(request)
    }
}
@MainActor final class WalletCommerceTests: XCTestCase {
    private func config() throws -> APIConfiguration { try .init(baseURL: URL(string: "https://example.com")!) }
    private func decode<T: Decodable>(_ type: T.Type, _ string: String) throws -> T { try JSONDecoder().decode(type, from: Data(string.utf8)) }
    private func service(_ transport: WalletRecordingTransport) throws -> WalletCommerceService { try .init(configuration: config(), transport: transport) }
    private func fields(_ request: URLRequest) -> String { String(data: request.httpBody ?? Data(), encoding: .utf8) ?? "" }
    private func scope() -> WalletCommerceScope { .init(namespace: "synthetic", accountID: 9, epoch: UUID()) }
    func testMissingAmountAndCurrencyNeverBecomeZero() throws {
        let row = try decode(WalletLedgerRow.self, #"{"id":1,"changeType":1}"#)
        XCTAssertNil(row.changeBalance); XCTAssertNil(row.currency)
        XCTAssertNil(row.signedText(points: false, income: true))
        let preview = try decode(WalletCheckoutPreview.self, "{}")
        XCTAssertNil(preview.requiredPoints); XCTAssertNil(preview.hasEnoughPoints)
    }
    func testDecimalStringsAndDirectionDoNotDoubleSignOrImplyStatus() throws {
        let row = try decode(WalletLedgerRow.self, #"{"id":1,"changeBalance":"-1.25","changeType":2,"eventType":4}"#)
        XCTAssertEqual(row.signedText(points: false, income: true), "−1.25")
        XCTAssertEqual(row.incomeDirection, .expense) // eventType never decides direction.
        let unknown = try decode(WalletLedgerRow.self, #"{"id":2,"changeBalance":8}"#)
        XCTAssertEqual(unknown.incomeDirection, .unknown)
        XCTAssertEqual(unknown.assetDirection, .income)
        XCTAssertThrowsError(try decode(WalletAmount.self, #""12junk""#))
    }
    func testInvalidStageIsNotEmptySuccessfulWallet() throws {
        for source in ["{}", #"{"pendingSettlement":0,"disputed":0,"withdrawable":0}"#,
                       #"{"pendingSettlement":-1,"disputed":0,"withdrawable":0,"complaintPeriod":[]}"#,
                       #"{"pendingSettlement":0,"disputed":0,"withdrawable":0,"complaintPeriod":[{"amount":1,"availableDate":"2026-02-30"}]}"#] {
            XCTAssertThrowsError(try decode(WalletFundsStages.self, source))
        }
        let value = try decode(WalletFundsStages.self, #"{"pendingSettlement":0,"disputed":0,"withdrawable":0,"complaintPeriod":[],"amountsKnown":false}"#)
        XCTAssertEqual(value.withdrawable.value, 0); XCTAssertFalse(value.amountsKnown)
    }
    func testStagesJSONAndLegacyArraysHaveNoInventedPagination() async throws {
        let fake = WalletRecordingTransport(#"{"code":200,"data":[]}"#)
        _ = try await service(fake).ledger(.balance, token: "fake")
        XCTAssertEqual(fake.requests.last?.url?.path, "/api/balance/list")
        XCTAssertFalse(fields(fake.requests[0]).contains("pageNum"))
        do { _ = try await service(fake).ledger(.balance, page: 2, token: "fake"); XCTFail() } catch {}
        XCTAssertEqual(fake.requests.count, 1)
        fake.handler = { _ in (Data(#"{"code":200,"data":{"pendingSettlement":0,"disputed":0,"withdrawable":0,"complaintPeriod":[]}}"#.utf8), 200) }
        _ = try await service(fake).stages(token: "fake")
        XCTAssertEqual(fake.requests.last?.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(fields(fake.requests.last!), "{}")
    }
    func testTruePagingAndIncomeEventFilter() async throws {
        let fake = WalletRecordingTransport(#"{"code":200,"data":{"rows":[],"total":"51"}}"#)
        let page = try await service(fake).ledger(.income(.brand), page: 3, pageSize: 20, token: "fake")
        XCTAssertEqual(page.total, 51); XCTAssertEqual(page.page, 3)
        let body = fields(fake.requests[0])
        XCTAssertTrue(body.contains("name=\"eventType\"\r\n\r\n2"))
        XCTAssertTrue(body.contains("name=\"pageNum\"\r\n\r\n3"))
        XCTAssertFalse(body.contains("change_type"))
        _ = try await service(fake).ledger(.points, changeType: 2, token: "fake")
        XCTAssertEqual(fake.requests.last?.url?.path, "/api/user/points/list")
        XCTAssertFalse(fields(fake.requests.last!).contains("change_type"))
    }
    func testWithdrawalEnvelopeShapesMaskingAndApprovalNotPayout() async throws {
        let row = #"{"id":1,"withdrawalAmount":5,"status":1,"bankAccount":"1234567890"}"#
        for payload in ["[\(row)]", "{\"rows\":[\(row)]}", "{\"list\":[\(row)]}"] {
            let fake = WalletRecordingTransport("{\"code\":200,\"data\":\(payload)}")
            let result = try await service(fake).withdrawals(token: "fake")
            XCTAssertEqual(result.rows[0].maskedAccount, "•••• 7890")
            XCTAssertEqual(result.rows[0].statusKey, "wallet.approved")
            XCTAssertNil(fake.requests[0].httpBody); XCTAssertNil(result.page)
        }
        XCTAssertThrowsError(try decode(WalletWithdrawalRecord.self, #"{"id":1,"amount":1,"status":4}"#))
        XCTAssertEqual(WalletAddressReference.mask("12"), "••••")
    }
    func testPointsCeilAndUnknownSubtotal() throws {
        let preview = try decode(WalletCheckoutPreview.self, #"{"totalAmount":"8.01","pointBalance":8}"#)
        XCTAssertEqual(preview.requiredPoints, 9); XCTAssertEqual(preview.hasEnoughPoints, false)
        let item = try decode(WalletCartItem.self, #"{"id":1,"productId":2,"skuId":3,"quantity":2}"#)
        XCTAssertNil(item.subtotalPoints)
    }
    func testCommandWireAndDuplicateIDs() throws {
        XCTAssertEqual(try WalletCommerceCommand.add(productID: 1, skuID: 2, quantity: 3).fields(),
                       ["product_id":"1", "sku_id":"2", "quantity":"3", "is_buy":"0"])
        XCTAssertEqual(WalletCommerceCommand.add(productID: 1, skuID: 2, quantity: 1).path, "api/cart/cart/add")
        XCTAssertThrowsError(try WalletCommerceCommand.redeem(cartIDs: [1,1], remark: "", addressID: 2).fields())
        XCTAssertThrowsError(try WalletCommerceCommand.update(cartID: 1, skuID: 2, quantity: 0).fields())
    }
    func testBusinessErrorsAndMalformedTableAreNotEmpty() async throws {
        for payload in [#"{"code":401,"data":[]}"#, #"{"code":500,"data":[]}"#, #"{"code":200,"data":{}}"#] {
            do { _ = try await service(WalletRecordingTransport(payload)).ledger(.points, token: "fake"); XCTFail() } catch {}
        }
    }
    func testReaderDiscardsSwitchedAccount() async throws {
        var active: WalletCommerceScope? = scope()
        let fake = WalletRecordingTransport { _ in
            active = nil
            return (Data(#"{"code":200,"data":[]}"#.utf8), 200)
        }
        let reader = WalletCommerceReader(service: try service(fake)) { active.map { ($0, "fake") } }
        do { _ = try await reader.read { try await $0.ledger(.balance, token: $1) }; XCTFail() }
        catch { XCTAssertEqual(error as? WalletCommerceSafetyError, .staleSession) }
    }
    func testClosedGateMakesNoRequest() async throws {
        let active = scope(); let fake = WalletRecordingTransport(#"{"code":200}"#)
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let adapter = WalletCommerceDormantAdapter(configuration: try config(), transport: fake,
                         journal: OperationDefaultsJournal(defaults: defaults), currentScope: { active })
        let review = try adapter.review(.delete(cartID: 1))
        do { _ = try await adapter.execute(review, token: "fake"); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        XCTAssertTrue(fake.requests.isEmpty)
    }
    func testAmbiguousOutcomePersistsAcrossRestartAndEpoch() async throws {
        var active = scope(); let first = active
        let fake = WalletRecordingTransport { _ in throw URLError(.timedOut) }
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let journal = OperationDefaultsJournal(defaults: defaults)
        let approval = try OperationEndpointApproval(baseURL: config().baseURL, namespace: active.namespace, accountID: active.accountID, paths: ["api/cart/delete"])
        let adapter = WalletCommerceDormantAdapter(configuration: try config(), transport: fake, journal: journal,
                         approval: approval, enableReviewedWrites: true, currentScope: { active })
        let review = try adapter.review(.delete(cartID: 1))
        do { _ = try await adapter.execute(review, token: "fake"); XCTFail() } catch {}
        active = .init(namespace: first.namespace, accountID: first.accountID, epoch: UUID())
        let restarted = WalletCommerceDormantAdapter(configuration: try config(), transport: fake,
                            journal: OperationDefaultsJournal(defaults: defaults), approval: approval,
                            enableReviewedWrites: true, currentScope: { active })
        XCTAssertThrowsError(try restarted.review(.delete(cartID: 2)))
        XCTAssertEqual(fake.requests.count, 1)
        let journalText = String(describing: defaults.dictionaryRepresentation())
        XCTAssertFalse(journalText.contains("fake")); XCTAssertFalse(journalText.contains("remark"))
    }
    func testMalformedRedemptionReceiptKeepsLock() async throws {
        let active = scope(); let fake = WalletRecordingTransport(#"{"code":200,"data":null}"#)
        let journal = OperationDefaultsJournal(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let approval = try OperationEndpointApproval(baseURL: config().baseURL, namespace: active.namespace, accountID: active.accountID, paths: ["api/cart/order/settlement"])
        let adapter = WalletCommerceDormantAdapter(configuration: try config(), transport: fake, journal: journal,
                         approval: approval, enableReviewedWrites: true, currentScope: { active })
        let preview = try decode(WalletCheckoutPreview.self, #"{"productAmount":1,"deliveryFee":0,"taxFee":0,"totalAmount":1,"pointBalance":2,"productList":[{"id":1,"productId":2,"skuId":3,"quantity":1,"price":1}],"address":{"id":4}}"#)
        let review = try adapter.review(.redeem(cartIDs: [1], remark: "", addressID: 4), snapshot: WalletCheckoutSnapshot(scope: active, cartIDs: [1], preview: preview, created: Date()))
        do { _ = try await adapter.execute(review, token: "fake"); XCTFail() } catch {}
        XCTAssertThrowsError(try adapter.review(.delete(cartID: 1)))
    }
    func testSyntheticSourceTasksExcludeSpendRules() async throws {
        let service = WalletCommerceService(configuration: try config(), transport: WalletCommerceSyntheticTransport())
        let tasks = try await service.pointsTasks(token: "fake")
        XCTAssertEqual(tasks.map(\.id), [50])
    }
    func testPagerFailureRetriesSamePageAndDoesNotReplaceEarlierRows() async throws {
        let active = scope(); var calls = 0
        let fake = WalletRecordingTransport { request in
            calls += 1
            if calls == 2 { throw URLError(.timedOut) }
            let id = calls == 1 ? 1 : 2
            return (Data("{\"code\":200,\"data\":{\"rows\":[{\"id\":\(id),\"changePoints\":1}],\"total\":2}}".utf8), 200)
        }
        let reader = WalletCommerceReader(service: try service(fake)) { (active, "fake") }
        let pager = WalletLedgerPager()
        await pager.load(reader: reader, kind: .points)
        XCTAssertEqual(pager.rows.map(\.id), [1]); XCTAssertTrue(pager.hasMore)
        await pager.load(reader: reader, kind: .points)
        XCTAssertTrue(pager.failed); XCTAssertEqual(pager.rows.map(\.id), [1])
        await pager.load(reader: reader, kind: .points)
        XCTAssertFalse(pager.failed); XCTAssertEqual(pager.rows.map(\.id), [1,2]); XCTAssertFalse(pager.hasMore)
        XCTAssertTrue(fields(fake.requests[1]).contains("name=\"pageNum\"\r\n\r\n2"))
        XCTAssertTrue(fields(fake.requests[2]).contains("name=\"pageNum\"\r\n\r\n2"))
    }
    func testStaleReviewCannotDispatch() async throws {
        var active = scope(); let fake = WalletRecordingTransport(#"{"code":200}"#)
        let approval = try OperationEndpointApproval(baseURL: config().baseURL, namespace: active.namespace, accountID: active.accountID, paths: ["api/cart/delete"])
        let adapter = WalletCommerceDormantAdapter(configuration: try config(), transport: fake,
            journal: OperationDefaultsJournal(defaults: UserDefaults(suiteName: UUID().uuidString)!),
            approval: approval, enableReviewedWrites: true, currentScope: { active })
        let review = try adapter.review(.delete(cartID: 1))
        active = .init(namespace: active.namespace, accountID: active.accountID, epoch: UUID())
        do { _ = try await adapter.execute(review, token: "fake"); XCTFail() }
        catch { XCTAssertEqual(error as? WalletCommerceSafetyError, .staleSession) }
        XCTAssertTrue(fake.requests.isEmpty)
    }
    func testSuccessfulRedemptionReturnsOnlyOrderReference() async throws {
        let active = scope(); let fake = WalletRecordingTransport(#"{"code":200,"data":"90"}"#)
        let approval = try OperationEndpointApproval(baseURL: config().baseURL, namespace: active.namespace, accountID: active.accountID, paths: ["api/cart/order/settlement"])
        let adapter = WalletCommerceDormantAdapter(configuration: try config(), transport: fake,
            journal: OperationDefaultsJournal(defaults: UserDefaults(suiteName: UUID().uuidString)!),
            approval: approval, enableReviewedWrites: true, currentScope: { active })
        let preview = try decode(WalletCheckoutPreview.self, #"{"productAmount":1,"deliveryFee":0,"taxFee":0,"totalAmount":1,"pointBalance":2,"productList":[{"id":1,"productId":2,"skuId":3,"quantity":1,"price":1}],"address":{"id":4}}"#)
        let snapshot = WalletCheckoutSnapshot(scope: active, cartIDs: [1], preview: preview, created: Date())
        let review = try adapter.review(.redeem(cartIDs: [1], remark: "", addressID: 4), snapshot: snapshot)
        let reference = try await adapter.execute(review, token: "fake")
        XCTAssertEqual(reference, 90)
        XCTAssertEqual(fake.requests[0].url?.path, "/api/cart/order/settlement")
        XCTAssertNoThrow(try adapter.review(.delete(cartID: 1)))
    }

    func testReadGrantRejectsMutationEvenWhenPathIsApproved() async throws {
        let active = scope(); let fake = WalletRecordingTransport(#"{"code":200}"#)
        let configuration = try config()
        let approval = try OperationEndpointApproval(baseURL: configuration.baseURL, namespace: active.namespace,
            accountID: active.accountID, paths: ["api/cart/order/settlement"])
        let transport = WalletCommerceApprovedReadTransport(configuration: configuration, approval: approval, transport: fake, currentSession: { (active, "fake") })
        let request = try AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent("api/cart/order/settlement"), fields: [:], token: "fake")
        do { _ = try await transport.send(request, scope: active, token: "fake"); XCTFail() } catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        XCTAssertTrue(fake.requests.isEmpty)
    }
    func testReadGrantRejectsDifferentAccount() async throws {
        let active = scope(); let fake = WalletRecordingTransport(#"{"code":200,"data":[]}"#)
        let configuration = try config()
        let approval = try OperationEndpointApproval(baseURL: configuration.baseURL, namespace: active.namespace,
            accountID: active.accountID + 1, paths: ["api/balance/list"])
        let transport = WalletCommerceApprovedReadTransport(configuration: configuration, approval: approval, transport: fake, currentSession: { (active, "fake") })
        let request = try AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent("api/balance/list"), fields: [:], token: "fake")
        do { _ = try await transport.send(request, scope: active, token: "fake"); XCTFail() } catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        XCTAssertTrue(fake.requests.isEmpty)
    }
    func testUnauthorizedReadInvokesCurrentAccountCallback() async throws {
        let active = scope(); var expired: WalletCommerceScope?
        let reader = WalletCommerceReader(service: try service(WalletRecordingTransport(#"{"code":401}"#, status: 401)),
            onUnauthorized: { expired = $0 }, session: { (active, "fake") })
        do { _ = try await reader.read { try await $0.ledger(.balance, token: $1) }; XCTFail() } catch {}
        XCTAssertEqual(expired, active)
    }

    func testWalletApprovedReadRejectsStaleBindingBeforeDispatch() async throws {
        let old = scope(), configuration = try config()
        let variants = [
            WalletCommerceScope(namespace: old.namespace, accountID: old.accountID + 1, epoch: old.epoch),
            WalletCommerceScope(namespace: old.namespace, accountID: old.accountID, epoch: UUID()),
            WalletCommerceScope(namespace: "other", accountID: old.accountID, epoch: old.epoch),
            old
        ]
        for (index, current) in variants.enumerated() {
            let token = index == variants.count - 1 ? "new-token" : "old-token"
            let fake = WalletRecordingTransport(#"{"code":200,"data":[]}"#)
            let approval = try OperationEndpointApproval(baseURL: configuration.baseURL, namespace: current.namespace, accountID: current.accountID, paths: ["api/balance/list"])
            let guarded = WalletCommerceApprovedReadTransport(configuration: configuration, approval: approval, transport: fake, currentSession: { (current, token) })
            let request = try AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent("api/balance/list"), fields: [:], token: "old-token")
            do { _ = try await guarded.send(request, scope: old, token: "old-token"); XCTFail() }
            catch { XCTAssertEqual(error as? WalletCommerceSafetyError, .staleSession) }
            XCTAssertTrue(fake.requests.isEmpty)
        }
    }
    func testWalletReaderPropagatesBindingAndBareRequestsFailClosed() async throws {
        let active = scope(), configuration = try config(), fake = WalletRecordingTransport(#"{"code":200,"data":[]}"#)
        let approval = try OperationEndpointApproval(baseURL: configuration.baseURL, namespace: active.namespace, accountID: active.accountID, paths: ["api/balance/list"])
        let guarded = WalletCommerceApprovedReadTransport(configuration: configuration, approval: approval, transport: fake, currentSession: { (active, "fake") })
        let service = WalletCommerceService(configuration: configuration, transport: guarded)
        let reader = WalletCommerceReader(service: service, session: { (active, "fake") })
        _ = try await reader.read { try await $0.ledger(.balance, token: $1) }
        XCTAssertEqual(fake.requests.count, 1)
        do { _ = try await service.ledger(.balance, token: "fake"); XCTFail("Unbound service escaped") } catch {}
        let forged = try AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent("api/balance/list"), fields: [:], token: "other")
        do { _ = try await guarded.send(forged, scope: active, token: "fake"); XCTFail() } catch {}
        do { _ = try await guarded.send(forged); XCTFail() } catch {}
        XCTAssertEqual(fake.requests.count, 1)
    }

    func testWalletApprovedReadRejectsSessionChangeDuringResponse() async throws {
        let old = scope(), configuration = try config()
        var current: (scope: WalletCommerceScope, token: String)? = (old, "fake")
        let fake = WalletRecordingTransport { _ in current = nil; return (Data(#"{"code":200,"data":[]}"#.utf8), 200) }
        let approval = try OperationEndpointApproval(baseURL: configuration.baseURL, namespace: old.namespace, accountID: old.accountID, paths: ["api/balance/list"])
        let guarded = WalletCommerceApprovedReadTransport(configuration: configuration, approval: approval, transport: fake, currentSession: { current })
        let request = try AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent("api/balance/list"), fields: [:], token: "fake")
        do { _ = try await guarded.send(request, scope: old, token: "fake"); XCTFail() }
        catch { XCTAssertEqual(error as? WalletCommerceSafetyError, .staleSession) }
        XCTAssertEqual(fake.requests.count, 1)
    }

}
