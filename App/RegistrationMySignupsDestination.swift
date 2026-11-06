import SwiftUI

/// Session host for the source "查看我的报名" entry on the already-registered checkout banner.
private struct RegistrationMySignupsDestinationKey: EnvironmentKey {
    static let defaultValue: (() -> AnyView)? = nil
}
extension EnvironmentValues {
    var registrationMySignupsDestination: (() -> AnyView)? {
        get { self[RegistrationMySignupsDestinationKey.self] }
        set { self[RegistrationMySignupsDestinationKey.self] = newValue }
    }
}
