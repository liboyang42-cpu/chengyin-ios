#if DEBUG
import SwiftUI
import Observation

/// Offline DEBUG host for the store-day merchant page. Synthetic store, code, picture URL and
/// identifiers only; no coordinates, camera, scanner, network or production endpoint.
@MainActor private final class PlayStoreDayFixtureState {
    let scenario: String
    var row: [String: Any]
    var consentEvent: String?
    var nodeReads = 0
    var writes: [String] = []
    init(scenario: String) {
        self.scenario = scenario
        var row: [String: Any] = ["nodeId": 701, "merchantId": 81, "name": "Synthetic store / 示例门店", "address": "Synthetic address 1",
            "openStatus": "营业中", "businessTime": "09:00-21:00", "crowded": false, "inStoreLoad": 2, "expectedWaitMinutes": 10,
            "serviceCapacity": ["batchSize": 2, "batchIntervalMinutes": 10, "maxConcurrent": 4, "perHour": 12], "quantityUnavailable": false,
            "ruleInstructions": "Synthetic rule: show the sample sign.", "photoRequireDesc": "Synthetic: photograph the sample sign.",
            "arrived": false, "selfReported": false, "gameDone": false, "done": false, "hasGame": true, "validationMethod": 3]
        switch scenario {
        case "arrived": row["arrived"] = true; row["hasGame"] = false
        case "consented", "noTicket": row["arrived"] = true; row["selfReported"] = true; row["gameDone"] = true
        case "degraded": row["quantityUnavailable"] = true; row["crowded"] = true; row["serviceCapacity"] = NSNull(); row["expectedWaitMinutes"] = NSNull()
        case "redeemed": row["arrived"] = true; row["selfReported"] = true; row["done"] = true
        default: break
        }
        if row["arrived"] as? Bool == true { Self.addQuiz(&row) }
        self.row = row
        consentEvent = scenario == "consented" ? "AGREE" : nil
    }
    private static func addQuiz(_ row: inout [String: Any]) {
        guard row["hasGame"] as? Bool == true else { return }
        row["gameTitle"] = "Synthetic quiz"; row["question"] = "Which sample sign is by the door?"
        row["options"] = ["A": "Sample circle", "B": "Sample square", "C": "Sample star", "D": "Sample moon"]
    }
    private func envelope(_ data: Any, code: Int = 200, msg: String? = nil) -> (Data, Int) {
        var root: [String: Any] = ["code": code, "data": data]
        if let msg { root["msg"] = msg }
        return ((try? JSONSerialization.data(withJSONObject: root, options: .sortedKeys)) ?? Data(), 200)
    }
    private func proofData() -> [String: Any] {
        var data: [String: Any] = ["nodeId": 701, "arrived": row["arrived"] ?? false, "selfReported": row["selfReported"] ?? false, "done": false,
            "rule": "Synthetic rule: show the sample sign.", "photoDesc": "Synthetic: photograph the sample sign.", "hasGame": row["hasGame"] ?? false]
        if row["hasGame"] as? Bool == true { data["validationMethod"] = 3; Self.addQuiz(&data) }
        return data
    }
    private func field(_ name: String, in request: URLRequest) -> String? {
        guard let body = request.httpBody.flatMap({ String(data: $0, encoding: .utf8) }),
              let range = body.range(of: "name=\"\(name)\"\r\n\r\n") else { return nil }
        return body[range.upperBound...].components(separatedBy: "\r\n").first
    }
    private func consentRecord() -> [String: Any] {
        guard let consentEvent else { return [:] }
        return ["docType": "merchant_onsite_data_sharing", "docVersion": "v1.0", "scene": "merchant_redeem", "scopeType": "MERCHANT",
                "scopeId": 81, "eventType": consentEvent, "requestId": "synthetic-request", "occurredAt": "2026-01-01 00:00:00"]
    }
    func response(_ request: URLRequest) async throws -> (Data, Int) {
        guard request.value(forHTTPHeaderField: "Authorization") == PlayStoreDayMerchantFixtureHost.token else { return envelope(NSNull(), code: 401, msg: "请先登录") }
        switch request.url?.path ?? "" {
        case "/fixture/api/play/nodes":
            nodeReads += 1
            guard request.url?.query == "topicId=71" else { return envelope(NSNull(), code: 500, msg: "参数有误") }
            if scenario == "error" { return (Data(), 500) }
            if scenario == "permission" { return envelope(NSNull(), code: 401, msg: "请先登录") }
            if scenario == "stillUnknown", nodeReads > 1 { throw URLError(.notConnectedToInternet) }
            return envelope(["topicId": 71, "mode": 2, "nodes": scenario == "empty" ? [] : [row]])
        case "/fixture/api/play/checkin":
            writes.append("checkin")
            guard field("code", in: request) == PlayStoreDayFixtureEvidence.code, field("topicId", in: request) == "71" else { return envelope(NSNull(), code: 500, msg: "无效的打卡码") }
            row["arrived"] = true; row["arrivedAt"] = "2026-01-01 10:00:00"; Self.addQuiz(&row)
            if scenario == "uncertain" || scenario == "stillUnknown" { throw URLError(.timedOut) }
            return envelope(proofData(), msg: "已记录到店")
        case "/fixture/api/play/photo":
            writes.append("photo")
            guard field("picUrl", in: request) == PlayStoreDayFixtureEvidence.picture, field("nodeId", in: request) == "701" else { return envelope(NSNull(), code: 500, msg: "请先上传照片") }
            row["selfReported"] = true
            return envelope(proofData(), msg: "到店照片已记录")
        case "/fixture/api/play/answer":
            writes.append("answer")
            guard field("answer", in: request) == "B" else { return envelope(["answerWrong": true], code: 500, msg: "答案不正确") }
            row["gameDone"] = true
            return envelope(["firstTime": true, "xp": 9, "nodeId": 701], msg: "答对了！")
        case "/fixture/api/compliance/consents/latest":
            return envelope(consentRecord())
        case "/fixture/api/compliance/consents":
            writes.append("consents")
            guard let body = request.httpBody, let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
                  object["docType"] as? String == "merchant_onsite_data_sharing", object["scopeType"] as? String == "MERCHANT",
                  object["scopeId"] as? Int == 81, let event = object["eventType"] as? String, let id = object["requestId"] as? String,
                  id.hasPrefix("merchant-" + event.lowercased() + "-81-") else { return envelope(NSNull(), code: 500, msg: "授权商家范围不合法") }
            consentEvent = event
            return envelope(consentRecord())
        default: return (Data(), 404)
        }
    }
}
private final class PlayStoreDayFixtureTransport: PlayStoreDayOfflineTransport {
    let operation: @MainActor (URLRequest) async throws -> (Data, Int)
    init(_ operation: @escaping @MainActor (URLRequest) async throws -> (Data, Int)) { self.operation = operation }
    func send(_ request: URLRequest) async throws -> (Data, Int) { try await operation(request) }
}
@MainActor private final class PlayStoreDayFixtureEvidence: PlayStoreDayEvidenceSource {
    static let code = "SYNTHETIC-STORE-CODE"
    static let picture = "https://fixture.example/synthetic-proof.jpg"
    func storeCode() -> String? { Self.code }
    func proofPictureURL() -> String? { Self.picture }
}
@MainActor @Observable private final class PlayStoreDayFixtureFlags { var verificationShown = false }

