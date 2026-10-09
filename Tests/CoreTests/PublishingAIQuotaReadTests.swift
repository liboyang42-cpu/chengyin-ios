import XCTest
@testable import QuestifyCore

@MainActor final class PublishingAIQuotaReadTests: XCTestCase {
    private static func quota(_ remaining: Int, limit: Int = 4) throws -> PublishingAIQuota {
        try PublishingAIQuota(.object(["limited": .bool(true), "limit": .number(Decimal(limit)), "remaining": .number(Decimal(remaining))]))
    }
    func testExactCountFieldsAndAbsentOptionalLimit() throws {
        let value = try Self.quota(2)
        XCTAssertTrue(value.limited); XCTAssertEqual(value.limit, 4); XCTAssertEqual(value.remaining, 2)
        XCTAssertFalse(value.exhausted)
        let legacy = try PublishingAIQuota(.object(["limited": .bool(true), "remaining": .number(0)]))
        XCTAssertNil(legacy.limit); XCTAssertTrue(legacy.exhausted)
    }
    func testMalformedCountsAndUnknownUnlimitedSentinelsAreRejected() throws {
        let invalid: [ProjectEditJSON] = [.number(-1), .number(Decimal(string: "1.5")!), .string("4"), .bool(true)]
        for bad in invalid {
            for field in ["remaining", "limit"] {
                var fields: [String: ProjectEditJSON] = ["limited": .bool(true), "remaining": .number(1), "limit": .number(4)]
                fields[field] = bad
                XCTAssertThrowsError(try PublishingAIQuota(.object(fields)))
            }
        }
        XCTAssertThrowsError(try PublishingAIQuota(.object(["limited": .bool(true)])))
        XCTAssertThrowsError(try PublishingAIQuota(.object(["limited": .string("true"), "remaining": .number(1)])))
    }
    func testNotMarkedLimitedDoesNotInventCounts() throws {
        let quota = try PublishingAIQuota(.object(["limited": .bool(false), "limit": .null, "remaining": .null]))
        XCTAssertNil(quota.limit); XCTAssertNil(quota.remaining); XCTAssertFalse(quota.exhausted)
    }
    func testReadRecordsObservationTimeWithoutGeneratingOrEditingIdea() async throws {
        let client = Stub(); let instant = Date(timeIntervalSince1970: 100)
        let flow = PublishingAIDraftFlow(client: client, product: .city, now: { instant })
        flow.idea = "Keep this local idea"; await flow.loadQuota()
        XCTAssertEqual(flow.quotaReadState, .fresh); XCTAssertEqual(flow.quotaReadAt, instant)
        XCTAssertEqual(flow.quota?.remaining, 2); XCTAssertFalse(flow.quotaIsStale)
        XCTAssertEqual(flow.idea, "Keep this local idea"); XCTAssertNil(flow.candidate)
        XCTAssertEqual(client.readCalls, 1); XCTAssertEqual(client.generateCalls, 0)
    }
    func testFailedRefreshRetainsExhaustedValueAndCannotRestoreGeneration() async throws {
        let client = Stub(); client.result = .success(try Self.quota(0))
        let flow = PublishingAIDraftFlow(client: client, product: .city)
        await flow.loadQuota(); let observed = flow.quotaReadAt
        client.result = .failure(PublishModesError.rejected("Synthetic private error")); await flow.loadQuota()
        XCTAssertEqual(flow.quotaReadState, .failed); XCTAssertTrue(flow.quotaIsStale)
        XCTAssertEqual(flow.quota?.remaining, 0); XCTAssertEqual(flow.quotaReadAt, observed)
        XCTAssertFalse(flow.canGenerate); XCTAssertTrue(flow.canRefreshQuota); XCTAssertNil(flow.serverMessage)
        flow.idea = "Walk"; await flow.generate(); XCTAssertEqual(client.generateCalls, 0)
    }
    func testFirstReadFailureDoesNotCreateQuotaOrNewCapability() async {
        let client = Stub(); client.canGenerate = false; client.result = .failure(PublishModesError.unavailable)
        let flow = PublishingAIDraftFlow(client: client, product: .city); await flow.loadQuota()
        XCTAssertEqual(flow.quotaReadState, .failed); XCTAssertNil(flow.quota); XCTAssertNil(flow.quotaReadAt)
        XCTAssertFalse(flow.canGenerate); XCTAssertFalse(flow.quotaIsStale)
    }
    func testSameAccountNewEpochImmediatelyHidesPreviousCounts() async {
        let client = Stub(); let flow = PublishingAIDraftFlow(client: client, product: .city)
        await flow.loadQuota(); client.session = Self.session()
        XCTAssertNil(flow.quota); XCTAssertNil(flow.quotaReadAt); XCTAssertEqual(flow.quotaReadState, .unavailable)
        XCTAssertFalse(flow.canGenerate); XCTAssertFalse(flow.canRefreshQuota)
        await flow.loadQuota(); XCTAssertEqual(client.readCalls, 1)
    }
    func testDuplicateRefreshAndGenerationCannotRacePendingRead() async throws {
        let client = Stub(); client.hold = true
        let started = expectation(description: "Read started"); client.onRead = { started.fulfill() }
        let flow = PublishingAIDraftFlow(client: client, product: .city)
        let read = Task { await flow.loadQuota() }; await fulfillment(of: [started], timeout: 1)
        XCTAssertEqual(flow.quotaReadState, .loading); XCTAssertFalse(flow.canRefreshQuota); XCTAssertFalse(flow.canGenerate)
        await flow.loadQuota(); flow.idea = "Walk"; await flow.generate()
        XCTAssertEqual(client.readCalls, 1); XCTAssertEqual(client.generateCalls, 0)
        client.resume(); await read.value
        XCTAssertEqual(flow.quotaReadState, .fresh); XCTAssertTrue(flow.canRefreshQuota)
    }
    func testCloseRejectsLateNoncooperativeReadAndErasesMemory() async {
        let client = Stub(); client.hold = true
        let started = expectation(description: "Read started"); client.onRead = { started.fulfill() }
        let flow = PublishingAIDraftFlow(client: client, product: .city)
        let read = Task { await flow.loadQuota() }; await fulfillment(of: [started], timeout: 1)
        flow.close(); client.resume(); await read.value
        XCTAssertNil(flow.quota); XCTAssertNil(flow.quotaReadAt); XCTAssertEqual(flow.quotaReadState, .unavailable)
        XCTAssertFalse(flow.canRefreshQuota); XCTAssertEqual(client.generateCalls, 0)
    }
    func testAccountChangeRejectsLateRead() async {
        let client = Stub(); client.hold = true
        let started = expectation(description: "Read started"); client.onRead = { started.fulfill() }
        let flow = PublishingAIDraftFlow(client: client, product: .city)
        let read = Task { await flow.loadQuota() }; await fulfillment(of: [started], timeout: 1)
        client.session = nil; client.resume(); await read.value
        XCTAssertNil(flow.quota); XCTAssertEqual(flow.quotaReadState, .unavailable); XCTAssertFalse(flow.canGenerate)
    }
    func testGenerationFailureMarksPreviousObservationStale() async {
        let client = Stub(); let flow = PublishingAIDraftFlow(client: client, product: .city)
        await flow.loadQuota(); flow.idea = "Walk"; await flow.generate()
        XCTAssertEqual(client.generateCalls, 1); XCTAssertEqual(client.readCalls, 1)
        XCTAssertEqual(flow.quotaReadState, .stale); XCTAssertTrue(flow.quotaIsStale)
    }
    func testUnavailableClientHasNoRefreshOrGeneration() async {
        let flow = PublishingAIDraftFlow(client: nil, product: .city); await flow.loadQuota()
        XCTAssertEqual(flow.quotaReadState, .unavailable); XCTAssertFalse(flow.canRefreshQuota); XCTAssertFalse(flow.canGenerate)
    }
    private static func session() -> PublishingSession {
        .init(namespace: "synthetic", accountID: 7, epoch: UUID(), role: "player", region: .china)
    }
    @MainActor private final class Stub: PublishingAIDraftServing {
        var session: PublishingSession? = PublishingAIQuotaReadTests.session()
        var canGenerate = true
        var result: Result<PublishingAIQuota, Error> = .success(try! PublishingAIQuotaReadTests.quota(2))
        var readCalls = 0; var generateCalls = 0; var hold = false
        var onRead: (() -> Void)?
        var pending: CheckedContinuation<PublishingAIQuota, Error>?
        func quota() async throws -> PublishingAIQuota {
            readCalls += 1
            if hold { return try await withCheckedThrowingContinuation { pending = $0; onRead?() } }
            return try result.get()
        }
        func resume() { let value = pending; pending = nil; value?.resume(with: result) }
        func generate(idea: String, product: ProjectEditProduct) async throws -> PublishingAIThemeDraft {
            generateCalls += 1; throw PublishModesError.unavailable
        }
        func cancel() {}
    }
}
