#if DEBUG
import SwiftUI
import Foundation

/// Deterministic local providers and in-memory HTTP only. Never invokes an Apple
/// permission, CMPedometer, App Attest, notification center or real endpoint.
@MainActor @Observable final class NativePlatformFixtureData {
    var owner: PlayExperienceSession? = try! .init(accountID: 7, epoch: 1, namespace: "synthetic-native-ui", token: "synthetic-token")
    var version = 1
    var windowVersion = "fixture-1"
    var offset = 3600.0
    var requests = 0
    var native: PlayWireValue = .null
    let now = Date()
    let reminders = NativePlatformFixtureReminders()
    let pedometer = NativePlatformFixturePedometer()
    init(scenario: String) { if scenario == "denied" { reminders.status = .denied; pedometer.permission = .denied } }
    var window: PlayWireValue {
        .object(["enabled": .bool(true), "activityId": .int(0), "topicId": .int(71), "nodeId": .int(701),
            "notificationProvider": .string("LOCAL_ONLY"), "timeZone": .string("UTC"), "serverNow": .int(Int(Date().timeIntervalSince1970 * 1000)),
            "openNow": .bool(false), "nextOpenAt": .int(Int((now.timeIntervalSince1970 + offset) * 1000)),
            "nextCloseAt": .int(Int((now.timeIntervalSince1970 + offset + 3600) * 1000)), "windowVersion": .string(windowVersion),
            "openFrom": .string("11:00"), "openTo": .string("12:00"), "subscribed": .bool(true)])
    }
    var state: PlayWireValue {
        .object(["sessionId": .int(11), "activityId": .int(0), "topicId": .int(71), "nodeId": .int(701), "version": .int(version), "status": .string("RUNNING"),
            "playKit": .object(["steps": .object(["goal": .int(5000), "nativeSteps": native]), "timeWindow": window])])
    }
    func respond(_ request: URLRequest) throws -> (Data, Int) {
        let path = request.url?.path ?? ""
        let value: PlayWireValue
        if path.hasSuffix("/time-window") { value = window }
        else if path.hasSuffix("/action") {
            requests += 1
            let body = try JSONDecoder().decode(PlayWireValue.self, from: request.httpBody!)
            version += 1
            var result: [String: PlayWireValue] = ["protocolVersion": .int(1), "provider": .string(NativeStepChallenge.provider), "enabled": .bool(true), "rewardEnabled": .bool(false), "status": .string("AUDIT_ONLY"),
                "accountId": .int(7), "sessionId": .int(11), "sessionVersion": .int(version), "deviceKeyId": .string("fixture-key")]
            if body["action"].text == NativePlatformAction.issue.rawValue {
                var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
                let start = calendar.startOfDay(for: now), end = calendar.date(byAdding: .day, value: 1, to: start)!
                let formatter = DateFormatter(); formatter.timeZone = calendar.timeZone; formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
                let issued = Int(Date().timeIntervalSince1970 * 1000)
                result["challenge"] = .object(["challengeId": .string(String(repeating: "a", count: 64)), "provider": .string(NativeStepChallenge.provider), "accountId": .int(7), "sessionId": .int(11), "sessionVersion": .int(version), "deviceKeyId": .string("fixture-key"),
                    "attemptStartedAt": .int(issued - 1000), "issuedAt": .int(issued), "expiresAt": .int(min(issued + 120000, Int(end.timeIntervalSince1970 * 1000))),
                    "timeZone": .string("UTC"), "dayKey": .string(formatter.string(from: now)), "dayStartAt": .int(Int(start.timeIntervalSince1970 * 1000)), "dayEndAt": .int(Int(end.timeIntervalSince1970 * 1000))])
            } else { result["baselineSteps"] = .int(1234); result["acceptedDelta"] = .int(0); result["lastSampleEndAt"] = body["payload"]["sampleEndAt"] }
            native = .object(result); value = state
        } else { value = state }
        return (try JSONEncoder().encode(PlayWireValue.object(["code": .int(200), "data": value])), 200)
    }
}
@MainActor private final class NativePlatformFixtureHTTP: HTTPTransport {
    let data: NativePlatformFixtureData
    init(_ data: NativePlatformFixtureData) { self.data = data }
    func send(_ request: URLRequest) async throws -> (Data, Int) { try data.respond(request) }
}
@MainActor final class NativePlatformFixturePedometer: NativePedometerProviding {
    var permission = NativePlatformPermission.allowed
    func read(from: Date, to: Date) async throws -> NativePedometerReading { try .init(start: from, end: to, steps: 1234) }
    func cancel() {}
}
@MainActor private final class NativePlatformFixtureAssertion: NativeStepAssertionProviding {
    let deviceKeyID = "fixture-key"; let supported = true
    func assertion(clientData: Data) async throws -> String { Data("synthetic-only".utf8).base64EncodedString() }
    func cancel() {}
}
@MainActor @Observable final class NativePlatformFixtureReminders: NativeLocalReminderProviding {
    var status = NativePlatformPermission.notDetermined
    var prompts = 0; var writes = 0; var items: [NativeLocalReminder] = []
    func permission() async -> NativePlatformPermission { status }
    func requestPermission() async throws -> NativePlatformPermission { prompts += 1; if status == .notDetermined { status = .allowed }; return status }
    func pending() async -> [NativeLocalReminder] { items }
    func replace(_ reminder: NativeLocalReminder, title: String, body: String) async throws { writes += 1; items = [reminder] }
    func cancel(identifier: String) { items.removeAll { $0.identifier == identifier } }
    func cancelAllOwned(owner: String) { items.removeAll { $0.owner == owner } }
}
@MainActor struct NativePlatformFixtureHost: View {
    @State private var data: NativePlatformFixtureData
    @State private var advanced: PlayAdvancedCoordinator
    // Retain the entire provider graph across host reconstruction. A fresh runtime
    // must not capture new fixture data while SwiftUI keeps the old State models.
    @State private var runtime: NativePlatformRuntime
    private let disabled: Bool
    init() {
        let args = ProcessInfo.processInfo.arguments
        let i = args.firstIndex(of: "--uitesting-native-platform-scenario")
        let scenario = i.flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil } ?? "ready"
        disabled = scenario == "disabled"
        let data = NativePlatformFixtureData(scenario: scenario); _data = State(initialValue: data)
        let configuration = try! APIConfiguration(baseURL: URL(string: "https://example.com/synthetic/")!)
        let transport = NativePlatformFixtureHTTP(data)
        _advanced = State(initialValue: PlayAdvancedCoordinator(activityID: 0, topicID: 71, nodeID: 701,
            service: .init(configuration: configuration, transport: transport, enabled: [.reads, .advanced]), currentSession: { data.owner }))
        let service = NativePlatformService(configuration: configuration, transport: transport, owner: data.owner!, stepsEnabled: true, remindersEnabled: true, current: { data.owner })
        let approval = NativePlatformAcceptance(stepsEnabled: true, localRemindersEnabled: true, purposeVersion: "synthetic-v1", legalReviewed: true, privacyNoticeURL: URL(string: "https://example.com/privacy"), enrolledAppAttestKeyID: "fixture-key")
        _runtime = State(initialValue: NativePlatformRuntime(owner: data.owner!, acceptance: approval, service: service, current: { data.owner },
            makePedometer: { data.pedometer }, assertion: NativePlatformFixtureAssertion(), reminders: data.reminders))
    }
    var body: some View {
        NavigationStack {
            List {
                NavigationLink("nativePlatform.steps.title") { PlayKitScreen(model: advanced, kind: .steps) }
                    .disabled(!advanced.canInteract)
                    .accessibilityIdentifier("nativePlatform.fixture.steps")
                    .accessibilityValue(Text(verbatim: advanced.phase))
                NavigationLink("nativePlatform.reminder.title") { PlayKitScreen(model: advanced, kind: .timeWindow) }
                    .disabled(!advanced.canInteract)
                    .accessibilityIdentifier("nativePlatform.fixture.reminder")
                    .accessibilityValue(Text(verbatim: advanced.phase))
                Text(verbatim: String(data.requests)).accessibilityIdentifier("nativePlatform.fixture.requests")
                Text(verbatim: String(data.reminders.prompts)).accessibilityIdentifier("nativePlatform.fixture.prompts")
                Text(verbatim: String(data.reminders.items.count)).accessibilityIdentifier("nativePlatform.fixture.pending")
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("nativePlatform.fixture.controls") {
                        Button("nativePlatform.fixture.change") { data.windowVersion = "fixture-2"; data.offset += 3600; Task { await advanced.refreshAuthoritative(); await runtime.reconcileOwnedRequests() } }
                        Button("nativePlatform.fixture.logout") { data.owner = nil; runtime.invalidate() }
                    }.accessibilityIdentifier("nativePlatform.fixture.controls")
                }
            }
        }.environment(\.nativePlatformRuntime, disabled ? nil : runtime)
            .task { await advanced.start() }
    }
}
#endif
