#if DEBUG
import SwiftUI

@MainActor struct ClubOperationsFixtureHostView: View {
    @StateObject private var store: ClubOperationsFixtureStore
    @State private var destination: Destination?
    private struct Destination: Identifiable { let id = UUID(); let target: ClubOperationsTarget }
    init(scenario: ClubOperationsFixtureScenario = .owner) { _store = StateObject(wrappedValue: ClubOperationsFixtureStore(scenario: scenario)) }
    static func selected(arguments: [String]) -> ClubOperationsFixtureScenario? {
        guard let i = arguments.firstIndex(of: "--uitesting-club-operations"), arguments.indices.contains(i + 1) else { return nil }
        return ClubOperationsFixtureScenario(rawValue: arguments[i + 1])
    }
    var body: some View {
        NavigationStack {
            List {
                Text("club.ops.fixtureOnly").accessibilityIdentifier("club.ops.fixtureNotice")
                Button("club.ops.create") { destination = .init(target: .create) }.accessibilityIdentifier("club.ops.openCreate")
                Button("club.ops.manage") { destination = .init(target: .club(81)) }.accessibilityIdentifier("club.ops.openManage")
                controls
            }.navigationTitle("club.ops.manage")
        }
        .sheet(item: $destination) { value in
            NavigationStack {
                ClubOperationsWorkspaceView(target: value.target, identity: store.identity, access: store.access, coordinator: store.coordinator)
                    .toolbar { ToolbarItemGroup(placement: .bottomBar) { controls } }
            }
        }
    }
    @ViewBuilder private var controls: some View {
        Button("club.ops.switchAccount") { store.switchAccount() }.accessibilityIdentifier("club.ops.switchAccount")
        Button("club.ops.signOut") { store.signOut() }.accessibilityIdentifier("club.ops.signOut")
        Text(store.writeCount, format: .number).accessibilityIdentifier("club.ops.writeCount")
            .accessibilityValue("account=\(store.identity?.accountID ?? 0);finished=\(store.finishedWriteCount)")
    }
}
@MainActor private final class ClubOperationsFixtureStore: ObservableObject {
    @Published private(set) var identity: ClubReadIdentity?
    @Published private(set) var writeCount = 0
    @Published private(set) var finishedWriteCount = 0
    private var delayedWriteContinuation: CheckedContinuation<Void, Never>?
    let access: ClubOperationsFixtureAccess
    let coordinator: ClubOperationsCoordinator
    init(scenario: ClubOperationsFixtureScenario) {
        access = .init(scenario: scenario); coordinator = .init(access: access); identity = access.identity
        access.onWrite = { [weak self] in self?.writeCount = self?.access.writeCount ?? 0 }
        access.onWriteFinished = { [weak self] in self?.finishedWriteCount += 1 }
        if scenario == .delayed {
            access.delayedWriteGate = { [weak self] in
                guard let self else { return }
                await withCheckedContinuation { self.delayedWriteContinuation = $0 }
            }
        }
    }
    func switchAccount() {
        access.switchAccount(); coordinator.synchronizeSession(); identity = access.identity
        releaseDelayedWrite()
    }
    func signOut() {
        access.signOut(); coordinator.synchronizeSession(); identity = access.identity
        releaseDelayedWrite()
    }
    private func releaseDelayedWrite() {
        let pending = delayedWriteContinuation; delayedWriteContinuation = nil; pending?.resume()
    }
}
#endif
