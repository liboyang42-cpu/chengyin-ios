import SwiftUI

@MainActor final class MerchantLedgerInboxSource {
    let reader: any MerchantBusinessReading
    let scope: MerchantBusinessScope
    let authorization: UUID?
    let baseline: MerchantBusinessSnapshot
    static func eligible(_ snapshot: MerchantBusinessSnapshot) -> Bool {
        guard snapshot.access.merchantID > 0, snapshot.access.allows("merchant:finance:read") else { return false }
        switch snapshot.document.query { case .overview, .entries, .batches: return true; default: return false }
    }
    init?(reader: any MerchantBusinessReading, snapshot: MerchantBusinessSnapshot) {
        guard reader.isConfigured, let scope = reader.scope, Self.eligible(snapshot) else { return nil }
        self.reader = reader; self.scope = scope; authorization = reader.authorizationGeneration; baseline = snapshot
    }
    var current: Bool { reader.isConfigured && reader.scope == scope && reader.authorizationGeneration == authorization }
    func revalidate() async throws {
        guard current else { throw MerchantBusinessFailure.stale }
        let fresh = try await reader.snapshot(baseline.document.query)
        try Task.checkCancellation()
        guard current, fresh.access == baseline.access, fresh.document.query == baseline.document.query,
              Self.eligible(fresh) else { throw MerchantBusinessFailure.stale }
    }
}

@MainActor final class MerchantLedgerInboxGate: ObservableObject {
    @Published private(set) var busy = false
    @Published private(set) var approved = false
    private var generation = UUID()
    private(set) var active = false
    private var messagingIdentity: MessagingReadIdentity?
    private var messagingReader: ObjectIdentifier?
    func activate() { guard !active else { return }; active = true; generation = UUID() }
    func deactivate() { active = false; cancel() }
    func openingPermit() -> UUID? { active ? generation : nil }
    func cancel() { generation = UUID(); approved = false; busy = false; messagingIdentity = nil; messagingReader = nil }
    func permits(_ source: MerchantLedgerInboxSource, messaging: any MessagingReading) -> Bool {
        active && approved && source.current && messaging.isConfigured && messaging.identity == messagingIdentity
            && ObjectIdentifier(messaging) == messagingReader
    }
    func open(_ source: MerchantLedgerInboxSource, currentMessaging: @escaping () -> any MessagingReading, permit: UUID? = nil) async {
        guard active, permit == nil || permit == generation else { return }
        cancel(); let token = generation, messaging = currentMessaging()
        guard source.current, messaging.isConfigured, let identity = messaging.identity,
              identity.accountID == source.scope.accountID, identity.epoch == source.scope.epoch else { return }
        busy = true
        defer { if generation == token { busy = false } }
        do {
            try await source.revalidate()
            guard !Task.isCancelled, generation == token, source.current,
                  currentMessaging() === messaging, messaging.isConfigured, messaging.identity == identity else { return }
            messagingIdentity = identity; messagingReader = ObjectIdentifier(messaging); approved = true
        } catch { /* Existing retry performs another fresh read; no automatic retry or messaging request. */ }
    }
}

private struct MerchantLedgerInboxDestinationKey: EnvironmentKey {
    static let defaultValue: ((MerchantLedgerInboxSource) -> AnyView)? = nil
}
extension EnvironmentValues {
    var merchantLedgerInboxDestination: ((MerchantLedgerInboxSource) -> AnyView)? {
        get { self[MerchantLedgerInboxDestinationKey.self] }
        set { self[MerchantLedgerInboxDestinationKey.self] = newValue }
    }
}
@MainActor struct MerchantLedgerInboxEntry: View {
    let reader: any MerchantBusinessReading
    let snapshot: MerchantBusinessSnapshot
    @Environment(\.merchantLedgerInboxDestination) private var destination
    var body: some View {
        if let destination, let source = MerchantLedgerInboxSource(reader: reader, snapshot: snapshot) {
            Section {
                NavigationLink { destination(source) } label: { Label("merchant.ledgerInbox.open", systemImage: "tray") }
                    .accessibilityIdentifier("merchant.ledgerInbox.open")
            }
        }
    }
}
@MainActor struct SessionMerchantLedgerInboxView: View {
    @ObservedObject var session: AppSession
    let source: MerchantLedgerInboxSource
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var gate = MerchantLedgerInboxGate()
    @State private var isVisible = false
    private var ownsSource: Bool { source.reader === session.merchantBusinessReader && source.current }
    var body: some View {
        ZStack {
            if ownsSource, gate.permits(source, messaging: session.messagingReader) {
                MessagingHomeView(reader: session.messagingReader, mediaReader: session.socialMessageMediaReader,
                    senderForConversation: { session.messageSender(for: $0) }, expanded: session.imExpandedNavigation)
                    .id(session.messagingViewIdentity)
            } else if gate.busy { ProgressView("merchant.loading") }
            else {
                VStack(spacing: 12) {
                    Text("merchant.ledgerInbox.unavailable")
                    Button("action.retry") { scheduleOpen() }.disabled(!isVisible || scenePhase != .active || !ownsSource)
                }
            }
        }
        .appNavigationTitle("messaging.title")
        .onAppear { isVisible = true; scheduleOpen() }
        .onDisappear { isVisible = false; gate.deactivate() }
        .onChange(of: session.messagingViewIdentity) { _, _ in scheduleOpen() }
        .onChange(of: scenePhase) { _, _ in scheduleOpen() }
    }
    private func scheduleOpen() {
        guard isVisible, scenePhase == .active, ownsSource else { gate.deactivate(); return }
        gate.activate()
        guard let permit = gate.openingPermit() else { return }
        Task { await gate.open(source, currentMessaging: { session.messagingReader }, permit: permit) }
    }
}
