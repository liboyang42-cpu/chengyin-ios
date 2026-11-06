import SwiftUI

@MainActor struct ClubBadgeHost {
    let id: String
    let make: () -> ClubBadgeManagementFlow?
}
private struct ClubBadgeHostFactoryKey: EnvironmentKey {
    static let defaultValue: @MainActor (Int) -> ClubBadgeHost? = { _ in nil }
}
extension EnvironmentValues {
    var clubBadgeHostFactory: @MainActor (Int) -> ClubBadgeHost? {
        get { self[ClubBadgeHostFactoryKey.self] }
        set { self[ClubBadgeHostFactoryKey.self] = newValue }
    }
}
@MainActor struct ClubBadgeManagementEntry: View {
    let host: ClubBadgeHost
    var body: some View {
        NavigationLink { ClubBadgeManagementView(host: host).id(host.id) } label: {
            Label { Text("title", tableName: "ClubBadge") } icon: { Image(systemName: "medal") }
        }.accessibilityIdentifier("club.badges.entry")
    }
}
@MainActor final class ClubBadgeHostModel: ObservableObject {
    @Published private(set) var flow: ClubBadgeManagementFlow?
    @Published private(set) var revision = 0
    @Published private(set) var working = false
    private let host: ClubBadgeHost
    private var task: Task<Void, Never>?
    private var generation = UUID()
    init(host: ClubBadgeHost) { self.host = host }
    func start() {
        retire(); flow = host.make()
        perform { await $0.refresh() }
    }
    func perform(_ work: @escaping (ClubBadgeManagementFlow) async -> Void) {
        guard !working, let flow, flow.isCurrent else { return }
        working = true; let ticket = generation
        task = Task { [weak self] in
            await work(flow)
            guard let self, ticket == self.generation else { return }
            if !flow.isCurrent { self.retire(); return }
            self.working = false; self.revision &+= 1
        }
    }
    func changed() { revision &+= 1 }
    func retire() {
        generation = UUID(); task?.cancel(); task = nil
        flow?.invalidate(); flow = nil; working = false; revision &+= 1
        // The persistent original request journal is never deleted here.
    }
}
