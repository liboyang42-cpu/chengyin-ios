import Combine
import SwiftUI

/// Owns the accepted profile selection while its source list is covered by a push.
/// Identity publications only revoke an existing selection; they never authorize a read.
@MainActor final class CoopRelationPresentationOwner: ObservableObject {
    @Published private(set) var selection: CoopRelationProfileSelection?
    private var selectionIsCurrent: (() -> Bool)?
    private var identityObservation: AnyCancellable?

    init(identityChanges: AnyPublisher<Void, Never>? = nil) {
        identityObservation = identityChanges?.sink { [weak self] in
            // ObservableObject publishes before its values change. Check on the next
            // main-actor turn; service fences still read the live identity immediately.
            Task { @MainActor [weak self] in self?.reconcileIdentity() }
        }
    }

    @discardableResult
    func open(_ choice: CoopRelationProfileSelection, isCurrent: @escaping () -> Bool) -> Bool {
        guard isCurrent() else { return false }
        selectionIsCurrent = isCurrent
        selection = choice
        return true
    }

    func isCurrent(_ choice: CoopRelationProfileSelection) -> Bool {
        selection?.id == choice.id && selectionIsCurrent?() == true
    }

    func close(selectionID: UUID?) {
        guard let selectionID, selection?.id == selectionID else { return }
        selectionIsCurrent = nil
        selection = nil
    }

    func reconcileIdentity() {
        guard let selected = selection, !isCurrent(selected) else { return }
        close(selectionID: selected.id)
    }

    /// A delayed pop belonging to an old presentation cannot close a newly opened one.
    var binding: Binding<CoopRelationProfileSelection?> {
        let offeredID = selection?.id
        return Binding(get: { self.selection }, set: { next in
            if next == nil { self.close(selectionID: offeredID) }
        })
    }
}
