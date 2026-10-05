import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class RoamDormantSpyTransport: HTTPTransport {
    var sends = 0
    func send(_ request: URLRequest) async throws -> (Data, Int) { sends += 1; return (Data(), 500) }
}
@MainActor private final class RoamStampTestStorage: RoamHistoryDataStoring {
    var values: [String: Data] = [:]
    var fail = false
    func read(key: String) throws -> Data? { values[key] }
    func write(_ data: Data, key: String) throws {
        if fail { throw RoamExperienceFailure.historyWriteFailed }; values[key] = data
    }
}
@MainActor private final class RoamStampTestExecutor: RoamExperienceMutationExecuting {
    var isAvailable = true
    var mutations: [RoamExperienceMutation] = []
    var failCreate = false
    var failExchange = false
    var onCall: (() -> Void)?
    func execute(_ mutation: RoamExperienceMutation) async throws -> Data {
        mutations.append(mutation); onCall?()
        switch mutation {
        case .createStamp:
            if failCreate { throw APIError.httpStatus(503) }
            return Data(#"{"code":200,"data":{"id":901,"idempotent":true}}"#.utf8)
        case .exchangeStamp:
            if failExchange { throw APIError.httpStatus(503) }
            return Data(#"{"code":200,"data":{"exchanged":false,"reason":"Synthetic pool empty","idempotent":false}}"#.utf8)
        default: throw APIError.invalidRequest
        }
    }
}
@MainActor final class RoamExperienceMutationTests: XCTestCase {
    private func fix(_ datum: RoamDeviceFix.Datum = .gcj02) throws -> RoamDeviceFix {
        try RoamDeviceFix(coordinate: RoamCoordinate(latitude: 1, longitude: 2)!, accuracyMeters: 12, measuredAt: Date(timeIntervalSince1970: 100), datum: datum)
    }
    private func identity(epoch: UInt64 = 1) throws -> RoamExperienceIdentity {
        try RoamExperienceIdentity(scope: RoamHistoryScope(market: "cn", deployment: URL(string: "https://example.com/fixture/")!, accountID: 1), epoch: epoch)
    }
    private func draft(_ caption: String = "Synthetic caption") throws -> RoamStampExchangeDraft {
        try RoamStampExchangeDraft(pictureURL: "synthetic-upload-object", caption: caption, idempotencyKey: "synthetic-fixed-key")
    }
    func testRevealAndFinishUseCommaSeparatedExactFields() throws {
        XCTAssertEqual(try RoamExperienceMutation.reveal(sessionID: 0, tiles: ["s000000", "s000001"]).fields(), ["sessionId": "0", "tiles": "s000000,s000001"])
        XCTAssertEqual(try RoamExperienceMutation.finish(sessionID: 1, poiIDs: [3, 4], distanceMeters: 210).fields(), ["sessionId": "1", "poiIds": "3,4", "distanceM": "210"])
    }
    func testDiscoverShopAndPresenceKeepSourceTypesAndDatumExplicit() throws {
        let coordinates = try fix()
        XCTAssertEqual(try RoamExperienceMutation.discover(sessionID: 1, poiID: 2, fix: coordinates).fields(), ["sessionId": "1", "poiId": "2", "lat": "1.0", "lng": "2.0"])
        XCTAssertThrowsError(try RoamExperienceMutation.shopVisit(sessionID: 1, sourceType: 3, sourceID: 2, fix: coordinates).fields())
        XCTAssertThrowsError(try RoamExperienceMutation.discover(sessionID: 1, poiID: 2, fix: fix(.wgs84)).fields())
        XCTAssertEqual(try RoamExperienceMutation.presence(sessionID: 1, fix: coordinates, explorationPercent: 12).fields()["explorePct"], "12")
    }
    func testStampCreationRequiresStableKeyAndOmitsEmptyCaption() throws {
        XCTAssertThrowsError(try RoamExperienceMutation.createStamp(pictureURL: "object", caption: "", idempotencyKey: "").fields())
        let value = try RoamExperienceMutation.createStamp(pictureURL: "object", caption: "", idempotencyKey: "fixed").fields()
        XCTAssertEqual(value, ["picUrl": "object", "idempotencyKey": "fixed"])
        XCTAssertEqual(try RoamExperienceMutation.exchangeStamp(givenStampID: 8).fields(), ["givenStampId": "8"])
    }
    func testVoucherAndFavoriteWireRequestsMatchSource() throws {
        let configuration = try APIConfiguration(baseURL: URL(string: "https://example.com/")!)
        let voucher = try RoamExperienceMutation.issueVoucher(poiID: 9).request(configuration: configuration, token: "fixture-token")
        XCTAssertEqual(voucher.url?.path, "/api/verify/citynode/issue"); XCTAssertEqual(voucher.httpMethod, "POST")
        let favorite = try RoamExperienceMutation.toggleFavorite(poiID: 9).request(configuration: configuration, token: "fixture-token")
        XCTAssertEqual(favorite.url?.path, "/api/city/nodes/9/favorite"); XCTAssertNil(favorite.httpBody)
    }
    func testDormantAdapterDeniesBeforeReadingSessionOrTransport() async throws {
        let transport = RoamDormantSpyTransport()
        var credentialReads = 0
        let adapter = RoamDormantMutationAdapter(configuration: try APIConfiguration(baseURL: URL(string: "https://example.com/")!), transport: transport, currentSession: { credentialReads += 1; return nil })
        for operation in [RoamExperienceMutation.reveal(sessionID: 0, tiles: ["s000000"]), .finish(sessionID: 1, poiIDs: [], distanceMeters: 0), .issueVoucher(poiID: 1), .createStamp(pictureURL: "object", caption: "", idempotencyKey: "key"), .exchangeStamp(givenStampID: 1)] {
            do { _ = try await adapter.execute(operation); XCTFail() }
            catch { XCTAssertEqual(error as? RoamExperienceFailure, .capabilityUnavailable) }
        }
        XCTAssertFalse(adapter.isAvailable); XCTAssertEqual(transport.sends, 0); XCTAssertEqual(credentialReads, 0)
    }
    func testCheckinUsesThreeDataOutcomesNotJustCode200() throws {
        func receipt(_ json: String) throws -> RoamCheckinDisposition {
            try RoamMutationReceiptDecoder.value(RoamCheckinReceipt.self, from: Data(json.utf8)).disposition
        }
        XCTAssertEqual(try receipt(#"{"code":200,"data":{"tooFar":true,"xp":99}}"#), .tooFar)
        XCTAssertEqual(try receipt(#"{"code":200,"data":{"participating":true,"poiId":9}}"#), .needsScan(poiID: 9))
        XCTAssertEqual(try receipt(#"{"code":200,"data":{"participating":false,"firstVisit":false,"xp":99}}"#), .lit(firstVisit: false, awardedXP: 0))
    }
    func testCreateThenExchangeOrderAndDurableCompletionNoReplay() async throws {
        let executor = RoamStampTestExecutor(), storage = RoamStampTestStorage(), identity = try identity(), draft = try draft()
        let journal = RoamStampExchangeJournal(storage: storage)
        let model = RoamStampExchangeCoordinator(executor: executor, journal: journal, currentIdentity: { identity })
        await model.submitOrRetry(draft)
        XCTAssertEqual(model.phase, .noExchange); XCTAssertEqual(executor.mutations.count, 2)
        XCTAssertEqual(executor.mutations.last, .exchangeStamp(givenStampID: 901))
        XCTAssertEqual(try journal.load(scope: identity.scope)?.phase, .finished)
        let resumed = RoamStampExchangeCoordinator(executor: executor, journal: journal, currentIdentity: { identity })
        await resumed.submitOrRetry(draft)
        XCTAssertEqual(resumed.phase, .saved); XCTAssertEqual(executor.mutations.count, 2)
    }
    func testUnknownCreateRetriesSameKeyAndPayloadAcrossRecreation() async throws {
        let executor = RoamStampTestExecutor(), storage = RoamStampTestStorage(), identity = try identity(), draft = try draft()
        let journal = RoamStampExchangeJournal(storage: storage)
        executor.failCreate = true
        let model = RoamStampExchangeCoordinator(executor: executor, journal: journal, currentIdentity: { identity })
        await model.submitOrRetry(draft); XCTAssertEqual(model.phase, .retryRequired)
        XCTAssertEqual(try journal.load(scope: identity.scope)?.phase, .createPending)
        executor.failCreate = false
        let resumed = RoamStampExchangeCoordinator(executor: executor, journal: journal, currentIdentity: { identity })
        await resumed.submitOrRetry(draft)
        XCTAssertEqual(executor.mutations[0], executor.mutations[1]); XCTAssertEqual(resumed.phase, .noExchange)
    }
    func testUnknownExchangeDoesNotRecreateAlreadySavedStamp() async throws {
        let executor = RoamStampTestExecutor(), storage = RoamStampTestStorage(), identity = try identity(), draft = try draft()
        let model = RoamStampExchangeCoordinator(executor: executor, journal: RoamStampExchangeJournal(storage: storage), currentIdentity: { identity })
        executor.failExchange = true; await model.submitOrRetry(draft)
        executor.failExchange = false; await model.submitOrRetry(draft)
        XCTAssertEqual(executor.mutations.count, 3)
        XCTAssertEqual(executor.mutations[1], executor.mutations[2])
    }
    func testJournalFailurePreventsDispatch() async throws {
        let executor = RoamStampTestExecutor(), storage = RoamStampTestStorage(), identity = try identity()
        storage.fail = true
        let model = RoamStampExchangeCoordinator(executor: executor, journal: RoamStampExchangeJournal(storage: storage), currentIdentity: { identity })
        await model.submitOrRetry(try draft())
        XCTAssertEqual(model.phase, .journalFailure); XCTAssertTrue(executor.mutations.isEmpty)
    }
    func testUnknownDraftCannotBeChangedAndSentAsNewStamp() async throws {
        let executor = RoamStampTestExecutor(), storage = RoamStampTestStorage(), identity = try identity()
        let model = RoamStampExchangeCoordinator(executor: executor, journal: RoamStampExchangeJournal(storage: storage), currentIdentity: { identity })
        executor.failCreate = true; await model.submitOrRetry(try draft())
        executor.failCreate = false; await model.submitOrRetry(try draft("different"))
        XCTAssertEqual(executor.mutations.count, 1)
    }
    func testSessionChangeStopsExchangeAfterCreate() async throws {
        let executor = RoamStampTestExecutor(), storage = RoamStampTestStorage()
        var current: RoamExperienceIdentity? = try identity()
        executor.onCall = { current = nil }
        let model = RoamStampExchangeCoordinator(executor: executor, journal: RoamStampExchangeJournal(storage: storage), currentIdentity: { current })
        await model.submitOrRetry(try draft())
        XCTAssertEqual(executor.mutations.count, 1); XCTAssertNil(model.receipt); XCTAssertEqual(model.phase, .idle)
    }
}
