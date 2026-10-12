import SwiftUI

@MainActor final class MerchantAcceptedProjectSource {
    let reader: any CoopFlowReading
    let route: MerchantAcceptedProjectRoute
    let session: CoopFlowSession
    private let rowBytes: Data
    private let currentRows: () -> [CoopFlowJSON]?
    init?(reader: any CoopFlowReading, row: CoopFlowJSON, direction: CooperationDirection,
          currentRows: @escaping () -> [CoopFlowJSON]?) {
        guard let session = reader.session, let route = MerchantAcceptedProjectRoute(row: row, direction: direction),
              let bytes = try? row.canonical() else { return nil }
        self.reader = reader; self.route = route; self.session = session; rowBytes = bytes; self.currentRows = currentRows
        guard current else { return nil }
    }
    private func matches(_ rows: [CoopFlowJSON]) -> Bool {
        guard route.matchesUniqueRow(rows), let row = rows.first(where: { $0["id"].integer == route.invitationID }) else { return false }
        return (try? row.canonical()) == rowBytes
    }
    var current: Bool { reader.session == session && currentRows().map(matches) == true }
    func revalidate() async throws {
        guard current else { throw CoopFlowFailure.stale }
        let value = try await reader.read(.invitations, isCurrent: { self.current })
        try Task.checkCancellation()
        guard current, let rows = value[route.sourceKey].rows, matches(rows) else { throw CoopFlowFailure.stale }
    }
}

/// Navigation permit only; neither dispatches content writes nor manufactures a project membership.
@MainActor final class MerchantAcceptedProjectGate<Merchant: MerchantReading>: ObservableObject {
    struct Destination: Identifiable { let id = UUID(); let merchantID: Int }
    let source: MerchantAcceptedProjectSource
    let merchant: Merchant
    let service: any MerchantContentServing
    private let originRevision: UInt64
    private let originServiceScope: UUID
    private let hostIsCurrent: () -> Bool
    private var active = true
    private var generation = UUID()
    @Published private(set) var destination: Destination?
    @Published private(set) var busy = false
    @Published private(set) var issue: String?
    init(source: MerchantAcceptedProjectSource, merchant: Merchant, service: any MerchantContentServing,
         hostIsCurrent: @escaping () -> Bool = { true }) {
        self.source = source; self.merchant = merchant; self.service = service; self.hostIsCurrent = hostIsCurrent
        originRevision = merchant.sessionRevision; originServiceScope = service.scope
    }
    var isCurrent: Bool {
        active && hostIsCurrent() && source.current && merchant.sessionRevision == originRevision &&
            merchant.isConfigured && merchant.isSignedIn && service.scope == originServiceScope &&
            service.isConfigured && service.isAuthenticated
    }
    var canPresent: Bool { isCurrent && destination != nil && !busy && issue == nil }
    func activate() { active = true }
    func retire() { active = false; generation = UUID(); destination = nil; busy = false; issue = nil }
    func load() async {
        let stamp = UUID(); generation = stamp; destination = nil; issue = nil
        guard isCurrent else { issue = "merchant.acceptedProject.changed"; return }
        busy = true
        defer { if generation == stamp { busy = false } }
        do {
            let access = try await merchant.merchantAccess()
            try Task.checkCancellation()
            guard generation == stamp, isCurrent else { throw CancellationError() }
            guard access.active, access.allows(.projects), let merchantID = access.merchantID, merchantID > 0 else { throw MerchantReadError.accessDenied }
            try await source.revalidate()
            try Task.checkCancellation()
            guard generation == stamp, isCurrent else { throw CancellationError() }
            destination = .init(merchantID: merchantID)
        } catch {
            guard generation == stamp, active else { return }
            if error as? MerchantReadError == .accessDenied { issue = "merchant.access.denied" }
            else if error is CancellationError || error as? CoopFlowFailure == .stale || !isCurrent { issue = "merchant.acceptedProject.changed" }
            else { issue = "merchant.loadFailed" }
        }
    }
}

@MainActor struct SessionMerchantAcceptedProjectView: View {
    @ObservedObject var session: AppSession
    @StateObject private var gate: MerchantAcceptedProjectGate<AppSession>
    @Environment(\.scenePhase) private var scenePhase
    init(session: AppSession, source: MerchantAcceptedProjectSource) {
        self.session = session
        _gate = StateObject(wrappedValue: .init(source: source, merchant: session, service: session.merchantContentService,
            hostIsCurrent: { source.reader === session.cooperationFlowReader }))
    }
    var body: some View {
        ZStack {
            if gate.canPresent, let destination = gate.destination {
                MerchantContentDocumentView(service: gate.service, query: .project(topicID: gate.source.route.topicID),
                    focusedTopicID: gate.source.route.topicID, focusedMerchantID: destination.merchantID,
                    projectEntryIsCurrent: { gate.canPresent && gate.destination?.id == destination.id })
                    .id(destination.id)
                    .safeAreaInset(edge: .bottom) {
                        Text("merchant.acceptedProject.boundary").font(.footnote).padding().frame(maxWidth: .infinity).background(.regularMaterial)
                    }
            } else if !gate.isCurrent {
                ContentUnavailableView("merchant.acceptedProject.changed", systemImage: "lock")
            } else if gate.busy { ProgressView("merchant.loading") }
            else if let issue = gate.issue {
                MerchantFailureView(errorKey: issue, identifier: "merchant.acceptedProject", retry: { Task { await gate.load() } })
            } else { ProgressView("merchant.loading") }
        }
        .navigationTitle("merchant.acceptedProject.open")
        .onAppear { if scenePhase == .active { gate.activate(); Task { await gate.load() } } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { gate.activate(); Task { await gate.load() } } else { gate.retire() }
        }
        .onChange(of: session.sessionRevision) { _, _ in gate.retire() }
        .onDisappear { gate.retire() }
    }
}
private struct MerchantAcceptedProjectDestinationKey: EnvironmentKey {
    static let defaultValue: ((MerchantAcceptedProjectSource) -> AnyView)? = nil
}
extension EnvironmentValues {
    var merchantAcceptedProjectDestination: ((MerchantAcceptedProjectSource) -> AnyView)? {
        get { self[MerchantAcceptedProjectDestinationKey.self] }
        set { self[MerchantAcceptedProjectDestinationKey.self] = newValue }
    }
}
