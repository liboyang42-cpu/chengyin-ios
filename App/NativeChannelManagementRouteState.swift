import SwiftUI

/// The real NavigationLink owns this state. Each binding belongs to one visit and
/// observes its owner weakly. Closing and reopening cannot revive an older child.
@MainActor final class NativeChannelManagementRouteState: ObservableObject {
    @Published private(set) var visitID = UUID()
    @Published var isPresented = false {
        didSet { if oldValue && !isPresented { visitID = UUID() } }
    }
    var binding: Binding<Bool> {
        let visit = visitID
        return Binding(get: { [weak self] in
            guard let self, self.visitID == visit else { return false }
            return self.isPresented
        }, set: { [weak self] value in
            guard let self, self.visitID == visit else { return }
            self.isPresented = value
        })
    }
    static func child(_ presented: Binding<Bool>, parentCurrent: @escaping () -> Bool) -> Binding<Bool> {
        Binding(get: { parentCurrent() && presented.wrappedValue }, set: { value in
            // A stale child may dismiss its own visit, but never reopen an ancestor.
            presented.wrappedValue = value && parentCurrent()
        })
    }
}

/// Item navigation needs a visit identity as well as equality: A -> B -> A is a
/// new visit to A. Neither a retained binding nor a retained child owns this state.
@MainActor final class NativeChannelManagementSelectionState<Value: Hashable>: ObservableObject {
    @Published private(set) var visitID = UUID()
    @Published var selected: Value? {
        didSet { if oldValue != selected { visitID = UUID() } }
    }
    var binding: Binding<Value?> {
        let visit = visitID
        return Binding(get: { [weak self] in
            guard let self, self.visitID == visit else { return nil }
            return self.selected
        }, set: { [weak self] value in
            guard let self, self.visitID == visit else { return }
            self.selected = value
        })
    }
    func route(for value: Value, parentCurrent: @escaping () -> Bool) -> Binding<Bool> {
        let visit = visitID
        return Binding(get: { [weak self] in
            guard let self, self.visitID == visit, self.selected == value else { return false }
            return parentCurrent()
        }, set: { [weak self] presented in
            guard let self, self.visitID == visit, self.selected == value else { return }
            if !presented || !parentCurrent() { self.selected = nil }
        })
    }
}
