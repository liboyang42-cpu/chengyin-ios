#if DEBUG
import SwiftUI
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Offline synthetic station server for pages/merchant/game-node. Requests terminate here; no socket,
/// URLSession, camera or provider exists. All names are obviously synthetic.
final class MerchantGameNodeFixtureTransport: MerchantContentOfflineTransport {
    let scenario: String
    private(set) var requests: [URLRequest] = []
    private(set) var commands: [MerchantContentValue] = []
    private(set) var issuedCodes = 0
    private var revision = 4
    private var sessionStatus = "RUNNING"
    private var stations: [MerchantContentValue] = []
    private var fallbackOptions: MerchantContentValue = .array([])
    var receipts: [String: MerchantContentValue] = [:]
    static let activityID = 71

    init(scenario: String) {
        self.scenario = scenario
        let running = Self.station(id: 6, node: 8, name: "Sample dock station", code: "SAMPLE-08", status: "ACTIVE", pending: 2, playable: true, recap: true)
        switch scenario {
        case "invited", "uncertain", "failed":
            sessionStatus = "PREPARING"; stations = [Self.station(id: 6, node: 8, name: "Sample dock station", code: "SAMPLE-08", status: "INVITED", checked: false, playable: false)]
        case "ready":
            sessionStatus = "PREPARING"; stations = [Self.station(id: 6, node: 8, name: "Sample dock station", code: "SAMPLE-08", status: "ACCEPTED", checked: false, playable: false)]
        case "paused":
            stations = [Self.station(id: 6, node: 8, name: "Sample dock station", code: "SAMPLE-08", status: "PAUSED", playable: false, paused: true)]
        case "empty": stations = []
        case "multi":
            stations = [running, Self.station(id: 7, node: 9, name: "Sample clock station", code: "SAMPLE-09", status: "INVITED", checked: false, playable: false)]
        default: stations = [running]
        }
        let option: MerchantContentValue = .object(["sourceNodeId": .integer(8), "planCode": .string("SAMPLE_PLAN"),
            "planVersion": .integer(scenario == "invalidFallback" ? 0 : 2), "nodeId": .integer(19),
            "nodeName": .string("Sample backup station"), "playerMessage": .string("Sample: continue at the backup station")])
        fallbackOptions = ["running", "focusPause", "invalidFallback", "readOnly", "restored"].contains(scenario) ? .array([option]) : .array([])
        if scenario == "restored" {
            receipts["game_pause_71_8_1760000000000_sample"] = Self.receipt(requestID: "game_pause_71_8_1760000000000_sample", action: "STATION_PAUSE", outcome: "APPLIED", id: 501, revision: 5, replayed: false)
        }
    }

