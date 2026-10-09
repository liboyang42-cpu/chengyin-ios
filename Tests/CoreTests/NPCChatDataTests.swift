import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private let npcDataJSON = #"{"code":200,"data":{"retentionDays":37,"retentionPolicy":"Source policy, exactly as returned","records":[{"id":9007199254740993,"userId":7,"userMsg":"Where is the tea?","npcReply":"At the counter.","createTime":"2026-10-09 09:00:00","systemPrompt":"MUST NOT PROJECT","model":"internal-provider","profileId":9,"activityId":12}]}}"#

final class NPCChatDataDecodingTests: XCTestCase {
    func testWhitelistPreciseIDsOwnMessagesAndServerPolicy() throws {
        let value = try NPCChatData.decode(Data(npcDataJSON.utf8), expectedAccountID: 7)
        XCTAssertEqual(value.retentionDays, 37); XCTAssertEqual(value.retentionPolicy, "Source policy, exactly as returned")
        let row = try XCTUnwrap(value.records.first)
        XCTAssertEqual(row.id, "9007199254740993"); XCTAssertEqual(row.userMessage, "Where is the tea?")
        XCTAssertEqual(row.npcReply, "At the counter."); XCTAssertEqual(row.sourceTime, "2026-10-09 09:00:00")
        XCTAssertEqual(Set(Mirror(reflecting: row).children.compactMap(\.label)), ["id", "ownerID", "userMessage", "npcReply", "sourceTime"])
    }
    func testMissingPolicyDoesNotInventNinetyDayRetention() throws {
        let value = try NPCChatData.decode(Data(#"{"code":200,"data":{"records":[]}}"#.utf8), expectedAccountID: 7)
        XCTAssertNil(value.retentionDays); XCTAssertNil(value.retentionPolicy); XCTAssertTrue(value.records.isEmpty)
    }
    func testAnotherOwnersRowRejectsTheEntireProjection() {
        XCTAssertThrowsError(try NPCChatData.decode(Data(npcDataJSON.utf8), expectedAccountID: 8)) {
            XCTAssertEqual($0 as? NPCChatDataFailure, .malformed)
        }
        let mixed = #"{"code":200,"data":{"records":[{"id":1,"userId":7},{"id":2,"userId":8}]}}"#
        XCTAssertThrowsError(try NPCChatData.decode(Data(mixed.utf8), expectedAccountID: 7))
    }
    func testMissingOwnerDuplicateIDsInvalidEnvelopeAndDateFailClosed() {
        for body in [#"{"id":1}"#, #"{"id":true,"userId":7}"#, #"{"id":1,"userId":true}"#, #"{"id":1,"userId":7,"createTime":{"raw":"secret"}}"#] {
            let data = Data((#"{"code":200,"data":{"records":["# + body + "]}}").utf8)
            XCTAssertThrowsError(try NPCChatData.decode(data, expectedAccountID: 7))
        }
        for json in [#"{"code":200}"#, #"{"code":200,"data":{"records":null}}"#, #"{"code":200,"data":{"records":[{"id":1,"userId":7},{"id":"1","userId":"7"}]}}"#, #"{"code":200,"data":{"retentionDays":-1,"records":[]}}"#] {
            XCTAssertThrowsError(try NPCChatData.decode(Data(json.utf8), expectedAccountID: 7))
        }
    }
    func testRejectionDoesNotCarryServerErrorOrPromptText() {
        do { _ = try NPCChatData.decode(Data(#"{"code":403,"msg":"Internal prompt or private diagnostic"}"#.utf8), expectedAccountID: 7); XCTFail() }
        catch { XCTAssertEqual(error as? NPCChatDataFailure, .rejected) }
    }
    func testNumericTimestampIsKeptAsSourceRepresentationWithoutGuessedUnits() throws {
        let json = #"{"code":200,"data":{"records":[{"id":"1","userId":"7","createTime":1700000000000}]}}"#
        let value = try NPCChatData.decode(Data(json.utf8), expectedAccountID: 7)
        XCTAssertEqual(value.records.first?.sourceTime, "1700000000000")
        XCTAssertNil(value.records.first?.userMessage); XCTAssertNil(value.records.first?.npcReply)
    }
    func testLocalSearchMatchesQuestionOrReplyOnly() throws {
        let row = try XCTUnwrap(NPCChatData.decode(Data(npcDataJSON.utf8), expectedAccountID: 7).records.first)
        XCTAssertTrue(row.matches("TEA")); XCTAssertTrue(row.matches("counter")); XCTAssertTrue(row.matches("  "))
        XCTAssertFalse(row.matches("internal-provider")); XCTAssertFalse(row.matches("MUST NOT PROJECT"))
    }
    func testResponseAndRowCapacityBoundsNeverReturnTruncatedSuccess() throws {
        XCTAssertThrowsError(try NPCChatData.decode(Data(count: 8_388_609), expectedAccountID: 7)) {
            XCTAssertEqual($0 as? NPCChatDataFailure, .tooLarge)
        }
        let records = (1...10_001).map { ["id": $0, "userId": 7] }
        let data = try JSONSerialization.data(withJSONObject: ["code": 200, "data": ["records": records]])
        XCTAssertThrowsError(try NPCChatData.decode(data, expectedAccountID: 7)) { XCTAssertEqual($0 as? NPCChatDataFailure, .tooLarge) }
        let large = try JSONSerialization.data(withJSONObject: ["code": 200, "data": ["records": [["id": 1, "userId": 7, "npcReply": String(repeating: "x", count: 131_073)]]]])
        XCTAssertThrowsError(try NPCChatData.decode(large, expectedAccountID: 7)) { XCTAssertEqual($0 as? NPCChatDataFailure, .tooLarge) }
    }
}

private final class NPCDataHTTP: HTTPTransport {
    var requests: [URLRequest] = []
    var response = npcDataJSON
    var status = 200
    var afterSend: (() -> Void)?
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); afterSend?(); return (Data(response.utf8), status)
    }
}
@MainActor private final class NPCDataJournal: ComplianceJournaling {
    var writes = 0
    func pending(scope: String, operation: String) throws -> CompliancePendingOperation? { nil }
    func begin(_ operation: CompliancePendingOperation) throws { writes += 1 }
    func resolve(scope: String, operation: String) throws { writes += 1 }
}
@MainActor private final class NPCDataUnusedAuth: AuthChannelServing {
    func sendSMSCode(phone: String) async throws { XCTFail(); throw ComplianceFailure.unavailable }
    func loginWithPhone(phone: String, code: String) async throws -> LoginResult { XCTFail(); throw ComplianceFailure.unavailable }
    func loginWithApple(identityToken: String) async throws -> LoginResult { XCTFail(); throw ComplianceFailure.unavailable }
    func currentAccount(token: String) async throws -> Account { XCTFail(); throw ComplianceFailure.unavailable }
}
@MainActor private final class NPCDataUnusedEffects: ComplianceRoamEffects {
    func stopTracking() async throws { XCTFail() }
    func clearMapPrivacy() async throws { XCTFail() }
    func invalidateMapPrivacyCaches() { XCTFail() }
}
@MainActor final class NPCChatDataServiceTests: XCTestCase {
    private let session = ComplianceSession(accountID: 7, epoch: 1, market: "CN", namespace: "synthetic.invalid")
    private var configuration: APIConfiguration { try! .init(baseURL: URL(string: "https://synthetic.invalid")!) }
    private func approval(account: Int = 7, namespace: String = "synthetic.invalid", path: String = NPCChatData.path) throws -> OperationEndpointApproval {
        try .init(baseURL: configuration.baseURL, namespace: namespace, accountID: account, paths: [path])
    }
    func testIndependentDefaultOffEvenWhenGeneralComplianceReadsAreEnabled() async {
        let http = NPCDataHTTP(), journal = NPCDataJournal()
        let service = AccountComplianceService(configuration: configuration, transport: http, journal: journal,
            current: { self.session }, token: { "synthetic-test-token" }, readsEnabled: true, writesEnabled: true)
        XCTAssertFalse(service.canReadNPCChatData(session: session))
        do { _ = try await service.readNPCChatData(session: session); XCTFail() }
        catch { XCTAssertEqual(error as? NPCChatDataFailure, .unavailable) }
        XCTAssertTrue(http.requests.isEmpty); XCTAssertEqual(journal.writes, 0)
    }
    func testExactGETWithNoClientIdentityBodyQueryOrMutation() async throws {
        let http = NPCDataHTTP(), journal = NPCDataJournal(), approval = try approval()
        let service = AccountComplianceService(configuration: configuration, transport: http, journal: journal,
            current: { self.session }, token: { "synthetic-test-token" }, npcChatDataReadApproval: { approval })
        let value = try await service.readNPCChatData(session: session)
        XCTAssertEqual(value.records.count, 1)
        let request = try XCTUnwrap(http.requests.first)
        XCTAssertEqual(request.httpMethod, "GET"); XCTAssertEqual(request.url?.path, "/api/ai/npc/chat/data/export")
        XCTAssertNil(request.httpBody); XCTAssertNil(request.url?.query)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "synthetic-test-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cache-Control"), "no-store")
        XCTAssertEqual(journal.writes, 0)
    }
    func testAnotherAccountNamespaceOrPathApprovalDoesNotAuthorizeRead() async throws {
        for approval in [try approval(account: 8), try approval(namespace: "other"), try approval(path: "api/ai/npc/merchant-chat")] {
            let http = NPCDataHTTP()
            let service = AccountComplianceService(configuration: configuration, transport: http, journal: NPCDataJournal(),
                current: { self.session }, token: { "synthetic-test-token" }, npcChatDataReadApproval: { approval })
            XCTAssertFalse(service.canReadNPCChatData(session: session))
            do { _ = try await service.readNPCChatData(session: session); XCTFail() } catch {}
            XCTAssertTrue(http.requests.isEmpty)
        }
    }
    func testEpochTokenOrApprovalChangeRejectsLatePrivateResponse() async throws {
        for variant in [0, 1, 2] {
            let http = NPCDataHTTP(); var current: ComplianceSession? = session
            var token = "synthetic-test-token"; var accepted: OperationEndpointApproval? = try approval()
            let service = AccountComplianceService(configuration: configuration, transport: http, journal: NPCDataJournal(),
                current: { current }, token: { token }, npcChatDataReadApproval: { accepted })
            http.afterSend = {
                if variant == 0 { current = .init(accountID: 7, epoch: 2, market: "CN", namespace: "synthetic.invalid") }
                else if variant == 1 { token = "different-synthetic-token" }
                else { accepted = nil }
            }
            do { _ = try await service.readNPCChatData(session: session); XCTFail() }
            catch { XCTAssertEqual(error as? NPCChatDataFailure, .staleSession) }
        }
    }
    func testHTTPFailureDoesNotExposeRawBody() async throws {
        let http = NPCDataHTTP(), approval = try approval(); http.status = 500; http.response = "private raw stacktrace"
        let service = AccountComplianceService(configuration: configuration, transport: http, journal: NPCDataJournal(),
            current: { self.session }, token: { "synthetic-test-token" }, npcChatDataReadApproval: { approval })
        do { _ = try await service.readNPCChatData(session: session); XCTFail() }
        catch { XCTAssertEqual(error as? NPCChatDataFailure, .failed) }
    }
    func testParentInvalidationAndReplacementClearThePrivateChild() async throws {
        let http = NPCDataHTTP(), approval = try approval()
        let service = AccountComplianceService(configuration: configuration, transport: http, journal: NPCDataJournal(),
            current: { self.session }, token: { "synthetic-test-token" }, npcChatDataReadApproval: { approval })
        let parent = AccountComplianceCoordinator(service: service, auth: NPCDataUnusedAuth(), effects: NPCDataUnusedEffects(), current: { self.session }, invalidateSession: { _ in XCTFail() })
        let first = parent.makeNPCChatDataCoordinator(); first.appear(active: true); await first.load(); XCTAssertNotNil(first.data)
        let second = parent.makeNPCChatDataCoordinator(); XCTAssertNil(first.data); XCTAssertFalse(first.canLoad)
        second.appear(active: true); await second.load(); XCTAssertNotNil(second.data)
        parent.invalidate(); XCTAssertNil(second.data); XCTAssertFalse(second.canLoad)
    }
}

@MainActor final class NPCChatDataCoordinatorTests: XCTestCase {
    private let session = ComplianceSession(accountID: 7, epoch: 1, market: "CN", namespace: "synthetic.invalid")
    private func data() throws -> NPCChatData { try .decode(Data(npcDataJSON.utf8), expectedAccountID: 7) }
    func testClosedBackgroundAndReopenRequireAnExplicitNewRead() async throws {
        var calls = 0; let value = try data()
        let flow = NPCChatDataCoordinator(current: { self.session }, available: { _ in true }, read: { _ in calls += 1; return value })
        await flow.load(); XCTAssertEqual(calls, 0)
        flow.appear(active: true); await flow.load(); XCTAssertNotNil(flow.data)
        flow.suspend(); XCTAssertNil(flow.data); flow.foreground(); XCTAssertNil(flow.data); XCTAssertEqual(calls, 1)
        await flow.load(); XCTAssertEqual(calls, 2)
        flow.invalidate(); XCTAssertNil(flow.data); await flow.load(); XCTAssertEqual(calls, 2)
    }
    func testAccountOrApprovalChangeImmediatelyHidesLoadedData() async throws {
        var current: ComplianceSession? = session; var allowed = true; let value = try data()
        let flow = NPCChatDataCoordinator(current: { current }, available: { _ in allowed }, read: { _ in value })
        flow.appear(active: true); await flow.load(); XCTAssertNotNil(flow.data)
        allowed = false; XCTAssertNil(flow.data)
        allowed = true; current = .init(accountID: 8, epoch: 2, market: "CN", namespace: "synthetic.invalid")
        XCTAssertNil(flow.data); flow.sessionChanged(); XCTAssertNil(flow.data)
    }
    func testLateReadAfterCloseCannotRestoreTextAndRepeatedLoadDoesNotDispatchTwice() async throws {
        var continuation: CheckedContinuation<NPCChatData, Never>?
        var calls = 0; let value = try data()
        let flow = NPCChatDataCoordinator(current: { self.session }, available: { _ in true }, read: { _ in
            calls += 1; return await withCheckedContinuation { continuation = $0 }
        })
        flow.appear(active: true); let task = Task { await flow.load() }
        for _ in 0..<1_000 { if continuation != nil { break }; await Task.yield() }
        await flow.load(); XCTAssertEqual(calls, 1)
        flow.invalidate(); continuation?.resume(returning: value); await task.value
        XCTAssertNil(flow.data); XCTAssertFalse(flow.canLoad)
    }
    func testMissingApprovalAndFailedReloadNeverLookLikeAnEmptySuccess() async throws {
        var allowed = false; var fail = false; let value = try data()
        let flow = NPCChatDataCoordinator(current: { self.session }, available: { _ in allowed }, read: { _ in
            if fail { throw NPCChatDataFailure.failed }; return value
        })
        flow.appear(active: true); XCTAssertEqual(flow.failure, .unavailable); XCTAssertFalse(flow.canLoad)
        allowed = true; await flow.load(); XCTAssertNotNil(flow.data)
        fail = true; await flow.load(); XCTAssertNil(flow.data); XCTAssertEqual(flow.phase, .unavailable); XCTAssertEqual(flow.failure, .failed)
    }
    func testEvenAnInjectedReaderCannotReturnAValidatedSnapshotForAnotherAccount() async throws {
        let wrong = try NPCChatData.decode(Data(#"{"code":200,"data":{"records":[]}}"#.utf8), expectedAccountID: 8)
        let flow = NPCChatDataCoordinator(current: { self.session }, available: { _ in true }, read: { _ in wrong })
        flow.appear(active: true); await flow.load()
        XCTAssertNil(flow.data); XCTAssertEqual(flow.failure, .malformed)
    }
}
