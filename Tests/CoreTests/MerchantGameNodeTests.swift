import Foundation
import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private func gameNodeValue(_ json: String) throws -> MerchantContentValue { try JSONDecoder().decode(MerchantContentValue.self, from: Data(json.utf8)) }

private let gameNodeStation = #"{"stationId":6,"nodeId":8,"nodeName":"Sample","stationCode":"S-8","status":"ACTIVE","revision":4,"preparationChecklist":[{"code":"B","label":"Second","checked":true},{"code":"A","label":"First","checked":true}],"playerTask":{"taskCode":"T","prompt":"Sample prompt","inputType":"scan"},"capacity":12,"serviceStartAt":"2026-10-20 10:00:00","serviceEndAt":"2026-10-20 18:00","pendingVerificationCount":2,"playable":true}"#

private func gameNodeProjection(status: String = "RUNNING", station: String = gameNodeStation, actions: String = #"["STATION_PAUSE","VERIFY_SUBMISSION"]"#,
                                fallback: String = #"[{"sourceNodeId":8,"planCode":"plan_a","planVersion":2,"nodeId":9,"nodeName":"Backup","playerMessage":"Go to backup"}]"#,
                                extra: String = "") -> String {
    #"{"perspective":"MERCHANT","sessionId":90,"activityId":71,"revision":5,"status":""# + status + #"","availableActions":"# + actions
        + #","merchant":{"stations":["# + station + #"],"fallbackOptions":"# + fallback + "}" + extra + "}"
}

