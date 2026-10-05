import SwiftUI
import Observation

/// Only the active authoritative Play node can provide this presentation.
/// A merchant row ID or public merchant NPC can never construct a node binding here.
@MainActor struct ShopNPCNodeHost {
    let identity: String
    let name: String
    let greeting: String?
    let makeCoordinator: () -> ShopNPCCoordinator
}

/// Invalidates private conversation data before authentication/authorization changes.
/// Weak retention keeps the session owner from retaining closed navigation destinations.
@MainActor @Observable final class ShopNPCSessionOwner {
    private final class Reference {
        weak var value: ShopNPCCoordinator?
        init(_ value: ShopNPCCoordinator) { self.value = value }
    }
    private var conversations: [Reference] = []
    private(set) var accessRevision: UInt64 = 0
    func register(_ coordinator: ShopNPCCoordinator) {
        conversations.removeAll { $0.value == nil }
        conversations.append(Reference(coordinator))
    }
    func invalidate() {
        accessRevision &+= 1
        conversations.forEach { $0.value?.invalidate() }
        conversations.removeAll()
    }
}

/// NavigationLink destination construction is not an ownership boundary.
/// Create exactly one fresh coordinator after navigation, and retain it in view state.
@MainActor struct ShopNPCOwnedDestination: View {
    let makeCoordinator: () -> ShopNPCCoordinator
    let name: String
    let greeting: String?
    @State private var coordinator: ShopNPCCoordinator?
    var body: some View {
        Group {
            if let coordinator { ShopNPCView(coordinator: coordinator, name: name, greeting: greeting) }
            else { ProgressView() }
        }
        .task { if coordinator == nil { coordinator = makeCoordinator() } }
        .onDisappear { coordinator?.invalidate() }
    }
}
