import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private actor LifecycleFakeHTTP: HTTPTransport {
    var replies: [String]; var requests: [URLRequest] = []
    init(_ replies: [String]) { self.replies = replies }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        guard !replies.isEmpty else { throw URLError(.timedOut) }
        return (Data(replies.removeFirst().utf8), 200)
    }
}
@MainActor private final class LifecycleJournal: OperationPendingJournal {
    var records: [String: OperationPendingRecord] = [:]
    func pending(ownerKey: String, targetKey: String) throws -> OperationPendingRecord? { records[ownerKey + targetKey] }
    func write(_ record: OperationPendingRecord) throws { records[record.ownerKey + record.targetKey] = record }
    func clear(_ record: OperationPendingRecord) throws { records.removeValue(forKey: record.ownerKey + record.targetKey) }
}
@MainActor private final class LifecycleCenterReader: CreatorContentReading {
    let scope = UUID(); let isConfigured = true; let isAuthenticated = true; let isOfflineExample = true
    var status = "not_applied"; var count = 0
    func center() async throws -> CreatorContentCenter { count += 1; return try JSONDecoder().decode(CreatorContentCenter.self, from: Data("{\"applyStatus\":\"\(status)\"}".utf8)) }
    func projects(query: CreatorContentQuery) async throws -> CreatorContentProjectPage { .init(rows: [], total: 0) }
}
@MainActor final class PublisherLifecycleTests: XCTestCase {
    let floor = "{\"code\":200,\"data\":{\"priceMin\":12.5,\"lineup\":[]}}"
    let paid = "{\"code\":200,\"data\":{\"paidPlayers\":3}}"
    private func setup(_ transport: LifecycleFakeHTTP, active: Bool = true) throws -> PublisherLifecycleHTTP {
        let config = try APIConfiguration(baseURL: URL(string: "https://example.com/test/")!)
        let session = PublishingSession(namespace: "fixture", accountID: 7, epoch: UUID(), role: "member", region: .china)
        let credentials = try PublishingCredentials(session: session, token: "fixture-token")
        let grant = try OperationEndpointApproval(baseURL: config.baseURL, namespace: "fixture", accountID: 7, paths: ["api/topic/pricing/preview", "api/topic/pricing/confirm", "api/topic/cancel_preview", "api/activity/cancel_preview", "api/topic/cancel", "api/activity/cancel", "api/topic/xp-budget", "api/topic/transfer-to-club", "api/topic/beta/graduate", "api/creator/apply", "api/club/detail", "api/merchant/public-detail"])
        return PublisherLifecycleHTTP(configuration: config, transport: transport, grants: active ? .init(reads: grant, pricing: grant, cancellationRefunds: grant, ownership: grant, graduation: grant, creatorApplication: grant) : .dormant, credentials: { credentials })
    }
    private func coordinator(_ client: PublisherLifecycleHTTP, journal: LifecycleJournal? = nil) -> PublisherLifecycleCoordinator {
        PublisherLifecycleCoordinator(client: client, journal: journal ?? LifecycleJournal()) { resource, _ in
            PublisherAuthority(resource: resource, ownerAccountID: 7, revision: "fixture-server-version-1", beta: true, eligibleClubIDs: [9])
        }
    }
    func testMissingFloorNeverBecomesZero() throws {
        XCTAssertThrowsError(try PublisherPricingPreview(.object([:])))
        XCTAssertThrowsError(try PublisherPricingPreview(.object(["priceMin": .string("0")])))
        XCTAssertEqual(try PublisherPricingPreview(.object(["priceMin": .number(0)])).minimum, 0)
    }
    func testPricingExactPreviewAndConfirmBodies() async throws {
        let transport = LifecycleFakeHTTP([floor, floor, "{\"code\":200,\"msg\":\"accepted\"}"])
        let client = try setup(transport); let owner = coordinator(client)
        let input = try PublisherPricingInput(topicID: 4, subtype: .guided, leadCost: 2, teamSize: 3)
        let review = try await owner.prepare(.pricing(input, 13))
        let outcome = await owner.confirm(review, consequentialApproval: true)
        XCTAssertEqual(outcome, .acknowledged(message: "accepted", newTopicID: nil))
        let requests = await transport.requests
        let first = try JSONDecoder().decode([String: ProjectEditJSON].self, from: XCTUnwrap(requests[0].httpBody))
        let last = try JSONDecoder().decode([String: ProjectEditJSON].self, from: XCTUnwrap(requests.last?.httpBody))
        XCTAssertEqual(first["subType"], .string("guided")); XCTAssertEqual(first["teamSize"], .number(3))
        XCTAssertNil(last["subType"]); XCTAssertEqual(last["guidedPrice"], .number(13)); XCTAssertNil(last["selfPrice"])
    }
    func testCancellationUsesActualPaidPlayersAndServerMessage() async throws {
        let server = "已核销票需人工跟进"
        let transport = LifecycleFakeHTTP([paid, paid, "{\"code\":200,\"msg\":\"\(server)\"}"])
        let owner = coordinator(try setup(transport))
        let review = try await owner.prepare(.cancel(PublishedResource(kind: .activity, value: 5), reason: "Weather", scope: nil))
        XCTAssertEqual(review.paidPlayers, 3)
        let outcome = await owner.confirm(review, consequentialApproval: true)
        XCTAssertEqual(outcome, .acknowledged(message: server, newTopicID: nil))
        let requests = await transport.requests
        XCTAssertEqual(requests.last?.url?.path, "/test/api/activity/cancel")
        let body = String(data: requests.last!.httpBody!, encoding: .utf8)!
        XCTAssertTrue(body.contains("name=\"reason\"\r\n\r\nWeather\r\n"))
    }
    func testMissingRefundCountBlocksReview() async throws {
        let transport = LifecycleFakeHTTP(["{\"code\":200,\"data\":{}}"])
        do { _ = try await coordinator(setup(transport)).prepare(.cancel(PublishedResource(kind: .topic, value: 5), reason: "Reason", scope: nil)); XCTFail("Missing count accepted") } catch {}
        let requests = await transport.requests; XCTAssertEqual(requests.count, 1)
    }
    func testChangedCountBlocksDispatch() async throws {
        let transport = LifecycleFakeHTTP([paid, "{\"code\":200,\"data\":{\"paidPlayers\":4}}"])
        let owner = coordinator(try setup(transport))
        let review = try await owner.prepare(.cancel(PublishedResource(kind: .topic, value: 5), reason: "Reason", scope: nil))
        let outcome = await owner.confirm(review, consequentialApproval: true); XCTAssertEqual(outcome, .notSent)
        let requests = await transport.requests; XCTAssertEqual(requests.count, 2)
    }
    func testUnknownOutcomeLocksResourceAgainstReplay() async throws {
        let transport = LifecycleFakeHTTP([]); let journal = LifecycleJournal(); let owner = coordinator(try setup(transport), journal: journal)
        let review = try await owner.prepare(.graduate(topicID: 4))
        let first = await owner.confirm(review, consequentialApproval: true); XCTAssertEqual(first, .unknown)
        let fresh = try await owner.prepare(.graduate(topicID: 4))
        let second = await owner.confirm(fresh, consequentialApproval: true); XCTAssertEqual(second, .unknown)
        let requests = await transport.requests; XCTAssertEqual(requests.count, 1)
    }
    func testTransferRequiresNumericNewTopicID() async throws {
        let transport = LifecycleFakeHTTP(["{\"code\":200,\"data\":{}}"]); let owner = coordinator(try setup(transport))
        let review = try await owner.prepare(.transfer(topicID: 4, clubID: 9))
        let result = await owner.confirm(review, consequentialApproval: true); XCTAssertEqual(result, .unknown)
    }
    func testPartnerTermsComeFromFreshLineup() async throws {
        let transport = LifecycleFakeHTTP(["{\"code\":200,\"data\":{\"priceMin\":5,\"lineup\":[{\"toType\":\"club\",\"toId\":9,\"shareMode\":1,\"shareRate\":\"25\"}]}}", "{\"code\":200,\"data\":{\"name\":\"Fixture club\"}}"])
        let result = try await setup(transport).partner(topicID: 4, type: "club", id: 9)
        XCTAssertEqual(result.terms.shareRate, "25"); XCTAssertEqual(result.profile.object?["name"]?.text, "Fixture club")
    }
    func testInvalidPartnerTermsDoNotLoadProfile() async throws {
        let transport = LifecycleFakeHTTP(["{\"code\":200,\"data\":{\"priceMin\":5,\"lineup\":[{\"toType\":\"club\",\"toId\":9,\"shareMode\":1}]}}"])
        do { _ = try await setup(transport).partner(topicID: 4, type: "club", id: 9); XCTFail("Invalid terms accepted") } catch {}
        let requests = await transport.requests; XCTAssertEqual(requests.count, 1)
    }
    func testBudgetUsesServerOverFlagAndReadOnlyFields() async throws {
        let transport = LifecycleFakeHTTP(["{\"code\":200,\"data\":{\"budget\":10,\"totalXp\":10,\"over\":true,\"remain\":0}}"])
        let value = try await setup(transport).budget(topicID: 4)
        XCTAssertEqual(value.over, true); XCTAssertEqual(value.overBy, nil)
        let requests = await transport.requests
        XCTAssertTrue(String(data: requests[0].httpBody!, encoding: .utf8)!.contains("name=\"topic_id\""))
    }
    func testDormantGrantsSendNothing() async throws {
        let transport = LifecycleFakeHTTP([]); let client = try setup(transport, active: false)
        do { _ = try await client.budget(topicID: 4); XCTFail("Dormant read dispatched") } catch {}
        let owner = coordinator(client); let review = try await owner.prepare(.graduate(topicID: 4))
        let result = await owner.confirm(review, consequentialApproval: true); XCTAssertEqual(result, .notSent)
        let requests = await transport.requests; XCTAssertTrue(requests.isEmpty)
    }
    func testCreatorNumericPositiveAndMultipartThenRefresh() async throws {
        let transport = LifecycleFakeHTTP(["{\"code\":200,\"data\":1}"]); let reader = LifecycleCenterReader()
        let owner = CreatorApplicationCoordinator(client: try setup(transport), reader: reader, journal: LifecycleJournal())
        let review = try await owner.prepare(CreatorApplicationDraft(creatorName: "Creator", bio: "Bio", avatarURL: "https://example.com/avatar"))
        let result = await owner.confirm(review, approved: true)
        if case .submitted = result {} else { XCTFail("Not submitted") }
        XCTAssertEqual(reader.count, 3)
        let requests = await transport.requests; let request = try XCTUnwrap(requests.first)
        XCTAssertTrue(request.value(forHTTPHeaderField: "Content-Type")!.hasPrefix("multipart/form-data"))
        let body = String(data: request.httpBody!, encoding: .utf8)!
        for key in ["creatorName", "bio", "avatarUrl"] { XCTAssertTrue(body.contains("name=\"\(key)\"")) }
    }
    func testCreatorZeroIsNotSavedAndStringNotSuccess() async throws {
        for (data, expected) in [("0", CreatorApplicationOutcome.notSaved), ("\"1\"", .unknown)] {
            let transport = LifecycleFakeHTTP(["{\"code\":200,\"data\":\(data)}"])
            let owner = CreatorApplicationCoordinator(client: try setup(transport), reader: LifecycleCenterReader(), journal: LifecycleJournal())
            let review = try await owner.prepare(CreatorApplicationDraft(creatorName: "Creator"))
            let result = await owner.confirm(review, approved: true); XCTAssertEqual(result, expected)
        }
    }
    func testRejectedProfileCannotReapply() async throws {
        let transport = LifecycleFakeHTTP([]); let reader = LifecycleCenterReader(); reader.status = "rejected"
        let owner = CreatorApplicationCoordinator(client: try setup(transport), reader: reader, journal: LifecycleJournal())
        do { _ = try await owner.prepare(CreatorApplicationDraft(creatorName: "Creator")); XCTFail("Reapplication offered") } catch {}
        let requests = await transport.requests; XCTAssertTrue(requests.isEmpty)
    }
    func testInvalidatedReviewCannotDispatch() async throws {
        let transport = LifecycleFakeHTTP([]); let owner = coordinator(try setup(transport))
        let review = try await owner.prepare(.graduate(topicID: 4)); owner.invalidate()
        let result = await owner.confirm(review, consequentialApproval: true); XCTAssertEqual(result, .notSent)
    }
    func testChangedOwnershipStopsBeforeWrite() async throws {
        let transport = LifecycleFakeHTTP([]); let client = try setup(transport)
        var reads = 0
        let owner = PublisherLifecycleCoordinator(client: client, journal: LifecycleJournal()) { resource, _ in
            reads += 1
            return PublisherAuthority(resource: resource, ownerAccountID: reads == 1 ? 7 : 8, revision: "server", beta: true)
        }
        let review = try await owner.prepare(.graduate(topicID: 4))
        let result = await owner.confirm(review, consequentialApproval: true); XCTAssertEqual(result, .notSent)
        let requests = await transport.requests; XCTAssertTrue(requests.isEmpty)
    }
    func testMalformedSuccessEnvelopeRemainsUnknown() async throws {
        let transport = LifecycleFakeHTTP(["{\"msg\":\"not a receipt\"}"])
        let owner = coordinator(try setup(transport))
        let review = try await owner.prepare(.graduate(topicID: 4))
        let result = await owner.confirm(review, consequentialApproval: true); XCTAssertEqual(result, .unknown)
    }
    func testBusinessFailureAtHTTP200PreservesServerText() async throws {
        let transport = LifecycleFakeHTTP(["{\"code\":409,\"msg\":\"不在 Beta 期\"}"])
        let owner = coordinator(try setup(transport))
        let review = try await owner.prepare(.graduate(topicID: 4))
        let result = await owner.confirm(review, consequentialApproval: true); XCTAssertEqual(result, .rejected("不在 Beta 期"))
    }
    func testExplicitApprovalIsRequired() async throws {
        let transport = LifecycleFakeHTTP([]); let owner = coordinator(try setup(transport))
        let review = try await owner.prepare(.graduate(topicID: 4))
        let result = await owner.confirm(review, consequentialApproval: false); XCTAssertEqual(result, .notSent)
        let requests = await transport.requests; XCTAssertTrue(requests.isEmpty)
    }

}