final class MerchantGameNodeProjectionTests: XCTestCase {
    func testNormalizesStationExactlyLikeSource() throws {
        let p = try MerchantGameNodeProjection(gameNodeValue(gameNodeProjection()))
        let s = try XCTUnwrap(p.stations.first)
        XCTAssertEqual(p.playMode, .story); XCTAssertNil(p.authorityEpoch)
        XCTAssertEqual(s.preparationChecklist.map(\.code), ["B", "A"])
        XCTAssertEqual(s.playerTask?.inputType, "SCAN")
        XCTAssertTrue(s.playable, "seconds-bearing and minute server times must both be accepted")
        XCTAssertTrue(s.canPause); XCTAssertTrue(s.canVerify); XCTAssertFalse(s.canAccept)
        XCTAssertEqual(s.statusTextKey, "merchantGameNode.status.ACTIVE")
        XCTAssertEqual(p.fallbackOptions.first?.planCode, "PLAN_A")
    }
    func testRejectionReasonsKeepSourceCodes() throws {
        func reason(_ json: String) -> String? {
            do { _ = try MerchantGameNodeProjection(try gameNodeValue(json)); return nil } catch { return (error as? MerchantGameNodeRejection)?.rawValue }
        }
        XCTAssertEqual(reason("[]"), "EMPTY")
        XCTAssertEqual(reason(#"{"perspective":"PLAYER"}"#), "FORBIDDEN_PROJECTION")
        XCTAssertEqual(reason(#"{"perspective":"MERCHANT","merchant":{}}"#), "INVALID_MERCHANT_VIEW")
        XCTAssertEqual(reason(gameNodeProjection(status: "LIVE")), "INVALID_SESSION")
        XCTAssertEqual(reason(gameNodeProjection(actions: "null")), "INVALID_SESSION")
        XCTAssertEqual(reason(gameNodeProjection(fallback: #"[{"sourceNodeId":8,"planCode":"PLAN_A","planVersion":0,"nodeId":9,"nodeName":"B","playerMessage":"M"}]"#)), "INVALID_FALLBACK_OPTIONS")
        XCTAssertEqual(reason(gameNodeProjection(fallback: #"[{"sourceNodeId":8,"planCode":"","planVersion":2,"nodeId":9,"nodeName":"B","playerMessage":"M"}]"#)), "INVALID_FALLBACK_OPTIONS")
        XCTAssertEqual(reason(gameNodeProjection(fallback: #"[{"sourceNodeId":8,"planCode":"P_A","planVersion":2,"nodeId":8,"nodeName":"B","playerMessage":"M"}]"#)), "INVALID_FALLBACK_OPTIONS")
        let duplicate = #"{"sourceNodeId":8,"planCode":"P_A","planVersion":2,"nodeId":9,"nodeName":"B","playerMessage":"M"}"#
        XCTAssertEqual(reason(gameNodeProjection(fallback: "[" + duplicate + "," + duplicate + "]")), "INVALID_FALLBACK_OPTIONS")
        XCTAssertEqual(reason(gameNodeProjection(fallback: #"{}"#)), "INVALID_FALLBACK_OPTIONS")
        XCTAssertNil(reason(gameNodeProjection(fallback: "null")))
        XCTAssertEqual(reason(gameNodeProjection(station: gameNodeStation.replacingOccurrences(of: #""inputType":"scan""#, with: #""inputType":"VOICE""#))), "INVALID_STATION")
        XCTAssertEqual(reason(gameNodeProjection(station: gameNodeStation.replacingOccurrences(of: #""code":"A""#, with: #""code":"B""#))), "INVALID_STATION")
        XCTAssertEqual(reason(gameNodeProjection(station: gameNodeStation.replacingOccurrences(of: #""capacity":12"#, with: #""capacity":-1"#))), "INVALID_STATION")
    }
    func testRoutePlayModeAllowsEmptyChecklistAndSessionRulesGateFlags() throws {
        let empty = gameNodeStation.replacingOccurrences(of: #"[{"code":"B","label":"Second","checked":true},{"code":"A","label":"First","checked":true}]"#, with: "[]")
        let story = try MerchantGameNodeProjection(gameNodeValue(gameNodeProjection(station: empty)))
        XCTAssertFalse(story.stations[0].playable)
        let route = try MerchantGameNodeProjection(gameNodeValue(gameNodeProjection(station: empty).replacingOccurrences(of: #""merchant":{"#, with: #""merchant":{"playMode":"ROUTE","#)))
        XCTAssertTrue(route.stations[0].playable)
        let finished = try MerchantGameNodeProjection(gameNodeValue(gameNodeProjection(status: "FINISHED")))
        XCTAssertFalse(finished.stations[0].canPause); XCTAssertFalse(finished.stations[0].playable)
        let noPending = try MerchantGameNodeProjection(gameNodeValue(gameNodeProjection(station: gameNodeStation.replacingOccurrences(of: #""pendingVerificationCount":2"#, with: #""pendingVerificationCount":0"#))))
        XCTAssertFalse(noPending.stations[0].canVerify)
    }
    func testRecapRequiresNoPublicContentPolicy() throws {
        let recap = #","recap":{"arrivedPlayers":1,"submissionCount":1,"approvedCount":1,"rejectedCount":0,"recordedCount":0,"normalCompletedCount":1,"fallbackCompletedCount":0,"pauseEventCount":0,"authorizedContentCount":0,"contentPolicy":"NO_PUBLIC_CONTENT"}}"#
        let ok = try MerchantGameNodeProjection(gameNodeValue(gameNodeProjection(station: String(gameNodeStation.dropLast()) + recap)))
        XCTAssertEqual(ok.stations[0].recap?.arrivedPlayers, 1)
        let leaked = recap.replacingOccurrences(of: #""authorizedContentCount":0"#, with: #""authorizedContentCount":3"#)
        XCTAssertNil(try MerchantGameNodeProjection(gameNodeValue(gameNodeProjection(station: String(gameNodeStation.dropLast()) + leaked))).stations[0].recap)
    }
    func testSummaryStatesAndTones() throws {
        let playable = MerchantGameNodeSummary(try MerchantGameNodeProjection(gameNodeValue(gameNodeProjection())))
        XCTAssertEqual(playable.state, .playable); XCTAssertEqual(playable.tone, .ready)
        XCTAssertEqual(playable.textKey, "merchantGameNode.summary.playablePending"); XCTAssertEqual(playable.pendingVerificationCount, 2)
        let invited = gameNodeStation.replacingOccurrences(of: #""status":"ACTIVE""#, with: #""status":"INVITED""#)
        let summary = MerchantGameNodeSummary(try MerchantGameNodeProjection(gameNodeValue(gameNodeProjection(status: "PREPARING", station: invited))))
        XCTAssertEqual(summary.state, .invited); XCTAssertEqual(summary.tone, .pending)
        XCTAssertEqual(MerchantGameNodeSummary(nil).tone, .error)
    }
}

final class MerchantGameNodeCommandTests: XCTestCase {
    private func fixture(_ status: String = "RUNNING", station: String = gameNodeStation, actions: String = #"["STATION_PAUSE","VERIFY_SUBMISSION"]"#, extra: String = "") throws -> (MerchantGameNodeProjection, MerchantGameNodeStation) {
        let p = try MerchantGameNodeProjection(gameNodeValue(gameNodeProjection(status: status, station: station, actions: actions, extra: extra)))
        return (p, p.stations[0])
    }
    func testRequestIDFormatMatchesSource() {
        let id = MerchantGameNodeRequestID.make(action: .pause, activityID: 71, nodeID: 8, milliseconds: 1_760_000_000_000, random: "abc123")
        XCTAssertEqual(id, "game_pause_71_8_1760000000000_abc123")
        XCTAssertTrue(MerchantGameNodeRequestID.isValid(id))
        let long = MerchantGameNodeRequestID.make(action: .verify, activityID: 9_007_199_254_740_991, nodeID: 9_007_199_254_740_991, milliseconds: 1_760_000_000_000, random: "abcdef")
        XCTAssertEqual(long.utf8.count, 64)
        XCTAssertEqual(MerchantGameNodeRequestID.random6().count, 6)
    }
    func testDeclineSendsChosenSourceLabel() throws {
        let invited = gameNodeStation.replacingOccurrences(of: #""status":"ACTIVE""#, with: #""status":"INVITED""#)
        let (p, s) = try fixture("PREPARING", station: invited, actions: #"["STATION_ACCEPT","STATION_DECLINE"]"#)
        XCTAssertThrowsError(try MerchantGameNodeCommand.decline(p, s, draft: .init(), requestID: "game_decline_1"))
        let command = try MerchantGameNodeCommand.decline(p, s, draft: .init(reason: MerchantGameNodeReason.decline[0]), requestID: "game_decline_1")
        XCTAssertEqual(command.payload, ["reasonCode": .string("SCHEDULE_CONFLICT"), "reason": .string("档期冲突")])
        XCTAssertEqual(command.expectedRevision, 5)
    }
    func testReadyUsesServerChecklistOrderAndValidatesWindow() throws {
        let accepted = gameNodeStation.replacingOccurrences(of: #""status":"ACTIVE""#, with: #""status":"ACCEPTED""#)
        let (p, s) = try fixture("PREPARING", station: accepted, actions: #"["STATION_READY"]"#)
        var draft = MerchantGameNodeReadyDraft(checklist: [.init(code: "A", label: "First", checked: true), .init(code: "B", label: "Second", checked: true)],
                                               capacity: "8", serviceDate: "2026-10-20", serviceStartTime: "10:00", serviceEndTime: "12:00")
        let command = try MerchantGameNodeCommand.ready(p, s, draft: draft, requestID: "game_ready_71")
        XCTAssertEqual(command.payload["checklist"]?.array?.compactMap { $0["code"].text }, ["B", "A"])
        XCTAssertEqual(command.payload["serviceStartAt"], .string("2026-10-20 10:00"))
        XCTAssertEqual(command.payload["capacity"], .integer(8))
        draft.serviceEndTime = "09:00"
        XCTAssertThrowsError(try MerchantGameNodeCommand.ready(p, s, draft: draft, requestID: "game_ready_71"))
        XCTAssertEqual(MerchantGameNodeReadyDraft(station: s).serviceDate, "2026-10-20", "minute-format end seeds the date")
    }
    func testPauseFallbackMustBeApprovedAndIsOptional() throws {
        let (p, s) = try fixture()
        var draft = MerchantGameNodePauseDraft(); draft.reason = MerchantGameNodeReason.pause[1]; draft.resumeDate = "2026-10-20"; draft.resumeTime = "15:00"
        let plain = try MerchantGameNodeCommand.pause(p, s, draft: draft, requestID: "game_pause_71")
        XCTAssertTrue(plain.pausesWithoutFallback)
        XCTAssertEqual(plain.payload["reason"], .string("人员暂时离岗")); XCTAssertEqual(plain.payload["resumeEta"], .string("2026-10-20 15:00"))
        draft.fallback = p.fallbackOptions.first
        let withPlan = try MerchantGameNodeCommand.pause(p, s, draft: draft, requestID: "game_pause_71")
        XCTAssertEqual(withPlan.payload["fallbackPlanCode"], .string("PLAN_A")); XCTAssertEqual(withPlan.payload["fallbackPlanVersion"], .integer(2))
        XCTAssertNil(withPlan.payload["fallbackNodeId"])
        draft.fallback = MerchantGameNodeFallbackOption(sourceNodeID: 8, planCode: "UNREVIEWED", planVersion: 1, nodeID: 9, nodeName: "X", playerMessage: "Y")
        XCTAssertThrowsError(try MerchantGameNodeCommand.pause(p, s, draft: draft, requestID: "game_pause_71"))
    }
    func testVerifyRegexRejectReasonAndAuthorityEpochEcho() throws {
        let (p, s) = try fixture(extra: #","authorityEpoch":3"#)
        var draft = MerchantGameNodeVerifyDraft(submissionID: "0123")
        XCTAssertThrowsError(try MerchantGameNodeCommand.verify(p, s, draft: draft, requestID: "game_verify_71"))
        draft.submissionID = "1234567890123456789"; draft.approve = false
        XCTAssertThrowsError(try MerchantGameNodeCommand.verify(p, s, draft: draft, requestID: "game_verify_71"))
        draft.rejectReason = MerchantGameNodeReason.reject[0]
        let command = try MerchantGameNodeCommand.verify(p, s, draft: draft, requestID: "game_verify_71")
        XCTAssertEqual(command.lockKey, "VERIFY_SUBMISSION:8:1234567890123456789")
        let body = try command.body()
        XCTAssertEqual(body["authorityEpoch"], .integer(3)); XCTAssertEqual(body["requestId"], .string("game_verify_71"))
        XCTAssertEqual(body["payload"]?["submissionId"], .string("1234567890123456789"))
    }
    func testSubmissionCodeParsing() {
        XCTAssertEqual(MerchantGameNodeSubmissionCode.parse(#"{"submissionId":"42"}"#), "42")
        XCTAssertEqual(MerchantGameNodeSubmissionCode.parse(#"{"submissionId":42}"#), "42")
        XCTAssertEqual(MerchantGameNodeSubmissionCode.parse("pages/play?x=1&submissionId=77"), "77")
        XCTAssertEqual(MerchantGameNodeSubmissionCode.parse("0042"), "")
        XCTAssertEqual(MerchantGameNodeSubmissionCode.parse(" 9 "), "9")
    }
}

final class MerchantGameNodeReceiptTests: XCTestCase {
    private let command = MerchantGameNodeCommand(activityID: 71, nodeID: 8, requestID: "game_accept_71_8", expectedRevision: 5, authorityEpoch: nil, action: .accept, payload: [:])
    func testCommandClassification() throws {
        let applied = try gameNodeValue(#"{"receiptId":3,"activityId":71,"requestId":"game_accept_71_8","action":"STATION_ACCEPT","outcome":"APPLIED","revision":6}"#)
        guard case .success(let receipt) = MerchantGameNodeResults.command(code: 200, message: nil, data: applied, command: command) else { return XCTFail() }
        XCTAssertTrue(receipt.matches(command.pendingIndex, outcome: "APPLIED"))
        let otherRequest = try gameNodeValue(#"{"receiptId":3,"activityId":71,"requestId":"game_other_71_8","action":"STATION_ACCEPT","outcome":"APPLIED","revision":6}"#)
        XCTAssertEqual(MerchantGameNodeResults.command(code: 200, message: nil, data: otherRequest, command: command), .unknown(nil))
        let noRevision = try gameNodeValue(#"{"receiptId":3,"activityId":71,"requestId":"game_accept_71_8","action":"STATION_ACCEPT","outcome":"FAILED"}"#)
        XCTAssertEqual(MerchantGameNodeResults.command(code: 200, message: nil, data: noRevision, command: command), .unknown(nil))
        let business = MerchantGameNodeResults.command(code: 500, message: "select * from x", data: try gameNodeValue(#"{"reasonCode":"GAME_AUTHORITY_CONFLICT"}"#), command: command)
        XCTAssertEqual(business, .businessError(nil, reasonCode: "GAME_AUTHORITY_CONFLICT", receipt: nil))
    }
    func testBackendPendingReceiptHasNullActionAndRevision() throws {
        let pending = try gameNodeValue(#"{"activityId":71,"requestId":"game_accept_71_8","action":null,"outcome":"PENDING","revision":null,"replayed":false}"#)
        XCTAssertEqual(MerchantGameNodeResults.receipt(code: 200, message: nil, data: pending, activityID: 71, requestID: "game_accept_71_8"), .pending)
        let mismatch = try gameNodeValue(#"{"activityId":72,"requestId":"game_accept_71_8","outcome":"PENDING"}"#)
        XCTAssertEqual(MerchantGameNodeResults.receipt(code: 200, message: nil, data: mismatch, activityID: 71, requestID: "game_accept_71_8"),
                       .invalidResponse(.key("merchantGameNode.error.receiptInvalid")))
    }
    func testProjectionIdentityChecks() throws {
        let raw = try gameNodeValue(gameNodeProjection())
        XCTAssertEqual(MerchantGameNodeResults.projection(code: 200, message: nil, data: raw, activityID: 72), .businessError(.key("merchantGameNode.error.invalidData"), reasonCode: nil))
        XCTAssertEqual(MerchantGameNodeResults.projection(code: 500, message: "当前商家不负责本场站点", data: try gameNodeValue(#"{"reasonCode":"GAME_FORBIDDEN_SCOPE"}"#), activityID: 71),
                       .businessError(.server("当前商家不负责本场站点"), reasonCode: "GAME_FORBIDDEN_SCOPE"))
    }
}

private final class GameNodeScriptTransport: MerchantContentOfflineTransport {
    var projection: String = gameNodeProjection()
    var commandReply: ((MerchantContentValue) throws -> String)?
    var receiptReply: ((String) -> String)?
    var requests: [URLRequest] = []
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        let path = request.url?.path ?? ""
        func wrap(_ data: String) -> (Data, Int) { (Data(#"{"code":200,"msg":"ok","data":"#.utf8 + Data(data.utf8) + Data("}".utf8)), 200) }
        switch path {
        case "/api/game/session/view": return wrap(projection)
        case "/api/game/session/command":
            let body = try JSONDecoder().decode(MerchantContentValue.self, from: request.httpBody ?? Data())
            return wrap(try commandReply?(body) ?? "{}")
        case "/api/game/session/receipt":
            let id = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?.queryItems?.first { $0.name == "requestId" }?.value ?? ""
            return wrap(receiptReply?(id) ?? #"{"activityId":71,"requestId":""# + id + #"","outcome":"PENDING"}"#)
        default: return (Data(), 404)
        }
    }
}

@MainActor final class MerchantGameNodeCoordinatorTests: XCTestCase {
    private var session: MerchantGameNodeSession?
    private func service(_ transport: GameNodeScriptTransport,
                         execution: MerchantContentService.Execution = .injectedOfflineHarness) throws -> MerchantGameNodeHTTPService {
        try service(transport, journal: MerchantGameNodeMemoryJournal(), execution: execution)
    }
    private func service(_ transport: GameNodeScriptTransport, journal: MerchantGameNodeMemoryJournal?,
                         execution: MerchantContentService.Execution = .injectedOfflineHarness) throws -> MerchantGameNodeHTTPService {
        session = try MerchantGameNodeSession(accountID: 1, epoch: 1, storageScope: "tests", token: "token")
        return MerchantGameNodeHTTPService(configuration: try APIConfiguration(baseURL: XCTUnwrap(URL(string: "https://game-node.example"))),
            transport: transport, currentSession: { [unowned self] in self.session }, journal: journal, execution: execution)
    }
    private static func applied(_ body: MerchantContentValue) -> String {
        #"{"receiptId":9,"activityId":71,"requestId":""# + (body["requestId"].text ?? "") + #"","action":""# + (body["action"].text ?? "") + #"","outcome":"APPLIED","revision":6}"#
    }
    func testGatesDefaultOffAndProductionReaderNeverWrites() throws {
        XCTAssertFalse(MerchantCityNPCParityGates.disabled.stationCommands)
        let disabled = try service(GameNodeScriptTransport(), execution: .disabled)
        XCTAssertFalse(disabled.permitsWrites)
        let noJournal = try service(GameNodeScriptTransport(), journal: nil)
        XCTAssertFalse(noJournal.permitsWrites)
    }
    func testPauseWithoutFallbackNeedsConfirmationThenReadsBackOnce() async throws {
        let transport = GameNodeScriptTransport(); transport.commandReply = { Self.applied($0) }
        let c = MerchantGameNodeCoordinator(service: try service(transport), activityID: 71)
        await c.start()
        XCTAssertEqual(c.viewState, .ready)
        XCTAssertTrue(c.openPause())
        c.pauseDraft.reason = MerchantGameNodeReason.pause[0]; c.pauseDraft.resumeDate = "2026-10-20"
        await c.submitPause()
        let frozen = try XCTUnwrap(c.confirmation)
        XCTAssertFalse(transport.requests.contains { $0.url?.path == "/api/game/session/command" })
        c.dismissConfirmation()
        await c.confirm(frozen)
        let commands = transport.requests.filter { $0.url?.path == "/api/game/session/command" }
        XCTAssertEqual(commands.count, 1)
        XCTAssertEqual(commands.first?.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(c.writeState, .idle)
        XCTAssertEqual(c.recentReceipts.first?.action, "STATION_PAUSE")
    }
    func testUnknownWriteLocksAndOnlyExactReceiptReleases() async throws {
        let transport = GameNodeScriptTransport()
        var sent: [String] = []
        transport.commandReply = { body in sent.append(body["requestId"].text ?? ""); throw URLError(.timedOut) }
        let c = MerchantGameNodeCoordinator(service: try service(transport), activityID: 71)
        await c.start()
        XCTAssertTrue(c.openVerify(submissionID: "42"))
        await c.submitVerify()
        XCTAssertEqual(c.writeState, .unknown); XCTAssertTrue(c.canRetryUnknownWrite)
        await c.confirmUnknownWrite()
        XCTAssertEqual(c.writeState, .unknown); XCTAssertEqual(c.writeMessage, .key("merchantGameNode.write.stillProcessing"))
        await c.retryUnknownWrite()
        XCTAssertEqual(sent.count, 2); XCTAssertEqual(Set(sent).count, 1, "retry must reuse the original request ID")
        transport.receiptReply = { id in #"{"receiptId":9,"activityId":71,"requestId":""# + id + #"","action":"VERIFY_SUBMISSION","outcome":"APPLIED","revision":7,"replayed":true}"# }
        await c.confirmUnknownWrite()
        XCTAssertEqual(c.writeState, .idle); XCTAssertEqual(c.recentReceipts.first?.replayed, true)
    }
    func testRestoredPendingCannotRetryAndRequiresReadback() async throws {
        let journal = MerchantGameNodeMemoryJournal()
        let s = try service(GameNodeScriptTransport(), journal: journal)
        XCTAssertTrue(s.persistPending(.init(activityID: 71, requestID: "game_pause_71_8_1", action: .pause, nodeID: 8, expectedRevision: 5)))
        let c = MerchantGameNodeCoordinator(service: s, activityID: 71)
        await c.start()
        XCTAssertEqual(c.writeState, .unknown); XCTAssertFalse(c.canRetryUnknownWrite)
        XCTAssertFalse(c.openPause(), "every write stays locked until the receipt is read back")
    }
    func testMissingActivityAndFocusPause() async throws {
        let missing = MerchantGameNodeCoordinator(service: try service(GameNodeScriptTransport()), activityID: nil)
        await missing.start()
        XCTAssertEqual(missing.viewState, .businessError(.key("merchantGameNode.error.missingActivity")))
        let focused = MerchantGameNodeCoordinator(service: try service(GameNodeScriptTransport()), activityID: 71, focusPause: true)
        await focused.start()
        XCTAssertEqual(focused.sheet, .pause)
    }
}
