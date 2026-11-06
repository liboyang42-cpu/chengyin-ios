import SwiftUI

/// Read-only navigation identity from the returned public-home row, not the owner,
/// release, featured activity or a guessed playable-session target.
struct MerchantGameFactsSelection: Hashable, Identifiable {
    let id = UUID()
    let row: PublicMerchantRowID
    let target: PublicMerchantHomeTarget
    let scope: UUID
    let snapshot: UUID
    init?(home: PublicMerchantHome, target: PublicMerchantHomeTarget, scope: UUID, snapshot: UUID) {
        guard let raw = home.id, let row = PublicMerchantRowID(raw) else { return nil }
        switch target {
        case .ownerMemberID(let owner): guard home.memberId == owner.rawValue else { return nil }
        case .legacyMerchantRowID(let requested): guard row == requested else { return nil }
        }
        self.row = row; self.target = target; self.scope = scope; self.snapshot = snapshot
    }
    func matches(home: PublicMerchantHome, target: PublicMerchantHomeTarget, scope: UUID, snapshot: UUID) -> Bool {
        guard self.target == target, self.scope == scope, self.snapshot == snapshot,
              let current = Self(home: home, target: target, scope: scope, snapshot: snapshot) else { return false }
        return current.row == row
    }
}

/// Create one coordinator only after navigation. Rebuilding a public-home body
/// must not replace the original result being inspected or start a network read.
@MainActor final class MerchantGameFactsPresentation: ObservableObject {
    @Published private(set) var coordinator: MerchantGamePlayerCoordinator?
    @Published private(set) var prepared = false
    private let current: () -> Bool
    private let make: () -> MerchantGamePlayerCoordinator?
    init(current: @escaping () -> Bool, make: @escaping () -> MerchantGamePlayerCoordinator?) {
        self.current = current; self.make = make
    }
    var isCurrent: Bool { current() }
    func prepare() {
        guard !prepared else { return }
        guard isCurrent else { revoke(); return }
        prepared = true
        coordinator = make()
        if !isCurrent { revoke() }
    }
    func revoke() {
        coordinator?.revoke()
        coordinator = nil
        prepared = true
    }
}

/// AppSession publication changes re-evaluate the captured identity/authorization
/// fence before displaying a private receipt. The service repeats it at dispatch.
@MainActor struct MerchantGameFactsDestination: View {
    @ObservedObject var session: AppSession
    @StateObject private var presentation: MerchantGameFactsPresentation
    let render: @MainActor (MerchantGamePlayerCoordinator, AnyView?) -> AnyView
    let chat: AnyView?
    init(session: AppSession, current: @escaping () -> Bool, make: @escaping () -> MerchantGamePlayerCoordinator?,
         render: @escaping @MainActor (MerchantGamePlayerCoordinator, AnyView?) -> AnyView, chat: AnyView?) {
        self.session = session; self.render = render; self.chat = chat
        _presentation = StateObject(wrappedValue: MerchantGameFactsPresentation(current: current, make: make))
    }
    var body: some View {
        Group {
            if !presentation.isCurrent { Text("merchantNPC.unavailable") }
            else if let coordinator = presentation.coordinator { render(coordinator, chat) }
            else if presentation.prepared { Text("merchantNPC.unavailable") }
            else { ProgressView() }
        }
        .privacySensitive()
        .onAppear { presentation.prepare() }
        .onChange(of: presentation.isCurrent) { _, current in if !current { presentation.revoke() } }
        .onChange(of: session.sessionRevision) { _, _ in presentation.revoke() }
    }
}
