import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class FreeExploreSaleHTTPFake: HTTPTransport {
    var requests: [URLRequest] = []
    var response = "{\"code\":200}"
    func send(_ request: URLRequest) async throws -> (Data, Int) { requests.append(request); return (Data(response.utf8), 200) }
}

/// F10: free exploration may publish for recruitment without a ticket price, then publish for sale
/// once every merchant slot is supplied. Neutral synthetic fixtures only.
@MainActor final class ProjectEditDraftFreeExploreTests: XCTestCase {
    private func draft(_ product: ProjectEditProduct, price: String) -> ProjectEditDraft {
        var d = ProjectEditSyntheticFixtures.draft(product: product); d.tickets[0].price = price; return d
    }
    private func priceIssue(_ d: ProjectEditDraft) -> Bool {
        ProjectEditValidation.issues(d).contains { $0.id == "price\(d.tickets[0].id)" }
    }
    private func json(_ text: String) throws -> ProjectEditJSON { try JSONDecoder().decode(ProjectEditJSON.self, from: Data(text.utf8)) }

    func testFreeExploreAllowsEmptyPriceButCityStillRequiresIt() {
        XCTAssertFalse(priceIssue(draft(.freeExplore, price: "")))
        XCTAssertFalse(priceIssue(draft(.freeExplore, price: "  ")))
        XCTAssertTrue(priceIssue(draft(.city, price: "")))
    }
    func testFreeExploreStillRejectsMalformedOrNegativePrice() {
        XCTAssertTrue(priceIssue(draft(.freeExplore, price: "abc")))
        XCTAssertTrue(priceIssue(draft(.freeExplore, price: "-1")))
        XCTAssertFalse(priceIssue(draft(.freeExplore, price: "0")))
        XCTAssertFalse(priceIssue(draft(.freeExplore, price: "38.5")))
    }
    func testPayloadSendsNullForMissingFreeExplorePriceAndNeverZero() throws {
        let payload = try ProjectEditContract.payload(draft(.freeExplore, price: ""), topicID: nil, scope: .full)
        let ticket = try XCTUnwrap(payload["tickets"]?.array?.first?.object)
        XCTAssertEqual(ticket["price"], .null)
        let priced = try ProjectEditContract.payload(draft(.freeExplore, price: "12.5"), topicID: nil, scope: .full)
        XCTAssertEqual(priced["tickets"]?.array?.first?.object?["price"], .number(Decimal(string: "12.5")!))
        XCTAssertThrowsError(try ProjectEditContract.payload(draft(.city, price: ""), topicID: nil, scope: .full))
    }
    func testReadinessDecodesExactServerShape() throws {
        let value = try FreeExploreSaleReadiness(json(#"{"topicId":71,"lifecycle":1,"totalSlots":3,"filledSlots":1,"openSlots":2,"canFillPrice":false,"canPublish":false}"#), expectedTopicID: 71)
        XCTAssertEqual(value.openSlots, 2); XCTAssertEqual(value.priceState, .awaitingSlots(open: 2))
        XCTAssertEqual(value.priceState.openSlotsText(zh: true), "还有 2 个位置待承接")
        XCTAssertTrue(value.priceState.disablesPriceFields)
        XCTAssertThrowsError(try FreeExploreSaleReadiness(json(#"{"topicId":72,"lifecycle":1,"totalSlots":3,"filledSlots":1,"openSlots":2,"canFillPrice":false,"canPublish":false}"#), expectedTopicID: 71))
        XCTAssertThrowsError(try FreeExploreSaleReadiness(json(#"{"topicId":71,"lifecycle":1,"totalSlots":3}"#), expectedTopicID: 71))
    }
    func testPriceStateFollowsLifecycle() {
        func state(_ lifecycle: Int, fill: Bool = true, publish: Bool = true) -> FreeExplorePriceState {
            FreeExplorePriceState(FreeExploreSaleReadiness(topicID: 1, lifecycle: lifecycle, totalSlots: 2, filledSlots: 2, openSlots: 0, canFillPrice: fill, canPublish: publish))
        }
        XCTAssertEqual(FreeExplorePriceState(nil), .notApplicable)
        XCTAssertEqual(state(2), .priceEntry(canPublish: true)); XCTAssertFalse(state(2).disablesPriceFields)
        XCTAssertEqual(state(2, publish: false), .priceEntry(canPublish: false))
        XCTAssertEqual(state(2, fill: false), .awaitingSlots(open: 0))
        XCTAssertEqual(state(3), .frozen); XCTAssertTrue(state(3).disablesPriceFields)
        XCTAssertEqual(state(0), .notApplicable)
    }
    func testPublishRequestNeedsServerTicketIDAndEveryPrice() throws {
        var d = draft(.freeExplore, price: ""); d.tickets[0].localMetadata["id"] = .number(501)
        XCTAssertThrowsError(try FreeExplorePublishRequest(topicID: 71, tickets: d.tickets, prices: [:]))
        let request = try FreeExplorePublishRequest(topicID: 71, tickets: d.tickets, prices: [d.tickets[0].id: "19.90"])
        XCTAssertEqual(request.fields["topicId"], .number(71))
        XCTAssertEqual(request.fields["ticketPrices"], .object(["501": .number(Decimal(string: "19.90")!)]))
        XCTAssertThrowsError(try FreeExplorePublishRequest(topicID: 71, tickets: d.tickets, prices: [d.tickets[0].id: "1.234"]))
        d.tickets[0].localMetadata["id"] = nil
        XCTAssertThrowsError(try FreeExplorePublishRequest(topicID: 71, tickets: d.tickets, prices: [d.tickets[0].id: "1"]))
        XCTAssertTrue(request.acknowledged(try json(#"{"topicId":71,"lifecycle":3}"#)))
        XCTAssertFalse(request.acknowledged(try json(#"{"topicId":71,"lifecycle":2}"#)))
    }
    func testSelfSupplySlotsAreRecruitingChaptersWithServerIDs() {
        var d = ProjectEditSyntheticFixtures.draft(product: .freeExplore)
        var open = ProjectEditChapter(); open.name = "示例站点"; open.preserved["recruitEnabled"] = .number(1); open.preserved["id"] = .number(31)
        var unsaved = ProjectEditChapter(); unsaved.preserved["recruitEnabled"] = .number(1)
        d.chapters += [open, unsaved]
        XCTAssertEqual(d.selfSupplySlots, [CoopFlowSelfSupplySlot(chapterID: 31, name: "示例站点")])
        d.product = .city
        XCTAssertTrue(d.selfSupplySlots.isEmpty)
    }
    func testDormantGrantsNeverSendPublishOrSelfSupply() async throws {
        let transport = FreeExploreSaleHTTPFake()
        let session = PublishingSession(namespace: "fixture-cn", accountID: 7, epoch: UUID(), role: "member", region: .china)
        let credentials = try PublishingCredentials(session: session, token: "synthetic-token")
        let client = PublisherLifecycleHTTP(configuration: try .init(baseURL: URL(string: "https://example.com")!), transport: transport, credentials: { credentials })
        XCTAssertFalse(client.canPublishForSale); XCTAssertFalse(client.canSelfSupply)
        let request = try FreeExplorePublishRequest(topicID: 71, ticketPrices: [501: 10])
        let outcome = try await client.publishForSale(request)
        XCTAssertEqual(outcome, .notSent)
        let supply = try CoopFlowSelfSupplyRequest(topicID: 71, chapterID: 31, perk: .init(name: "示例权益", redeemRule: "到店出示", validEnd: "2030-12-31", capacity: 10))
        do { _ = try await client.selfSupply(supply); XCTFail("dormant grant sent a write") } catch { XCTAssertEqual(error as? CoopFlowFailure, .disabled) }
        do { _ = try await client.saleReadiness(topicID: 71); XCTFail("dormant read") } catch { XCTAssertEqual(error as? PublisherLifecycleError, .unavailable) }
        XCTAssertTrue(transport.requests.isEmpty)
    }
    func testGrantedPublishPostsExactJSONAndReadinessUsesGET() async throws {
        let transport = FreeExploreSaleHTTPFake()
        let session = PublishingSession(namespace: "fixture-cn", accountID: 7, epoch: UUID(), role: "member", region: .china)
        let credentials = try PublishingCredentials(session: session, token: "synthetic-token")
        let config = try APIConfiguration(baseURL: URL(string: "https://example.com")!)
        let reads = try OperationEndpointApproval(baseURL: config.baseURL, namespace: "fixture-cn", accountID: 7, paths: [FreeExploreSaleRoute.readinessPath])
        let sale = try OperationEndpointApproval(baseURL: config.baseURL, namespace: "fixture-cn", accountID: 7, paths: [FreeExploreSaleRoute.publishPath])
        let client = PublisherLifecycleHTTP(configuration: config, transport: transport, grants: .init(reads: reads, freeExploreSale: sale), credentials: { credentials })
        transport.response = #"{"code":200,"data":{"topicId":71,"lifecycle":2,"totalSlots":2,"filledSlots":2,"openSlots":0,"canFillPrice":true,"canPublish":true}}"#
        let readiness = try await client.saleReadiness(topicID: 71)
        XCTAssertEqual(readiness.priceState, .priceEntry(canPublish: true))
        XCTAssertEqual(transport.requests.last?.httpMethod, "GET")
        XCTAssertEqual(transport.requests.last?.url?.query, "topicId=71")
        transport.response = #"{"code":200,"msg":"ok","data":{"topicId":71,"lifecycle":3}}"#
        let outcome = try await client.publishForSale(try FreeExplorePublishRequest(topicID: 71, ticketPrices: [501: 10]))
        XCTAssertEqual(outcome, .acknowledged(message: "ok", newTopicID: nil))
        let post = try XCTUnwrap(transport.requests.last)
        XCTAssertEqual(post.url?.path, "/api/topic/fe/publish-for-sale"); XCTAssertEqual(post.httpMethod, "POST")
        let body = try JSONDecoder().decode(ProjectEditJSON.self, from: try XCTUnwrap(post.httpBody))
        XCTAssertEqual(body, .object(["topicId": .number(71), "ticketPrices": .object(["501": .number(10)])]))
    }
}
