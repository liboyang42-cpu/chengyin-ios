import SwiftUI
import Observation

/// Display and navigation facts come only from the original role/info result.
@MainActor @Observable final class MemberBenefitsReadOwner {
    struct Snapshot: Equatable {
        let id: UUID, scope: UUID, rows: [MemberBenefit]
        var opensEarnings: Bool { rows.contains { $0.opensEarnings } }
    }
    struct Navigation: Hashable {
        let id: UUID, snapshot: Snapshot
        static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }
    enum Phase: Equatable { case loading, ready(Snapshot), unavailable, failed }
    private let reader: any MemberHomeReading
    private var mounted = false, foreground = false
    private var operation = UUID()
    private var readScope: UUID?
    private var stored: Phase = .loading
    private var work: Task<Void, Never>?
    private var navigation: Navigation?
    init(reader: any MemberHomeReading) { self.reader = reader }
    deinit { work?.cancel() }
    private var sourceAvailable: Bool { reader.isSignedIn && reader.isConfigured && reader.roleInfoAvailable }
    var phase: Phase {
        guard foreground, sourceAvailable else { return .unavailable }
        if !mounted {
            // Keep the active NavigationLink's anchor while its destination covers the list.
            // No ticket means no offscreen rows; an invalid ticket cannot preserve the anchor.
            guard let selected = currentNavigation else { return .unavailable }; return .ready(selected.snapshot)
        }
        guard readScope == reader.scope else { return .loading }
        return stored
    }
    func appear(active: Bool) { mounted = true; foreground = active }
    func scene(active: Bool) {
        foreground = active
        if !active { cancelRead(); navigation = nil }
    }
    func disappear() {
        mounted = false; cancelRead()
        // Pushing an already selected destination hides this list. The destination
        // keeps its separate ticket, still guarded by source, foreground and scope.
    }
    private func cancelRead() {
        operation = UUID(); work?.cancel(); work = nil; readScope = nil; stored = .unavailable
    }
    @discardableResult func refresh() -> Task<Void, Never>? {
        guard mounted, foreground else { return nil }
        cancelRead(); navigation = nil
        guard sourceAvailable else { return nil }
        let run = operation, scope = reader.scope; readScope = scope; stored = .loading
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { if self.operation == run { self.work = nil } }
            do {
                guard !Task.isCancelled, self.accepts(run: run, scope: scope) else { return }
                let info = try await self.reader.roleInfo()
                guard !Task.isCancelled, self.accepts(run: run, scope: scope) else { return }
                self.stored = .ready(.init(id: UUID(), scope: scope, rows: info.benefits))
            } catch is CancellationError {
                guard self.operation == run else { return }; self.stored = .unavailable
            } catch {
                guard !Task.isCancelled, self.accepts(run: run, scope: scope) else { return }
                self.stored = error as? APIError == .notConfigured ? .unavailable : .failed
            }
        }
        work = task; return task
    }
    private func accepts(run: UUID, scope: UUID) -> Bool {
        mounted && foreground && operation == run && readScope == scope && reader.scope == scope && sourceAvailable
    }
    func accepts(_ snapshot: Snapshot) -> Bool {
        guard mounted, foreground, sourceAvailable, reader.scope == snapshot.scope,
              case .ready(let current) = stored else { return false }
        return current == snapshot && readScope == snapshot.scope
    }
    @discardableResult func openEarnings(_ snapshot: Snapshot) -> Navigation? {
        guard navigation == nil, accepts(snapshot), snapshot.opensEarnings else { return nil }
        let value = Navigation(id: UUID(), snapshot: snapshot); navigation = value; return value
    }
    func navigationIsCurrent(_ offered: Navigation) -> Bool {
        foreground && sourceAvailable && reader.scope == offered.snapshot.scope && offered.snapshot.opensEarnings
            && navigation?.id == offered.id && navigation?.snapshot == offered.snapshot
    }
    func navigationValue<Value>(_ offered: Navigation, build: () -> Value) -> Value? {
        guard navigationIsCurrent(offered) else { return nil }
        let value = build()
        guard navigationIsCurrent(offered) else { return nil }; return value
    }
    func closeNavigation(_ offered: UUID) { if navigation?.id == offered { navigation = nil } }
    var currentNavigation: Navigation? {
        guard let value = navigation, navigationIsCurrent(value) else { return nil }; return value
    }
    func navigation(for snapshot: Snapshot) -> Navigation? {
        guard let value = currentNavigation, value.snapshot == snapshot else { return nil }; return value
    }
    private final class BindingTicket {
        var id: UUID?
        init(_ id: UUID?) { self.id = id }
    }
    /// Each rendered binding closes only the ticket it opened or observed.
    func earningsBinding(_ snapshot: Snapshot) -> Binding<Bool> {
        let ticket = BindingTicket(navigation(for: snapshot)?.id)
        return .init(get: { [weak self] in self?.navigation(for: snapshot) != nil }, set: { [weak self] active in
            guard let self else { return }
            if active {
                if let value = self.openEarnings(snapshot) { ticket.id = value.id }
            } else if let id = ticket.id { self.closeNavigation(id) }
        })
    }

}

/// Revalidates the selected read at destination evaluation; never authorizes a wallet action.
/// Nested wallet navigation may hide this wrapper, so only the exact link binding closes its ticket.
@MainActor struct MemberBenefitsEarningsDestination: View {
    let owner: MemberBenefitsReadOwner
    let offered: MemberBenefitsReadOwner.Navigation
    let destination: () -> AnyView
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        Group {
            if scenePhase == .active, let value = owner.navigationValue(offered, build: destination) { value }
            else { Text("member.benefits.unavailable", tableName: "MemberProfile") }
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { owner.closeNavigation(offered.id) } }
    }
}
