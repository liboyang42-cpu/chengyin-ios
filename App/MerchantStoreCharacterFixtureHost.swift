#if DEBUG
import SwiftUI

/// Offline transport for the store character page. Synthetic values only; nothing leaves the process.
@MainActor final class StoreCharacterOfflineTransport: HTTPTransport {
    struct Failure: Error {}
    let scenario: String
    private(set) var calls: [String] = []
    private var profile: [String: Any]?
    private var voiceStatus = 0
    private var voiceSample: String?
    private var statusReads = 0
    private var point: [String: Any]?
    init(scenario: String) {
        self.scenario = scenario
        switch scenario {
        case "empty", "saveSuccess", "saveRejected", "saveUnknown":
            profile = nil
        case "rejected":
            profile = Self.profile(name: "Sample Lantern Host", avatar: "px1:p25", audit: 2, reason: "Sample review note: please revise the greeting.")
        default:
            profile = Self.profile(name: "Sample Lantern Host", avatar: "px1:p07", audit: 1, reason: nil)
        }
        if scenario == "normal" || scenario == "rejected" { voiceStatus = 2; voiceSample = "https://example.com/synthetic/voice-sample.mp3" }
        if scenario == "voicePending" { voiceStatus = 1; voiceSample = "https://example.com/synthetic/voice-sample.mp3" }
        if scenario == "normal" || scenario == "scopes" { point = ["locationLat": 0.0, "locationLng": 0.0, "address": "Sample address, Example District"] }
    }
    private static func profile(name: String, avatar: String, audit: Int, reason: String?) -> [String: Any] {
        var value: [String: Any] = ["id": 12, "name": name, "avatar": avatar, "greeting": "Welcome to the sample shop.",
                                    "persona": "A friendly fictional guide.", "knowledge": "Sample menu: synthetic tea and synthetic cake.",
                                    "auditStatus": audit, "voiceStatus": 0]
        if let reason { value["auditReason"] = reason }
        return value
    }
    private func reply(_ object: [String: Any], status: Int = 200) throws -> (Data, Int) {
        (try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), status)
    }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        let path = String((request.url?.path ?? "").drop(while: { $0 == "/" }))
        calls.append(path)
        let body = (request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]) ?? [:]
        switch path {
        case StoreCharacterEndpoint.access:
            if scenario == "denied" { return try reply(["code": 200, "data": ["active": true, "merchant": ["id": 31, "name": "Sample Shop"], "roleCode": "MERCHANT_CHECKIN", "permissions": ["merchant:basic:read"]]]) }
            if scenario == "notMember" { return try reply(["code": 200, "data": ["active": false, "permissions": []]]) }
            return try reply(["code": 200, "data": ["active": true, "merchant": ["id": 31, "name": "Sample Shop"], "roleCode": "MERCHANT_OWNER",
                                                     "permissions": ["merchant:basic:read", "merchant:profile:write", "merchant:coop:manage"]]])
        case StoreCharacterEndpoint.profile:
            if scenario == "error" { return (Data(), 503) }
            return try reply(["code": 200, "data": profile.map { $0 as Any } ?? NSNull()])
        case StoreCharacterEndpoint.voiceStatus:
            statusReads += 1
            if scenario == "voicePending", statusReads >= 3 { voiceStatus = 2 }
            var value: [String: Any] = ["code": 200, "msg": "操作成功", "voiceStatus": voiceStatus]
            if let voiceSample { value["voiceSample"] = voiceSample }
            return try reply(value)
        case StoreCharacterEndpoint.mapPointRead:
            guard let point else { return try reply(["code": 500, "msg": "Sample: profile unavailable"]) }
            return try reply(["code": 200, "data": point.merging(["id": 31]) { a, _ in a }])
        case StoreCharacterEndpoint.save:
            if scenario == "saveRejected" { return try reply(["code": 500, "msg": "Sample content check rejected this text."]) }
            var next = profile ?? [:]
            for key in ["name", "avatar", "greeting", "persona", "knowledge"] { next[key] = body[key] }
            next["auditStatus"] = 0; next["voiceStatus"] = voiceStatus
            profile = next
            if scenario == "saveUnknown" { throw Failure() }
            return try reply(["code": 200, "msg": "已保存"])
        case StoreCharacterEndpoint.consent:
            return try reply(["code": 200, "data": ["requestId": body["requestId"] ?? "", "docType": body["docType"] ?? "", "scene": body["scene"] ?? "",
                                                     "eventType": body["eventType"] ?? "", "docVersion": "sample-1"]])
        case StoreCharacterEndpoint.voiceEnroll:
            voiceStatus = 1; voiceSample = body["voiceSample"] as? String
            if scenario == "voiceUnknown" { throw Failure() }
            return try reply(["code": 200, "msg": "声音正在生成,稍后可用", "voiceStatus": 1])
        case StoreCharacterEndpoint.mapPointSave:
            point = ["locationLat": body["locationLat"] ?? 0, "locationLng": body["locationLng"] ?? 0, "address": body["address"] ?? ""]
            return try reply(["code": 200, "msg": "已保存"])
        default:
            return (Data(), 404)
        }
    }
}