    static func station(id: Int, node: Int, name: String, code: String, status: String, checked: Bool = true, pending: Int = 0,
                        playable: Bool, recap: Bool = false, paused: Bool = false) -> MerchantContentValue {
        var fields: [String: MerchantContentValue] = [
            "stationId": .integer(id), "nodeId": .integer(node), "nodeName": .string(name), "stationCode": .string(code),
            "status": .string(status), "revision": .integer(3),
            "preparationChecklist": .array([
                .object(["code": .string("STAFF"), "label": .string("Sample staff in place"), "checked": .bool(checked)]),
                .object(["code": .string("PROP"), "label": .string("Sample props prepared"), "checked": .bool(checked)])]),
            "playerTask": .object(["taskCode": .string("SAMPLE_TASK"), "prompt": .string("Sample: scan the counter task code"),
                                   "inputType": .string("SCAN"), "verificationRequired": .bool(true)]),
            "merchantInstruction": .string("Sample: confirm the shown number only"),
            "hiddenInfoReminder": .string("Sample: never reveal answers or other clues"),
            "capacity": checked ? .integer(12) : .null,
            "serviceStartAt": checked ? .string("2026-10-20 10:00:00") : .null,
            "serviceEndAt": checked ? .string("2026-10-20 18:00:00") : .null,
            "pendingVerificationCount": .integer(pending), "playable": .bool(playable),
            "pauseReasonCode": paused ? .string("STAFF") : .null, "pauseReason": paused ? .string("人员暂时离岗") : .null,
            "resumeEta": paused ? .string("2026-10-20 15:00:00") : .null,
        ]
        if recap {
            fields["recap"] = .object(["arrivedPlayers": .integer(18), "submissionCount": .integer(15), "approvedCount": .integer(10),
                "rejectedCount": .integer(2), "recordedCount": .integer(3), "normalCompletedCount": .integer(10),
                "fallbackCompletedCount": .integer(1), "pauseEventCount": .integer(2), "authorizedContentCount": .integer(0),
                "contentPolicy": .string("NO_PUBLIC_CONTENT")])
        }
        return .object(fields)
    }
    static func receipt(requestID: String, action: String, outcome: String, id: Int, revision: Int, replayed: Bool, reason: String? = nil) -> MerchantContentValue {
        var fields: [String: MerchantContentValue] = ["receiptId": .integer(id), "activityId": .integer(activityID), "requestId": .string(requestID),
            "action": .string(action), "outcome": .string(outcome), "revision": .integer(revision), "replayed": .bool(replayed)]
        if let reason { fields["reasonCode"] = .string("GAME_STATE_CONFLICT"); fields["result"] = .object(["reason": .string(reason)]) }
        return .object(fields)
    }
    private var projection: MerchantContentValue {
        var actions = Set<String>()
        for station in stations {
            switch station["status"].text {
            case "INVITED"?: actions.formUnion(["STATION_ACCEPT", "STATION_DECLINE"])
            case "ACCEPTED"?: actions.insert("STATION_READY")
            case "ACTIVE"?: actions.formUnion(["STATION_PAUSE", "VERIFY_SUBMISSION"])
            case "PAUSED"?: actions.insert("STATION_RESUME")
            default: break
            }
        }
        return .object(["sessionId": .integer(90), "activityId": .integer(Self.activityID), "perspective": .string("MERCHANT"),
            "status": .string(sessionStatus), "revision": .integer(revision), "availableActions": .array(actions.sorted().map { .string($0) }),
            "merchant": .object(["playMode": .string("STORY"), "stations": .array(stations), "fallbackOptions": fallbackOptions])])
    }
    private func envelope(_ data: MerchantContentValue, code: Int = 200, message: String = "Synthetic acknowledgement") throws -> (Data, Int) {
        (try JSONEncoder().encode(MerchantContentValue.object(["code": .integer(code), "msg": .string(message), "data": data])), 200)
    }
    private func apply(_ command: MerchantContentValue) {
        guard let node = command["nodeId"].integer, let index = stations.firstIndex(where: { $0["nodeId"].integer == node }),
              var fields = stations[index].object else { return }
        switch command["action"].text {
        case "STATION_ACCEPT"?: fields["status"] = .string("ACCEPTED")
        case "STATION_DECLINE"?: fields["status"] = .string("CLOSED")
        case "STATION_READY"?:
            fields["status"] = .string("READY"); fields["capacity"] = command["payload"]["capacity"]
            fields["serviceStartAt"] = command["payload"]["serviceStartAt"]; fields["serviceEndAt"] = command["payload"]["serviceEndAt"]
            fields["preparationChecklist"] = .array((fields["preparationChecklist"]?.array ?? []).map { item in
                var row = item.object ?? [:]; row["checked"] = .bool(true); return .object(row) })
        case "STATION_PAUSE"?:
            fields["status"] = .string("PAUSED"); fields["playable"] = .bool(false)
            fields["pauseReasonCode"] = command["payload"]["reasonCode"]; fields["pauseReason"] = command["payload"]["reason"]
            fields["resumeEta"] = command["payload"]["resumeEta"]
            fields["fallbackPlanCode"] = command["payload"]["fallbackPlanCode"]; fields["fallbackPlanVersion"] = command["payload"]["fallbackPlanVersion"]
        case "STATION_RESUME"?:
            fields["status"] = .string("ACTIVE"); fields["playable"] = .bool(true)
            for key in ["pauseReasonCode", "pauseReason", "resumeEta", "fallbackPlanCode", "fallbackPlanVersion"] { fields[key] = .null }
        case "VERIFY_SUBMISSION"?: fields["pendingVerificationCount"] = .integer(max(0, (fields["pendingVerificationCount"]?.integer ?? 0) - 1))
        default: return
        }
        stations[index] = .object(fields); revision += 1
    }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        let path = request.url?.path ?? ""
        let query = URLComponents(url: request.url ?? URL(fileURLWithPath: "/"), resolvingAgainstBaseURL: false)?.queryItems ?? []
        if scenario == "error" { throw URLError(.notConnectedToInternet) }
        switch path {
        case "/api/game/session/view":
            if scenario == "denied" { return try envelope(.object(["reasonCode": .string("GAME_FORBIDDEN_SCOPE")]), code: 500, message: "当前商家不负责本场站点") }
            return try envelope(projection)
        case "/api/game/session/merchant/entries":
            return try envelope(.array([
                .object(["activityId": .integer(71), "topicId": .integer(70), "activityName": .string("Sample session A"), "stationCount": .integer(1), "startAt": .string("2026-10-20 10:00:00")]),
                .object(["activityId": .integer(72), "topicId": .integer(70), "activityName": .string("Sample session B"), "stationCount": .integer(1)]),
                .object(["activityId": .integer(73), "topicId": .integer(99), "activityName": .string("Sample other topic"), "stationCount": .integer(1)])]))
        case "/api/merchant/chapter-node/live-checkin-code":
            issuedCodes += 1
            return try envelope(.object(["code": .string("SYNTHETIC-CHECKIN-\(issuedCodes)"), "qrcodeUrl": .string(""),
                                         "nodeId": .integer(8), "nodeName": .string("Sample dock station"), "ttlMs": .integer(5_000)]))
        case "/api/game/session/receipt":
            let requestID = query.first { $0.name == "requestId" }?.value ?? ""
            if let stored = receipts[requestID] { return try envelope(stored) }
            // Backend PENDING view: identity only, action and revision are null.
            return try envelope(.object(["activityId": .integer(Self.activityID), "requestId": .string(requestID), "outcome": .string("PENDING"), "replayed": .bool(false)]))
        case "/api/game/session/command":
            let body = try JSONDecoder().decode(MerchantContentValue.self, from: request.httpBody ?? Data())
            commands.append(body)
            let requestID = body["requestId"].text ?? "", action = body["action"].text ?? ""
            if let stored = receipts[requestID], var replay = stored.object { replay["replayed"] = .bool(true); return try envelope(.object(replay)) }
            if scenario == "failed" {
                let failed = Self.receipt(requestID: requestID, action: action, outcome: "FAILED", id: 400 + commands.count, revision: revision, replayed: false, reason: "Sample: this invitation was already handled")
                receipts[requestID] = failed; return try envelope(failed)
            }
            apply(body)
            let applied = Self.receipt(requestID: requestID, action: action, outcome: "APPLIED", id: 300 + commands.count, revision: revision, replayed: false)
            receipts[requestID] = applied
            if scenario == "uncertain" && commands.count == 1 { throw URLError(.timedOut) }
            return try envelope(applied)
        default:
            return (Data(), 404)
        }
    }
}

