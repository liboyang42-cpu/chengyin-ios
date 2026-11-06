import SwiftUI

/// Destinations outlive list snapshots. The owner blacklist uses its own authority, not a friend row.
@MainActor final class NativeFriendHomeNavigation: ObservableObject {
    enum Child {
        case metadata(NativeFriendMetadataFlow, String)
        case groups(NativeFriendMetadataFlow)
        case removal(NativeFriendRemovalFlow)
        case blacklist(NativeBlacklistFlow)
        case conversation(Int)
        var requiresFriendAuthority: Bool {
            if case .blacklist = self { return false }
            if case .groups = self { return false }
            return true
        }
        @MainActor func invalidate() {
            switch self {
            case .metadata(let flow, _): flow.invalidate()
            case .groups(let flow): flow.invalidate()
            case .removal(let flow): flow.invalidate()
            case .blacklist(let flow): flow.invalidate()
            case .conversation: break
            }
        }
    }
    let flow: NativeFriendFlow
    @Published var child: Child? { didSet { oldValue?.invalidate() } }
    init(_ flow: NativeFriendFlow) {
        self.flow = flow
        flow.onChange = { [weak self] in
            guard let self else { return }
            if self.child?.requiresFriendAuthority == true {
                if !self.flow.isCurrent { self.child = nil }
            }
            self.objectWillChange.send()
        }
    }
    func openMetadata(_ item: NativeFriendItem, using metadataFactory: (NativeFriendItem) -> NativeFriendMetadataFlow) {
        guard flow.isCurrent, !flow.busy, flow.friends.contains(item), child == nil else { return }
        child = .metadata(metadataFactory(item), item.nickname)
    }
    func openGroups(using factory: () -> NativeFriendMetadataFlow) {
        guard child == nil else { return };child = .groups(factory())
    }
    func openRemoval(_ item: NativeFriendItem, using removalFactory: (NativeFriendItem?) -> NativeFriendRemovalFlow) {
        guard flow.isCurrent, !flow.busy, flow.friends.contains(item), child == nil else { return }
        child = .removal(removalFactory(item))
    }
    func openBlacklist(using blacklistFactory: () -> NativeBlacklistFlow) {
        // The dedicated service validates its own grant, even when friend reads are unavailable.
        guard child == nil else { return }
        child = .blacklist(blacklistFactory())
    }
    func openConversation(_ item: NativeFriendItem) async {
        guard child == nil, flow.friends.contains(item), let id = await flow.existingConversation(peerID: item.peerID), flow.isCurrent, child == nil else { return }
        child = .conversation(id)
    }
    func suspend() { child = nil; flow.invalidate() }
}
