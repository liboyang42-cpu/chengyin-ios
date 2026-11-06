import SwiftUI

/// A rendered read action may run only during its original visible, active visit.
@MainActor final class MerchantOperationsHomeReadLifetime: ObservableObject {
    @Published private(set) var permit: UUID?
    private var visible = false
    private var active = false
    func appear(active: Bool) {
        if !visible { visible = true; self.active = active; permit = active ? UUID() : nil }
        else { sceneChanged(active: active) }
    }
    func disappear() { visible = false; permit = nil }
    func sceneChanged(active: Bool) {
        guard self.active != active else { return }
        self.active = active; permit = visible && active ? UUID() : nil
    }
    func sourceChanged() { permit = visible && active ? UUID() : nil }
    func allows(_ original: UUID?) -> Bool {
        visible && active && original != nil && original == permit
    }
}
