import SwiftUI

/// Mini-program `wx.switchTab` equivalent for nested screens (for example the
/// order list's 去发现城市路线). Only the root TabView installs a live switch;
/// any other host keeps the inert default, so a screen never navigates by accident.
struct RootTabSwitch {
    let isAvailable: Bool
    private let select: @MainActor (RootTab) -> Void
    init(_ select: @escaping @MainActor (RootTab) -> Void) { isAvailable = true; self.select = select }
    private init() { isAvailable = false; select = { _ in } }
    static let unavailable = RootTabSwitch()
    @MainActor func callAsFunction(_ tab: RootTab) { select(tab) }
}

private struct RootTabSwitchKey: EnvironmentKey {
    static let defaultValue = RootTabSwitch.unavailable
}

extension EnvironmentValues {
    var rootTabSwitch: RootTabSwitch {
        get { self[RootTabSwitchKey.self] }
        set { self[RootTabSwitchKey.self] = newValue }
    }
}
