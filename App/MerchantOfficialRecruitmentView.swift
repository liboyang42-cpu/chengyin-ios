import SwiftUI

/// Narrow read adapter: merchant membership is freshly checked before each public
/// official list/detail read. It never creates an invitation or operation grant.
@MainActor final class MerchantOfficialRecruitmentReader<Merchant: MerchantReading>: ObservableObject, OfficialEventReading {
    private let merchant: Merchant
    private let official: any OfficialEventReading
    private let sourceIsCurrent: () -> Bool
    private let originRevision: UInt64
    private let originOfficialScope: UUID
    @Published private(set) var active = true
    private var generation = UUID()
    private var lastKey: Key?
    private var stamp = UUID()
    private struct Key: Equatable {
        let revision: UInt64
        let officialScope: UUID
        let signedIn: Bool
        let configured: Bool
        let officialAuthenticated: Bool
        let source: Bool
        let active: Bool
        let generation: UUID
    }
    init(merchant: Merchant, official: any OfficialEventReading, sourceIsCurrent: @escaping () -> Bool) {
        self.merchant = merchant; self.official = official; self.sourceIsCurrent = sourceIsCurrent
        originRevision = merchant.sessionRevision; originOfficialScope = official.scope
    }
    private var current: Bool {
        active && merchant.sessionRevision == originRevision && official.scope == originOfficialScope
            && merchant.isConfigured && merchant.isSignedIn && official.isConfigured && official.isAuthenticated && sourceIsCurrent()
    }
    var isConfigured: Bool { merchant.isConfigured && official.isConfigured }
    var isAuthenticated: Bool { current }
    var isOfflineExample: Bool { official.isOfflineExample }
    var scope: UUID {
        let key = Key(revision: merchant.sessionRevision, officialScope: official.scope,
                      signedIn: merchant.isSignedIn, configured: isConfigured,
                      officialAuthenticated: official.isAuthenticated, source: sourceIsCurrent(), active: active, generation: generation)
        if key != lastKey { lastKey = key; stamp = UUID() }
        return stamp
    }
    func setActive(_ value: Bool) {
        guard active != value else { return }
        generation = UUID(); active = value
    }
    private func read<Value>(_ operation: () async throws -> Value) async throws -> Value {
        let captured = scope
        guard current else { throw APIError.unauthorized }
        try Task.checkCancellation()
        let access = try await merchant.merchantAccess()
        try Task.checkCancellation()
        guard current, scope == captured else { throw CancellationError() }
        guard access.active, let merchantID = access.merchantID, merchantID > 0 else { throw OfficialReadFailure.forbidden }
        let result = try await operation()
        try Task.checkCancellation()
        guard current, scope == captured else { throw CancellationError() }
        return result
    }
    func events(city: String?) async throws -> [OfficialEvent] {
        // The source channel is not city-filtered. Refuse callers trying to widen this adapter's contract.
        guard city == nil else { throw APIError.invalidRequest }
        return try await read { MerchantOfficialRecruitment.visible(try await official.events(city: nil)) }
    }
    func detail(id: Int) async throws -> OfficialEvent {
        guard id > 0 else { throw APIError.invalidRequest }
        return try await read { try await official.detail(id: id) }
    }
    func myEvents() async throws -> [OfficialEvent] { throw APIError.invalidRequest }
    func partyInbox() async throws -> [OfficialPartyInvite] { throw APIError.invalidRequest }
    func canPublish() async throws -> Bool { false }
    func myPublished() async throws -> OfficialPublished { throw APIError.invalidRequest }
    func broadcastStats(id: Int) async throws -> OfficialBroadcastStats { throw APIError.invalidRequest }
}

@MainActor struct MerchantOfficialRecruitmentView<Merchant: MerchantReading>: View {
    @ObservedObject var reader: MerchantOfficialRecruitmentReader<Merchant>
    var actions: OfficialActionCoordinator? = nil
    var body: some View {
        OfficialReadScreen(reader: reader, isPrivate: true, requestID: "merchant.officialRecruitment",
                           load: { try await reader.events(city: nil) }) { events in
            List {
                Section { Text("merchant.officialRecruitment.boundary").font(.footnote).foregroundStyle(.secondary) }
                if events.isEmpty {
                    Text("merchant.officialRecruitment.empty").accessibilityIdentifier("merchant.officialRecruitment.empty")
                }
                ForEach(events) { event in
                    NavigationLink {
                        OfficialEventDetailView(id: event.id, reader: reader, actions: actions)
                    } label: { OfficialEventCard(event: event) }
                    .buttonStyle(QuestifyCardButtonStyle()).questifyCardListRow()
                    .accessibilityIdentifier("merchant.officialRecruitment.event." + String(event.id))
                }
                Section { OfficialReadOnlyNotice(offline: reader.isOfflineExample) }
            }
        }
        .appNavigationTitle("merchant.officialRecruitment.title")
    }
}

@MainActor struct SessionMerchantOfficialRecruitmentView: View {
    @ObservedObject var session: AppSession
    @StateObject private var reader: MerchantOfficialRecruitmentReader<AppSession>
    @Environment(\.scenePhase) private var scenePhase
    init(session: AppSession, source: any CoopFlowReading) {
        self.session = session
        let selected = source.session
        _reader = StateObject(wrappedValue: .init(merchant: session, official: session.officialEventReader,
            sourceIsCurrent: { selected != nil && source.session == selected }))
    }
    var body: some View {
        MerchantOfficialRecruitmentView(reader: reader, actions: session.officialActionCoordinator)
            .id(reader.scope)
            .onChange(of: scenePhase) { _, phase in reader.setActive(phase == .active) }
            .onAppear { reader.setActive(scenePhase == .active) }
    }
}

private struct MerchantOfficialRecruitmentDestinationKey: EnvironmentKey {
    static let defaultValue: ((any CoopFlowReading) -> AnyView)? = nil
}
extension EnvironmentValues {
    var merchantOfficialRecruitmentDestination: ((any CoopFlowReading) -> AnyView)? {
        get { self[MerchantOfficialRecruitmentDestinationKey.self] }
        set { self[MerchantOfficialRecruitmentDestinationKey.self] = newValue }
    }
}
