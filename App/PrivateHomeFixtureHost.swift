#if DEBUG
import SwiftUI
import Observation

/// Synthetic UI fixture only. No production journal, credentials, backend, or location provider.
@MainActor final class PrivateHomeFixtureJournal: PrivateHomeSecureJournaling {
    let scope: PrivateHomeJournalScope
    var value: PrivateHomeMutation?
    init(owner: PlayExperienceSession) { scope = PrivateHomeJournalScope(owner: owner) }
    func read() throws -> PrivateHomeMutation? { value }
    func save(_ mutation: PrivateHomeMutation) throws { guard value == nil else { throw PrivateHomeIssue.busy }; value = mutation }
    func clear(matching mutation: PrivateHomeMutation) throws { guard value == mutation else { throw PrivateHomeIssue.invalid }; value = nil }
}
@MainActor @Observable final class PrivateHomeFixtureService: PrivateHomeServing {
    var version: Int64 = 0
    var active = false
    var lost = false
    var receipts: [String: PrivateHomeReceipt] = [:]
    var mutations: [PrivateHomeMutation] = []
    private var saved: PrivateHomeMutation?
    func load() async throws -> PrivateHomeSnapshot {
        if active, let saved, let latitude = saved.latitude, let longitude = saved.longitude {
            let body: [String: Any] = ["version": version, "status": "ACTIVE", "changedAt": 1, "effectiveAt": 1,
                "label": saved.label ?? "Synthetic home", "latitude": NSDecimalNumber(decimal: latitude),
                "longitude": NSDecimalNumber(decimal: longitude), "datum": "WGS84"]
            return try JSONDecoder().decode(PrivateHomeSnapshot.self, from: JSONSerialization.data(withJSONObject: body))
        }
        let json = active ? "{\"version\":\(version),\"status\":\"ACTIVE\",\"changedAt\":1,\"effectiveAt\":1,\"label\":\"Synthetic home\",\"latitude\":12.345,\"longitude\":45.678,\"datum\":\"WGS84\"}" : "{\"version\":\(version),\"status\":\"DELETED\"}"
        return try JSONDecoder().decode(PrivateHomeSnapshot.self, from: Data(json.utf8))
    }
    func mutate(_ mutation: PrivateHomeMutation) async throws -> PrivateHomeReceipt {
        mutations.append(mutation)
        if let receipt = receipts[mutation.requestId] { return receipt }
        version += 1; active = mutation.method == "PUT"; saved = active ? mutation : nil
        let json = "{\"requestId\":\"\(mutation.requestId)\",\"decision\":\"\(active ? "SAVED" : "DELETED")\",\"version\":\(version)}"
        let receipt = try JSONDecoder().decode(PrivateHomeReceipt.self, from: Data(json.utf8)); receipts[mutation.requestId] = receipt
        if lost { lost = false; throw PrivateHomeIssue.unknownOutcome }; return receipt
    }
}
@MainActor struct PrivateHomeFixtureHost: View {
    @State private var model: PrivateHomeCoordinator
    @State private var service: PrivateHomeFixtureService
    @State private var previousServices: [PrivateHomeFixtureService] = []
    @State private var replacements = 0
    @State private var mapAdapter: PrivateHomeFixtureMapAdapter?
    private let records: Bool
    private let accountRoute: Bool
    init() {
        let owner = try! PlayExperienceSession(accountID: 12, epoch: 1, namespace: "fixture-private", token: "fixture-token")
        let service = PrivateHomeFixtureService(); service.lost = ProcessInfo.processInfo.arguments.contains("--private-home-lost")
        _service = State(initialValue: service)
        _mapAdapter = State(initialValue: ProcessInfo.processInfo.arguments.contains("--private-home-map-fixture") ? PrivateHomeFixtureMapAdapter() : nil)
        records = ProcessInfo.processInfo.arguments.contains("--private-home-map-recorder")
        accountRoute = ProcessInfo.processInfo.arguments.contains("--private-home-account-route")
        _model = State(initialValue: PrivateHomeCoordinator(service: service, journal: PrivateHomeFixtureJournal(owner: owner), owner: owner,
            enabled: !ProcessInfo.processInfo.arguments.contains("--private-home-disabled"), current: { owner }))
    }
    var body: some View {
        NavigationStack {
            Group {
                if accountRoute {
                    // The actual AccountView link/destination stays on the same route as its owner changes.
                    Form { PrivateHomeAccountLink(coordinator: model, mapAdapter: mapAdapter) }
                } else { PrivateHomeView(model: model, mapAdapter: mapAdapter) }
            }
        }
        .onAppear { mapAdapter?.replaceOwner = { replaceOwner() } }
        .safeAreaInset(edge: .bottom) {
            if records {
                // Payload-free synthetic recorder: proves selection/preview do not mutate.
                VStack {
                    Text(verbatim: String(service.mutations.count + previousServices.reduce(0) { $0 + $1.mutations.count }))
                        .accessibilityIdentifier("privateHome.recorder.requests")
                    Text(verbatim: String(service.receipts.count + previousServices.reduce(0) { $0 + $1.receipts.count }))
                        .accessibilityIdentifier("privateHome.recorder.receipts")
                    Text(verbatim: String(mapAdapter?.starts ?? 0)).accessibilityIdentifier("privateHome.recorder.starts")
                    Text(verbatim: String(replacements)).accessibilityIdentifier("privateHome.recorder.replacements")
                    Text(verbatim: String(service.mutations.last?.latitude == Decimal(string: "12.345678") && service.mutations.last?.longitude == Decimal(string: "45.678901")))
                        .accessibilityIdentifier("privateHome.recorder.exactPoint")
                    HStack {
                        Button { replaceOwner() } label: { Text(verbatim: "Synthetic: replace owner") }
                            .accessibilityIdentifier("privateHome.fixture.replaceOwner")
                        Button { mapAdapter?.approvedSource = nil } label: { Text(verbatim: "Synthetic: revoke source") }
                            .accessibilityIdentifier("privateHome.fixture.revokeSource")
                    }
                }.font(.caption2)
                    // Payload-free DEBUG instrumentation must not cover the product
                    // Form when its own typography is exercised at accessibility5.
                    .dynamicTypeSize(.large)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("privateHome.fixture.recorder")
            }
        }
    }
    private func replaceOwner() {
        // Only synthetic view/session state is replaced. No production journal deletion occurs.
        model.invalidate(); previousServices.append(service); replacements += 1
        let owner = try! PlayExperienceSession(accountID: 12 + replacements, epoch: 1, namespace: "fixture-private", token: "fixture-token")
        let replacement = PrivateHomeFixtureService()
        service = replacement
        model = PrivateHomeCoordinator(service: replacement, journal: PrivateHomeFixtureJournal(owner: owner),
            owner: owner, enabled: true, current: { owner })
    }
}
#endif