/// `--w2-19-page aiNPC --w2-19-scenario <scenario>`: normal, empty, rejected, error, denied, notMember,
/// login, saveSuccess, saveRejected, saveUnknown, voicePending, voiceEnroll, voiceUnknown, mapPoint, scopes.
struct MerchantStoreCharacterFixtureHost: View {
    private let coordinator: StoreCharacterCoordinator
    private let reform: StoreCharacterReformContext?
    init(scenario: String) {
        let transport = StoreCharacterOfflineTransport(scenario: scenario)
        var gates = MerchantCityNPCParityGates()
        if ["saveSuccess", "saveRejected", "saveUnknown", "mapPoint"].contains(scenario) { gates.storeCharacterSaves = true }
        if ["voiceEnroll", "voiceUnknown"].contains(scenario) { gates.storeVoiceEnrollment = true }
        if scenario == "scopes" { gates.themeNPCBinding = true; gates.merchantAIDrafts = true }
        let session = UUID()
        let signedIn = scenario != "login"
        // swiftlint:disable:next force_try
        let configuration = try! APIConfiguration(baseURL: URL(string: "https://example.com/store-character-fixture/")!)
        let backend = StoreCharacterServiceBackend(service: .init(configuration: configuration, transport: transport), market: .china, gates: gates,
            execution: .injectedOfflineHarness, token: { signedIn ? "synthetic-fixture-token" : nil }, currentScope: { signedIn ? session : nil })
        let sample = ["voiceEnroll", "voiceUnknown"].contains(scenario)
            ? StoreCharacterRecordedSample(url: "https://example.com/synthetic/voice-recording.mp3", durationSeconds: 14, byteCount: 180_000) : nil
        let point = scenario == "mapPoint" ? StoreCharacterMapPointWrite(latitude: 0, longitude: 0, address: "Sample picked point, Example District") : nil
        coordinator = StoreCharacterCoordinator(reader: backend, writer: backend, gates: gates, syntheticRecording: sample, syntheticPoint: point)
        if scenario == "scopes", let binding = ThemeNPCSessionScope(actorType: .player, actorID: "sample-player", merchantID: "sample-merchant",
                                                                     themeID: "sample-theme", releaseID: "sample-release", runID: "sample-run", bindingID: "sample-binding") {
            let revision = MerchantAuthoringRevision(draftID: "sample-draft", version: 1, stage: .draft, authorID: "sample-editor",
                contentHash: "sample-hash", touchesThemeContent: true, merchantFactsApproval: nil, themeContentApproval: nil)
            reform = .init(projection: .init(merchantID: "sample-merchant", storeID: "sample-store", serverBinding: binding, clientThemeHint: "sample-theme"),
                           draft: .init(revision: revision, gates: gates))
        } else { reform = nil }
    }
    var body: some View {
        NavigationStack {
            MerchantStoreCharacterView(coordinator: coordinator, reform: reform)
        }
    }
}
#endif
