import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private actor CooperationTransport: HTTPTransport {
    struct Reply { let json: String; var status = 200 }
    let replies: [String: Reply]
    private(set) var requests: [URLRequest] = []
    init(_ replies: [String: Reply] = [:]) { self.replies = replies }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        let path = request.url!.path.replacingOccurrences(of: "/test", with: "")
        let reply = replies[path] ?? Reply(json: #"{"code":200,"data":{}}"#)
        return (Data(reply.json.utf8), reply.status)
    }
}
private actor CooperationSuspendedTransport: HTTPTransport {
    private(set) var requests: [URLRequest] = []
    private var pending: [Int: CheckedContinuation<(Data, Int), Error>] = [:]
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        let index = requests.count; requests.append(request)
        return try await withCheckedThrowingContinuation { pending[index] = $0 }
    }
    func waitForRequests(_ count: Int) async { while pending.count < count { await Task.yield() } }
    func finish(_ json: String, status: Int = 200) {
        let continuations = Array(pending.values); pending.removeAll()
        for continuation in continuations { continuation.resume(returning: (Data(json.utf8), status)) }
    }
}
final class CooperationTests: XCTestCase {
    private func service(_ transport: any HTTPTransport) throws -> CooperationService {
        try CooperationService(configuration: APIConfiguration(baseURL: URL(string: "https://example.com/test/")!), transport: transport)
    }
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }
    private func fixtureTransport() -> CooperationTransport {
        CooperationTransport([
            "/api/coop/list": .init(json: CooperationSyntheticFixtures.invitationsJSON),
            "/api/coop/pool/mine": .init(json: CooperationSyntheticFixtures.sentApplicationsJSON),
            "/api/coop/pool/received": .init(json: CooperationSyntheticFixtures.receivedApplicationsJSON),
            "/api/coop/candidates/received": .init(json: CooperationSyntheticFixtures.registrationsJSON),
            "/api/coop/pool/list": .init(json: CooperationSyntheticFixtures.poolJSON),
            "/api/coop/candidates": .init(json: CooperationSyntheticFixtures.candidatesJSON)
        ])
    }
    func testAllowlistedJSONRequestsPreserveRawAuthorizationAndNumericTopicId() async throws {
        let t = fixtureTransport(); let api = try service(t)
        _ = try await api.invitations(token: "synthetic-token")
        _ = try await api.applications(direction: .sent, token: "synthetic-token")
        _ = try await api.applications(direction: .received, token: "synthetic-token")
        _ = try await api.registrations(token: "synthetic-token")
        _ = try await api.pool(token: "synthetic-token")
        _ = try await api.candidates(topicID: 301, token: "synthetic-token")
        let requests = await t.requests
        XCTAssertEqual(requests.count, 6)
        XCTAssertEqual(Set(requests.compactMap { $0.url?.path }), Set(["/test/api/coop/list", "/test/api/coop/pool/mine", "/test/api/coop/pool/received", "/test/api/coop/candidates/received", "/test/api/coop/pool/list", "/test/api/coop/candidates"]))
        for request in requests {
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "synthetic-token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
            XCTAssertNil(request.url?.query)
            let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
            if request.url?.lastPathComponent == "candidates" {
                XCTAssertEqual(fields.count, 1); XCTAssertEqual(fields["topicId"] as? Int, 301)
            } else { XCTAssertTrue(fields.isEmpty) }
        }
    }
    func testInvitationDetailRereadsSameDirectionWithSlotsFromOneResponse() async throws {
        let t = fixtureTransport(); let api = try service(t)
        let received = try await api.detail(key: .init(id: 71, direction: .received), token: "synthetic-token")
        let sent = try await api.detail(key: .init(id: 71, direction: .sent), token: "synthetic-token")
        XCTAssertEqual(received.row.partner?.name, "Sample receiving partner")
        XCTAssertEqual(sent.row.partner?.name, "Sample sent merchant")
        XCTAssertEqual(received.occupancy?.kind, .gamePending)
        XCTAssertEqual(received.occupancy?.count, 2)
        XCTAssertEqual(received.occupancy?.capacity, 4)
        XCTAssertEqual(sent.occupancy?.kind, .topicAccepted)
        let requests = await t.requests
        XCTAssertEqual(requests.count, 2, "Do not request slots separately or trust a cached row")
        XCTAssertTrue(requests.allSatisfy { $0.url?.path == "/test/api/coop/list" })
    }
    func testDirectionAbsenceAndDuplicateIdentityCannotResolveWrongInvitation() async throws {
        for (json, expected) in [
            (#"{"code":200,"data":{"sent":[{"id":7}],"received":[]}}"#, CooperationReadFailure.unavailable),
            (#"{"code":200,"data":{"received":[{"id":7},{"id":7}]}}"#, .ambiguousIdentity)
        ] {
            let t = CooperationTransport(["/api/coop/list": .init(json: json)])
            do { _ = try await service(t).detail(key: .init(id: 7, direction: .received), token: "synthetic-token"); XCTFail() }
            catch { XCTAssertEqual(error as? CooperationReadFailure, expected) }
        }
    }
    func testDistinctApplicationAndRegistrationEnvelopesAndHistory() async throws {
        let t = fixtureTransport(); let api = try service(t)
        let applies = try await api.applications(direction: .sent, token: "synthetic-token")
        XCTAssertEqual(applies.first?.status, 2)
        let regs = try await api.registrations(token: "synthetic-token")
        XCTAssertEqual(regs.rows.first?.id, 91); XCTAssertEqual(regs.hasMore, true)
        let received = try await api.applications(direction: .received, token: "synthetic-token")
        XCTAssertEqual(received.first?.scope, "MERCHANT")
        for (path, json) in [
            ("/api/coop/pool/mine", #"{"code":200,"data":{"rows":[]}}"#),
            ("/api/coop/candidates/received", #"{"code":200,"data":[]}"#)
        ] {
            let broken = CooperationTransport([path: .init(json: json)])
            do {
                if path.contains("pool") { _ = try await service(broken).applications(direction: .sent, token: "synthetic-token") }
                else { _ = try await service(broken).registrations(token: "synthetic-token") }
                XCTFail("Wrong envelope must not become empty success")
            } catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
        }
    }
    func testInboxIndependentSectionsPreserveSuccessAndPartialEmpty() async throws {
        for empty in [false, true] {
            let t = CooperationTransport([
                "/api/coop/list": .init(json: empty ? #"{"code":200,"data":{}}"# : CooperationSyntheticFixtures.invitationsJSON),
                "/api/coop/pool/received": .init(json: empty ? #"{"code":200,"data":[]}"# : CooperationSyntheticFixtures.receivedApplicationsJSON),
                "/api/coop/candidates/received": .init(json: #"{"code":500,"msg":"Registrations unavailable"}"#)
            ])
            let result = try await service(t).inbox(direction: .received, token: "synthetic-token")
            XCTAssertTrue(result.isPartial)
            if case .content(let list) = result.invitations { XCTAssertEqual(list.received.count, empty ? 0 : 3) } else { XCTFail() }
            if case .content(let rows) = result.applications { XCTAssertEqual(rows.count, empty ? 0 : 1) } else { XCTFail() }
            if case .failure(let issue)? = result.registrations { XCTAssertEqual(issue, .server("Registrations unavailable")) } else { XCTFail() }
        }
    }
    func testSentInboxDoesNotReadReceivedRegistrationsOrOpenPool() async throws {
        let t = fixtureTransport()
        let result = try await service(t).inbox(direction: .sent, token: "synthetic-token")
        XCTAssertNil(result.registrations)
        let requests = await t.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertFalse(requests.contains { $0.url?.path.contains("candidates") == true || $0.url?.path.contains("pool/list") == true })
    }
    func testCurrentUnauthorizedSiblingClosesWholeInboxBeforeMalformedProseOrPayload() async throws {
        for path in ["/api/coop/list", "/api/coop/pool/received", "/api/coop/candidates/received"] {
            for http in [false, true] {
                let t = CooperationTransport([path: .init(json: http ? "bad" : #"{"code":401,"msg":{},"data":"bad"}"#, status: http ? 401 : 200)])
                do { _ = try await service(t).inbox(direction: .received, token: "synthetic-token"); XCTFail() }
                catch { XCTAssertEqual(error as? APIError, .unauthorized) }
            }
        }
    }
    func testCandidateOwnerDenialAnd403ArePermissionStatesWithoutRetry() async throws {
        for reply in [CooperationTransport.Reply(json: #"{"code":500,"msg":"仅主题发布者可查看候选池"}"#), .init(json: #"{"code":403,"msg":"Permission denied"}"#), .init(json: "bad", status: 403)] {
            let t = CooperationTransport(["/api/coop/candidates": reply])
            do { _ = try await service(t).candidates(topicID: 301, token: "synthetic-token"); XCTFail() }
            catch {
                let issue = CooperationIssue(error)
                if case .forbidden = issue {} else { XCTFail("Expected permission state") }
                XCTAssertFalse(issue.canRetry)
            }
        }
    }
    func testServerProseSurvivesBusinessAndHTTPFailuresWithoutInventedPermission() async throws {
        for reply in [CooperationTransport.Reply(json: #"{"code":500,"msg":"Sample server explanation"}"#), .init(json: #"{"msg":"Sample server explanation"}"#, status: 503)] {
            let t = CooperationTransport(["/api/coop/pool/list": reply])
            do { _ = try await service(t).pool(token: "synthetic-token"); XCTFail() }
            catch { XCTAssertEqual(CooperationIssue(error), .server("Sample server explanation")) }
        }
        XCTAssertTrue(CooperationIssue.server("Sample server explanation").canRetry)
        XCTAssertFalse(CooperationIssue.unavailable.canRetry)
    }
    func testUnknownStatusAmountsContactsAndSourceTimesRemainHonest() throws {
        let row = try decode(CooperationInvite.self, #"{"id":7,"status":99,"inviteType":2,"shareMode":2,"depositOwed":true,"expireTime":"2026-10-10 12:00:00"}"#)
        XCTAssertEqual(row.statusKey, "cooperation.status.unknown")
        XCTAssertNil(row.fixedFee); XCTAssertNil(row.depositAmount); XCTAssertNil(row.partner)
        XCTAssertTrue(row.legacyReadonly)
        XCTAssertEqual(row.expireTime, .text("2026-10-10 12:00:00"))
        XCTAssertNil(row.expireTime?.date)
        let timestamp = try decode(CooperationSourceTime.self, "1000")
        XCTAssertEqual(timestamp.date, Date(timeIntervalSince1970: 1))
        let supplied = try decode(CooperationInvite.self, #"{"id":8,"status":0,"partner":{"phone":"SYNTHETIC"},"depositAmount":0}"#)
        XCTAssertEqual(supplied.partner?.phone, "SYNTHETIC", "Source returned contact fields are not guessed from status")
        XCTAssertEqual(supplied.depositAmount, 0, "A supplied zero is different from absence")
    }
    func testAllPoolStatesNoClubAndUnknownMustNotDefaultToOpen() throws {
        for state in ["open", "applied", "invited", "taken", "cooped", "converted", "declined", "withdrawn"] {
            let row = try decode(CooperationPoolItem.self, "{\"topicId\":7,\"state\":\"\(state)\"}")
            XCTAssertEqual(row.stateKey, "cooperation.pool.state.\(state)")
        }
        for json in [#"{"topicId":7}"#, #"{"topicId":7,"state":"future"}"#] {
            XCTAssertEqual(try decode(CooperationPoolItem.self, json).stateKey, "cooperation.status.unknown")
        }
        let pool = try decode(CooperationPool.self, #"{"rows":[{"topicId":7}],"hasClub":false}"#)
        XCTAssertFalse(pool.hasClub)
    }
    func testCoverFallbackAndMissingSlotsNeverInventZero() throws {
        let list = try decode(CooperationInvites.self, #"{"received":[{"id":7,"topicId":3,"gameId":4,"cover":" ","topicCover":"source-cover","topicImgUrl":"other-cover"}],"slots":{"byGame":{"4":{"pending":2}},"byTopic":{"3":{"accepted":1,"cap":5}}}}"#)
        XCTAssertEqual(list.received.first?.coverURL, "source-cover")
        XCTAssertNil(list.occupancy(for: list.received[0]), "Malformed game slot must not be presented as a different topic slot")
    }
    func testMalformedRowsPayloadAndMissingDataFailClosed() async throws {
        for json in [#"{"code":200}"#, #"{"code":200,"data":null}"#, #"{"code":200,"data":[]}"#, #"{"code":200,"data":{"received":[3]}}"#, #"{"code":200,"data":{"received":[{}]}}"#, #"{"code":200,"data":{"received":[{"id":0}]}}"#, #"{"code":200,"data":{"received":[{"id":7,"status":"0"}]}}"#] {
            let t = CooperationTransport(["/api/coop/list": .init(json: json)])
            do { _ = try await service(t).invitations(token: "synthetic-token"); XCTFail(json) }
            catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
        }
    }
    func testInvalidInputAndTokenNeverDispatch() async throws {
        let t = fixtureTransport(); let api = try service(t)
        do { _ = try await api.detail(key: .init(id: 0, direction: .sent), token: "synthetic-token"); XCTFail() } catch { XCTAssertEqual(error as? APIError, .invalidRequest) }
        do { _ = try await api.candidates(topicID: -1, token: "synthetic-token"); XCTFail() } catch { XCTAssertEqual(error as? APIError, .invalidRequest) }
        do { _ = try await api.invitations(token: "bad\ntoken"); XCTFail() } catch { XCTAssertEqual(error as? APIError, .invalidRequest) }
        let requests = await t.requests; XCTAssertTrue(requests.isEmpty)
    }
    @MainActor func testGuestAndUnconfiguredNeverDispatch() async throws {
        let t = fixtureTransport()
        let guest = CooperationSessionReader(service: try service(t), currentSession: { nil })
        do { _ = try await guest.pool(); XCTFail() } catch { XCTAssertEqual(error as? APIError, .unauthorized) }
        let session = try CooperationReadSession(accountID: 1, epoch: 1, token: "synthetic-token")
        let missing = CooperationSessionReader(service: nil, currentSession: { session })
        do { _ = try await missing.pool(); XCTFail() } catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        let requests = await t.requests; XCTAssertTrue(requests.isEmpty)
    }
    @MainActor func testLateSuccessAnd401CannotCrossAccountTokenEpochOrSignOut() async throws {
        let first = try CooperationReadSession(accountID: 1, epoch: 1, token: "synthetic-first")
        let nextSessions: [CooperationReadSession?] = [nil,
            try CooperationReadSession(accountID: 2, epoch: 1, token: "synthetic-first"),
            try CooperationReadSession(accountID: 1, epoch: 2, token: "synthetic-first"),
            try CooperationReadSession(accountID: 1, epoch: 1, token: "synthetic-next")]
        for next in nextSessions {
            for unauthorized in [false, true] {
                var current: CooperationReadSession? = first
                var invalidations = 0
                let t = CooperationSuspendedTransport()
                let reader = CooperationSessionReader(service: try service(t), currentSession: { current }, onUnauthorized: { _ in invalidations += 1 })
                let scope = reader.scope
                let task = Task { try await reader.detail(key: .init(id: 71, direction: .received)) }
                await t.waitForRequests(1)
                current = next
                XCTAssertNotEqual(scope, reader.scope)
                await t.finish(unauthorized ? #"{"code":401}"# : CooperationSyntheticFixtures.invitationsJSON)
                do { _ = try await task.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
                XCTAssertEqual(invalidations, 0)
            }
        }
    }
    @MainActor func testCancelledAndLateInboxCannotInvalidateReplacementSession() async throws {
        let first = try CooperationReadSession(accountID: 1, epoch: 1, token: "synthetic-first")
        for cancel in [false, true] {
            var current: CooperationReadSession? = first
            var invalidations = 0
            let t = CooperationSuspendedTransport()
            let reader = CooperationSessionReader(service: try service(t), currentSession: { current }, onUnauthorized: { _ in invalidations += 1 })
            let task = Task { try await reader.inbox(direction: .received) }
            await t.waitForRequests(3)
            if cancel { task.cancel() } else { current = nil }
            await t.finish(#"{"code":401}"#)
            do { _ = try await task.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
            XCTAssertEqual(invalidations, 0)
        }
    }
    @MainActor func testCurrentUnauthorizedInboxInvalidatesOnce() async throws {
        let session = try CooperationReadSession(accountID: 1, epoch: 1, token: "synthetic-token")
        let t = CooperationTransport(["/api/coop/list": .init(json: #"{"code":401}"#), "/api/coop/pool/received": .init(json: #"{"code":401}"#), "/api/coop/candidates/received": .init(json: #"{"code":401}"#)])
        var invalidations = 0
        let reader = CooperationSessionReader(service: try service(t), currentSession: { session }, onUnauthorized: { _ in invalidations += 1 })
        do { _ = try await reader.inbox(direction: .received); XCTFail() } catch { XCTAssertEqual(error as? APIError, .unauthorized) }
        XCTAssertEqual(invalidations, 1)
    }
    @MainActor func testReadModelClearsFreshReadsRejectsOverlapAndPreservesNavigationRows() async throws {
        let model = CooperationReadModel<String>()
        var scope = UUID()
        await model.load(scope: scope, currentScope: { scope }) { "first" }
        XCTAssertEqual(model.visibleValue(scope: scope), "first")
        var pending: CheckedContinuation<String, Error>?
        let captured = scope
        let old = Task { await model.load(scope: captured, currentScope: { scope }) { try await withCheckedThrowingContinuation { pending = $0 } } }
        while pending == nil { await Task.yield() }
        XCTAssertNil(model.visibleValue(scope: scope)); XCTAssertTrue(model.isLoading)
        await model.load(scope: scope, currentScope: { scope }) { "newer" }
        pending?.resume(returning: "old"); await old.value
        XCTAssertEqual(model.visibleValue(scope: scope), "newer")
        model.cancelPending(); XCTAssertEqual(model.visibleValue(scope: scope), "newer")
        scope = UUID(); XCTAssertNil(model.visibleValue(scope: scope))
        await model.load(scope: scope, currentScope: { scope }) { throw CooperationReadFailure.forbidden(message: "Denied") }
        XCTAssertNil(model.visibleValue(scope: scope)); XCTAssertEqual(model.visibleIssue(scope: scope), .forbidden("Denied"))
        model.invalidate(); XCTAssertNil(model.visibleIssue(scope: scope))
    }
}
