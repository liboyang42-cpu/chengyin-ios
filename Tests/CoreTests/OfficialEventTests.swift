import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class OfficialTestTransport: HTTPTransport {
    var json: String
    var status: Int
    var requests: [URLRequest] = []
    init(_ json: String = #"{"code":200,"data":[]}"#, status: Int = 200) { self.json = json; self.status = status }
    func send(_ request: URLRequest) async throws -> (Data, Int) { requests.append(request); return (Data(json.utf8), status) }
}
private actor OfficialSuspendedTransport: HTTPTransport {
    private var continuation: CheckedContinuation<(Data, Int), Error>?
    private(set) var requests: [URLRequest] = []
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }
    // The service runs off MainActor. Keep registration, readiness and completion
    // on one executor instead of racing the test's read against send's write.
    func waitForRequest() async { while continuation == nil { await Task.yield() } }
    func finish(_ json: String, status: Int = 200) {
        let pending = continuation
        continuation = nil
        pending?.resume(returning: (Data(json.utf8), status))
    }
}
final class OfficialEventTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T { try JSONDecoder().decode(type, from: Data(json.utf8)) }
    private func service(_ transport: any HTTPTransport) throws -> OfficialEventService {
        try OfficialEventService(configuration: APIConfiguration(baseURL: URL(string: "https://example.com/test/")!), transport: transport)
    }
    func testPublicGETCityQueryIsEncodedAndGuestHasNoAuth() async throws {
        let t = OfficialTestTransport()
        _ = try await service(t).events(city: "Example & town/城")
        let request = try XCTUnwrap(t.requests.first)
        XCTAssertEqual(request.httpMethod, "GET"); XCTAssertEqual(request.url?.path, "/test/api/official/events")
        let parts = try XCTUnwrap(URLComponents(url: XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
        XCTAssertEqual(parts.queryItems, [URLQueryItem(name: "city", value: "Example & town/城")])
        XCTAssertNil(request.httpBody); XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(request.value(forHTTPHeaderField: "Content-Type"))
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
    }
    func testExactReadRoutesAndRawAuthorization() async throws {
        let t = OfficialTestTransport(); let api = try service(t)
        _ = try await api.events(token: "synthetic-token")
        t.json = #"{"code":200,"data":{"id":71,"title":"Synthetic"}}"#
        _ = try await api.detail(id: 71, token: "synthetic-token")
        t.json = #"{"code":200,"data":[]}"#
        _ = try await api.myEvents(token: "synthetic-token"); _ = try await api.partyInbox(token: "synthetic-token")
        t.json = #"{"code":200,"data":{"canPublish":true}}"#
        let permission = try await api.canPublish(token: "synthetic-token")
        XCTAssertTrue(permission)
        t.json = #"{"code":200,"data":{}}"#
        _ = try await api.myPublished(token: "synthetic-token"); _ = try await api.broadcastStats(id: 91, token: "synthetic-token")
        XCTAssertEqual(t.requests.compactMap { $0.url?.path }, ["/test/api/official/events", "/test/api/official/events/71", "/test/api/official/my-events", "/test/api/official/v2/party-inbox", "/test/api/official/can-publish", "/test/api/official/my-published", "/test/api/official/broadcast/91/stats"])
        for request in t.requests {
            XCTAssertEqual(request.httpMethod, "GET"); XCTAssertNil(request.httpBody)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "synthetic-token")
        }
    }
    func testInboxAcceptsOnlySourceBareArrayOrDataRowsAndReadsStatusNotState() async throws {
        for payload in [OfficialEventSyntheticFixtures.inboxJSON, "{\"rows\":\(OfficialEventSyntheticFixtures.inboxJSON)}"] {
            let result = try await service(OfficialTestTransport("{\"code\":200,\"data\":\(payload)}")).partyInbox(token: "synthetic")
            XCTAssertEqual(result.map(\.id), [81,82,83,84]); XCTAssertEqual(result[1].status, "ACCEPTED")
            XCTAssertNil(result[3].status); XCTAssertEqual(result[3].statusKey, "official.status.unknown")
        }
        do { _ = try await service(OfficialTestTransport(#"{"code":200,"rows":[]}"#)).partyInbox(token: "synthetic"); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
    }
    func testMalformedEnvelopeIsNeverAnEmptySuccess() async throws {
        for json in ["html", #"{"data":[]}"#, #"{"code":200,"data":null}"#, #"{"code":200,"data":{"rows":[]}}"#] {
            do { _ = try await service(OfficialTestTransport(json)).events(); XCTFail(json) }
            catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
        }
    }
    func testBusinessPermissionAndOwnershipStatesPrecedePayloadDecoding() async throws {
        for (json, status, failure) in [(#"{"code":500,"msg":"无官方发布权限","data":"bad"}"#, 200, OfficialReadFailure.noPublisherPermission), (#"{"code":403,"data":null}"#, 200, .forbidden), (#"{"code":500,"msg":"Other failure"}"#, 200, .rejected(500))] {
            do { _ = try await service(OfficialTestTransport(json, status: status)).myPublished(token: "synthetic"); XCTFail() }
            catch { XCTAssertEqual(error as? OfficialReadFailure, failure) }
        }
        do { _ = try await service(OfficialTestTransport(#"{"code":500,"msg":"通知不存在"}"#)).broadcastStats(id: 91, token: "synthetic"); XCTFail() }
        catch { XCTAssertEqual(error as? OfficialReadFailure, .unavailable) }
    }
    func testHTTPAndBodyUnauthorizedAreNotBusinessOrDecodeErrors() async throws {
        for (json, status) in [("html", 401), (#"{"code":401,"data":"bad"}"#, 200)] {
            do { _ = try await service(OfficialTestTransport(json, status: status)).events(); XCTFail() }
            catch { XCTAssertEqual(error as? APIError, .unauthorized) }
        }
    }
    func testDetailRejectsWrongIdentityAndMissingEventBusinessCode() async throws {
        for json in [#"{"code":200,"data":{"id":72,"title":"wrong"}}"#, #"{"code":200,"data":{"id":71,"title":" "}}"#, #"{"code":500,"msg":"活动不存在"}"#] {
            do { _ = try await service(OfficialTestTransport(json)).detail(id: 71); XCTFail() }
            catch { XCTAssertEqual(error as? OfficialReadFailure, .unavailable) }
        }
    }
    func testInvalidInputsNeverReachTransport() async throws {
        let t = OfficialTestTransport(); let api = try service(t)
        do { _ = try await api.detail(id: 0); XCTFail() } catch { XCTAssertEqual(error as? APIError, .invalidRequest) }
        do { _ = try await api.broadcastStats(id: -1, token: "synthetic"); XCTFail() } catch { XCTAssertEqual(error as? APIError, .invalidRequest) }
        for token in ["", "   ", "x\r\ny"] {
            do { _ = try await api.myEvents(token: token); XCTFail() } catch { XCTAssertEqual(error as? APIError, .invalidRequest) }
        }
        XCTAssertTrue(t.requests.isEmpty)
    }
    func testListDropsIncompleteAndDuplicateRecords() async throws {
        let t = OfficialTestTransport(#"{"code":200,"data":[{}, {"id":71,"title":""},{"id":0,"title":"bad"},{"id":72,"title":"Good"},{"id":72,"title":"Duplicate"}]}"#)
        let rows = try await service(t).events()
        XCTAssertEqual(rows.map(\.id), [72]); XCTAssertEqual(rows.first?.title, "Good")
    }
    func testSourceBucketsAndKeywordUseStatusNotDates() throws {
        let rows = try decode([OfficialEvent].self, OfficialEventSyntheticFixtures.eventsJSON)
        XCTAssertEqual(OfficialEventFilter.visible(rows, bucket: .live).map(\.id), [71,74])
        XCTAssertEqual(OfficialEventFilter.visible(rows, bucket: .upcoming).map(\.id), [72])
        XCTAssertEqual(OfficialEventFilter.visible(rows, bucket: .ended).map(\.id), [73])
        XCTAssertEqual(OfficialEventFilter.visible(rows, bucket: .mine).count, 4)
        XCTAssertEqual(OfficialEventFilter.visible(rows, bucket: .live, keyword: "  EXAMPLE CITY ").map(\.id), [71])
        XCTAssertEqual(OfficialEventFilter.visible(rows, bucket: .live, keyword: "offline").map(\.id), [71])
        let missing = try decode(OfficialEvent.self, #"{"id":99,"title":"No status","activityStart":"2000-01-01"}"#)
        XCTAssertFalse(OfficialEventBucket.live.includes(missing)); XCTAssertEqual(missing.statusKey, "official.status.unknown")
    }
    func testMissingFactsAreUnknownAndFlagsMatchSource() throws {
        let missing = try decode(OfficialEvent.self, #"{"id":71,"title":"Synthetic"}"#)
        XCTAssertNil(missing.status); XCTAssertNil(missing.participants); XCTAssertNil(missing.signed)
        XCTAssertNil(missing.activityStart); XCTAssertTrue(missing.rewards.isEmpty)
        for raw in ["true", "1", "\"1\""] {
            let value = try decode(OfficialEvent.self, "{\"id\":71,\"title\":\"Synthetic\",\"bannerEnabled\":\(raw),\"signed\":1}")
            XCTAssertTrue(value.bannerEnabled); XCTAssertNil(value.signed)
        }
    }
    func testInformationWarningFieldsAreStrictOptionalServerFacts() throws {
        let missing = try decode(OfficialEvent.self, #"{"id":71,"title":"Synthetic"}"#)
        XCTAssertNil(missing.recruitmentBlocked); XCTAssertNil(missing.recruitmentBlockedReason)
        XCTAssertNil(missing.recruitmentWarningReason)
        for (raw, expected) in [("true", Optional(true)), ("false", Optional(false)), ("null", nil), ("1", nil), ("0", nil), ("\"true\"", nil), ("\"1\"", nil), ("{}", nil), ("[]", nil)] {
            let event = try decode(OfficialEvent.self, "{\"id\":71,\"title\":\"Synthetic\",\"recruitmentBlocked\":\(raw),\"recruitmentBlockedReason\":\"Synthetic reason\"}")
            XCTAssertEqual(event.recruitmentBlocked, expected, raw)
            XCTAssertEqual(event.recruitmentBlockedReason, "Synthetic reason", raw)
            XCTAssertEqual(event.recruitmentWarningReason, expected == true ? "Synthetic reason" : nil, raw)
        }
    }
    func testExplicitInformationWarningTrimsOnlyOuterReasonWhitespace() throws {
        let event = try decode(OfficialEvent.self, #"{"id":71,"title":"Synthetic","recruitmentBlocked":true,"recruitmentBlockedReason":" \nSynthetic [source] reason.\n保留来源说明。\t "}"#)
        XCTAssertEqual(event.recruitmentBlockedReason, " \nSynthetic [source] reason.\n保留来源说明。\t ")
        XCTAssertEqual(event.recruitmentWarningReason, "Synthetic [source] reason.\n保留来源说明。")
    }
    func testMissingBlankOrMalformedWarningReasonNeverInventsExplanation() throws {
        let missing = try decode(OfficialEvent.self, #"{"id":71,"title":"Synthetic","recruitmentBlocked":true}"#)
        XCTAssertEqual(missing.recruitmentBlocked, true); XCTAssertNil(missing.recruitmentWarningReason)
        for raw in ["null", "\"\"", "\" \\n\\t \"", "false", "7", "{}", "[]"] {
            let event = try decode(OfficialEvent.self, "{\"id\":71,\"title\":\"Synthetic\",\"recruitmentBlocked\":true,\"recruitmentBlockedReason\":\(raw)}")
            XCTAssertEqual(event.recruitmentBlocked, true, raw)
            XCTAssertNil(event.recruitmentWarningReason, raw)
        }
    }
    func testReasonAloneAndUnrelatedFlagsCannotCreateInformationWarning() throws {
        for fields in [#""recruitmentBlockedReason":"Synthetic reason""#, #""paused":true,"eligible":false,"recruitmentBlockedReason":"Synthetic reason""#] {
            let event = try decode(OfficialEvent.self, "{\"id\":71,\"title\":\"Synthetic\",\(fields)}")
            XCTAssertNil(event.recruitmentBlocked); XCTAssertNil(event.recruitmentWarningReason)
        }
    }
    func testInformationWarningCannotChangeEventIdentityStatusOrParticipation() throws {
        for status in [1, 2, 3, 4, 5, 9] {
            for signed in [false, true] {
                let fields = "\"id\":71,\"title\":\"Synthetic\",\"status\":\(status),\"signed\":\(signed),\"eligible\":true,\"paused\":false"
                let original = try decode(OfficialEvent.self, "{\(fields)}")
                let marked = try decode(OfficialEvent.self, "{\(fields),\"recruitmentBlocked\":true,\"recruitmentBlockedReason\":\"Synthetic reason\"}")
                XCTAssertEqual(marked.id, original.id); XCTAssertEqual(marked.isCompleteRecord, original.isCompleteRecord)
                XCTAssertEqual(marked.statusKey, original.statusKey); XCTAssertEqual(marked.participationKey, original.participationKey)
                XCTAssertEqual(marked.eligible, original.eligible); XCTAssertEqual(marked.paused, original.paused)
                XCTAssertEqual(marked.signed, original.signed)
                for bucket in OfficialEventBucket.allCases {
                    XCTAssertEqual(bucket.includes(marked), bucket.includes(original))
                }
            }
        }
    }
    func testPublicReadKeepsMarkedRowsAndExistingDuplicateIdentityRules() async throws {
        let transport = OfficialTestTransport(#"{"code":200,"data":[{"id":71,"title":"Synthetic marked","status":3,"recruitmentBlocked":true,"recruitmentBlockedReason":"Synthetic reason"},{"id":71,"title":"Duplicate","status":3},{"id":72,"title":"Synthetic unmarked","status":3,"recruitmentBlocked":false},{"id":73,"title":"Synthetic unknown","status":3,"recruitmentBlocked":"true"},{"id":0,"title":"Invalid","recruitmentBlocked":true}]}"#)
        let rows = try await service(transport).events()
        XCTAssertEqual(rows.map(\.id), [71, 72, 73])
        XCTAssertEqual(OfficialEventFilter.visible(rows, bucket: .live).map(\.id), [71, 72, 73])
        XCTAssertEqual(rows[0].recruitmentWarningReason, "Synthetic reason")
        XCTAssertEqual(rows[1].recruitmentBlocked, false); XCTAssertNil(rows[2].recruitmentBlocked)
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(transport.requests.count, 1); XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.path, "/test/api/official/events"); XCTAssertNil(request.httpBody)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }
    func testSourceDatesV2MissionsAndCollectiveAreServerFacts() throws {
        let event = try decode(OfficialEvent.self, OfficialEventSyntheticFixtures.eventJSON)
        XCTAssertTrue(event.isV2); XCTAssertEqual(event.completedMissionCount, 1)
        XCTAssertEqual(event.missions.first?.code, "sample-arrival")
        XCTAssertEqual(event.activityStart, .text("2030-01-01 10:00:00"))
        XCTAssertEqual(event.activityEnd, .milliseconds(1893549600000))
        XCTAssertEqual(event.collective?.displayFraction, 0.12)
        XCTAssertFalse(event.hasCollectiveReward)
    }
    func testRewardsNeverInventDefaultsOrThrowOnBadJSON() throws {
        for raw in ["{bad", "[]", "{}"] {
            let json = try JSONSerialization.data(withJSONObject: ["id":71,"title":"Synthetic","rewardJson":raw])
            let event = try JSONDecoder().decode(OfficialEvent.self, from: json)
            XCTAssertTrue(event.rewards.isEmpty); XCTAssertFalse(event.hasCollectiveReward)
        }
        let source = try decode(OfficialEvent.self, OfficialEventSyntheticFixtures.eventJSON)
        XCTAssertEqual(source.rewards, [.badge, .experience("25")])
    }
    func testPausedAndEndedPrecedeSignedV2Arrival() throws {
        let source = OfficialEventSyntheticFixtures.eventJSON
        let paused = try decode(OfficialEvent.self, source.replacingOccurrences(of: "\"paused\":false", with: "\"paused\":true"))
        XCTAssertEqual(paused.participationKey, "official.status.paused")
        let ended = try decode(OfficialEvent.self, source.replacingOccurrences(of: "\"status\":3", with: "\"status\":5").replacingOccurrences(of: "\"paused\":false", with: "\"paused\":true"))
        XCTAssertEqual(ended.participationKey, "official.status.ended")
        XCTAssertEqual(try decode(OfficialEvent.self, source).participationKey, "official.participation.arrival")
    }
    func testStatsPreserveUnknownScalarsAndOmitNestedValues() throws {
        let stats = try decode(OfficialBroadcastStats.self, OfficialEventSyntheticFixtures.statsJSON)
        XCTAssertEqual(stats.rows.map(\.id), ["clicks","enabled","reach","reads","sourceLabel","unmappedMetric"])
        XCTAssertEqual(stats.rows.first?.value, .number(2))
    }
    @MainActor func testGuestPrivateReadsMakeNoRequestsAndCannotPublish() async throws {
        let t = OfficialTestTransport()
        let reader = OfficialSessionReader(service: try service(t), currentContext: { OfficialReadContext(guestEpoch: 1) })
        do { _ = try await reader.myEvents(); XCTFail() } catch { XCTAssertEqual(error as? APIError, .unauthorized) }
        do { _ = try await reader.partyInbox(); XCTFail() } catch { XCTAssertEqual(error as? APIError, .unauthorized) }
        do { _ = try await reader.myPublished(); XCTFail() } catch { XCTAssertEqual(error as? APIError, .unauthorized) }
        do { _ = try await reader.broadcastStats(id: 91); XCTFail() } catch { XCTAssertEqual(error as? APIError, .unauthorized) }
        let permission = try await reader.canPublish(); XCTAssertFalse(permission)
        XCTAssertTrue(t.requests.isEmpty)
    }
    @MainActor func testAccountEpochTokenAndGuestTransitionsDropSuccessAnd401() async throws {
        let first = try OfficialReadContext(accountID: 1, epoch: 1, token: "synthetic-first")
        let transitions = [OfficialReadContext(guestEpoch: 2), try OfficialReadContext(accountID: 2, epoch: 1, token: "synthetic-first"), try OfficialReadContext(accountID: 1, epoch: 2, token: "synthetic-first"), try OfficialReadContext(accountID: 1, epoch: 1, token: "synthetic-rotated")]
        for next in transitions {
            for unauthorized in [false, true] {
                var current = first; var expirations = 0
                let t = OfficialSuspendedTransport()
                let reader = OfficialSessionReader(service: try service(t), currentContext: { current }, onUnauthorized: { _ in expirations += 1 })
                let scope = reader.scope
                let task = Task { try await reader.myEvents() }
                await t.waitForRequest()
                current = next
                XCTAssertNotEqual(scope, reader.scope)
                await t.finish(unauthorized ? #"{"code":401}"# : #"{"code":200,"data":[]}"#)
                do { _ = try await task.value; XCTFail("Stale completion accepted") } catch { XCTAssertTrue(error is CancellationError) }
                XCTAssertEqual(expirations, 0)
            }
        }
    }
    @MainActor func testGuestEpochChangeInvalidatesPublicReadEvenAfterRoundTrip() async throws {
        var current = OfficialReadContext(guestEpoch: 1)
        let t = OfficialSuspendedTransport()
        let reader = OfficialSessionReader(service: try service(t), currentContext: { current })
        let task = Task { try await reader.events() }
        await t.waitForRequest()
        current = OfficialReadContext(guestEpoch: 3) // Host advanced epoch for intervening login/logout.
        await t.finish(#"{"code":200,"data":[]}"#)
        do { _ = try await task.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
    }
    @MainActor func testCancelledReadNeverExpiresCurrentSession() async throws {
        let context = try OfficialReadContext(accountID: 1, epoch: 1, token: "synthetic")
        let t = OfficialSuspendedTransport(); var expirations = 0
        let reader = OfficialSessionReader(service: try service(t), currentContext: { context }, onUnauthorized: { _ in expirations += 1 })
        let task = Task { try await reader.myEvents() }
        await t.waitForRequest()
        task.cancel(); await t.finish(#"{"code":401}"#)
        do { _ = try await task.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(expirations, 0)
    }
    func testSuspendedTransportConsumesEachReplyOnceAndCanBeReused() async throws {
        let transport = OfficialSuspendedTransport()
        let request = URLRequest(url: URL(string: "https://example.com/test/")!)
        for (json, status) in [(#"{"code":401}"#, 401), (#"{"code":200,"data":[]}"#, 200)] {
            let task = Task { try await transport.send(request) }
            await transport.waitForRequest()
            await transport.finish(json, status: status)
            await transport.finish("duplicate must not resume the same continuation", status: 500)
            let (data, receivedStatus) = try await task.value
            XCTAssertEqual(data, Data(json.utf8))
            XCTAssertEqual(receivedStatus, status)
        }
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 2)
    }
    @MainActor func testCurrent401ExpiresExactlyTheCapturedContext() async throws {
        let context = try OfficialReadContext(accountID: 1, epoch: 7, token: "synthetic")
        var expired: [OfficialReadContext] = []
        let reader = OfficialSessionReader(service: try service(OfficialTestTransport(#"{"code":401}"#)), currentContext: { context }, onUnauthorized: { expired.append($0) })
        do { _ = try await reader.myEvents(); XCTFail() } catch { XCTAssertEqual(error as? APIError, .unauthorized) }
        XCTAssertEqual(expired, [context])
    }
    @MainActor func testUnconfiguredGuestStillGetsPrivateLoginState() async throws {
        let reader = OfficialSessionReader(service: nil, currentContext: { OfficialReadContext(guestEpoch: 0) })
        do { _ = try await reader.events(); XCTFail() } catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        do { _ = try await reader.myEvents(); XCTFail() } catch { XCTAssertEqual(error as? APIError, .unauthorized) }
    }
}