@MainActor struct PlayStoreDayMerchantFixtureHost: View {
    fileprivate static let token = "synthetic-fixture-token"
    @State private var state: PlayStoreDayFixtureState
    @State private var flags: PlayStoreDayFixtureFlags
    @State private var model: PlayStoreDayCoordinator
    init(scenario: String) {
        let state = PlayStoreDayFixtureState(scenario: scenario), flags = PlayStoreDayFixtureFlags()
        let session = try? PlayStoreDaySession(accountID: 9001, epoch: 1, token: Self.token)
        let service = PlayStoreDayService(configuration: try? APIConfiguration(baseURL: URL(string: "https://example.com/fixture/")!),
            transport: PlayStoreDayFixtureTransport { try await state.response($0) }, market: .china,
            execution: scenario == "disabled" ? .disabled : .injectedOfflineHarness, readsEnabled: true, currentSession: { session })
        _state = State(initialValue: state); _flags = State(initialValue: flags)
        _model = State(initialValue: PlayStoreDayCoordinator(nodeID: 701, scope: .topic(71), registrationID: scenario == "noTicket" ? 0 : 41,
            justScanned: scenario == "arrived", service: service, evidence: scenario == "noDevice" ? nil : PlayStoreDayFixtureEvidence(),
            presentVerification: { flags.verificationShown = true; return true }))
    }
    var body: some View {
        NavigationStack {
            PlayStoreDayMerchantView(model: model)
                .overlay(alignment: .top) {
                    if flags.verificationShown {
                        Text("playStoreDay.fixture.verificationPresented", tableName: "PlayStoreDay").font(.footnote.bold()).padding(8)
                            .background(.thinMaterial, in: Capsule()).accessibilityIdentifier("storeDayPage.fixture.verification")
                    }
                }
        }
    }
}
#endif