@MainActor final class MerchantGameNodeFixtureEnvironment: ObservableObject {
    let scenario: String
    let transport: MerchantGameNodeFixtureTransport
    let journal: MerchantGameNodeMemoryJournal
    let service: MerchantGameNodeHTTPService
    let session: MerchantGameNodeSession?
    init(scenario: String) {
        self.scenario = scenario
        transport = MerchantGameNodeFixtureTransport(scenario: scenario)
        let session = try? MerchantGameNodeSession(accountID: 1, epoch: 1, storageScope: "offline-merchant-game-node-fixture", token: "fixture-token")
        self.session = session
        var seed: [String: MerchantGameNodePendingIndex] = [:]
        if scenario == "restored", let session {
            seed[session.journalKey(activityID: MerchantGameNodeFixtureTransport.activityID)] = .init(activityID: MerchantGameNodeFixtureTransport.activityID,
                requestID: "game_pause_71_8_1760000000000_sample", action: .pause, nodeID: 8, expectedRevision: 4)
        }
        journal = MerchantGameNodeMemoryJournal(seed: seed)
        service = MerchantGameNodeHTTPService(configuration: URL(string: "https://merchant-game-node.example").flatMap { try? APIConfiguration(baseURL: $0) },
            transport: transport, currentSession: { session }, journal: scenario == "readOnly" ? nil : journal,
            execution: scenario == "readOnly" ? .disabled : .injectedOfflineHarness)
    }
}

/// Scenarios: running (default), invited, ready, paused, multi, empty, error, denied, invalidFallback,
/// uncertain, failed, restored, focusPause, readOnly, missingActivity, entries.
struct MerchantGameNodeFixtureHost: View {
    @StateObject private var environment: MerchantGameNodeFixtureEnvironment
    init(scenario: String) { _environment = StateObject(wrappedValue: .init(scenario: scenario)) }
    var body: some View {
        VStack(spacing: 0) {
            NavigationStack {
                if environment.scenario == "entries" {
                    MerchantGameNodeEntryView(service: environment.service, topicID: 70)
                } else {
                    MerchantGameNodeView(service: environment.service,
                                         activityID: environment.scenario == "missingActivity" ? nil : MerchantGameNodeFixtureTransport.activityID,
                                         nodeID: environment.scenario == "multi" ? 9 : nil, focusPause: environment.scenario == "focusPause")
                }
            }
            MerchantGameNodeCopy.text("merchantGameNode.fixture.banner").font(.footnote).padding(6).frame(maxWidth: .infinity).background(.regularMaterial)
        }
    }
}
#endif
