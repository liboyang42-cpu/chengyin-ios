import Foundation

@MainActor extension AppCompositionRoot {
    /// Explicit installation point for an already-created configuration source.
    /// Nothing calls this by default. Capturing the same object preserves issuance
    /// identity; configuration updates/revocation remain in its original live reader.
    /// This never enables a backend flag or infers rights from another IM capability.
    mutating func bindNativeChannelNotificationSource(_ source: NativeChannelNotificationConfiguredSource?) {
        nativeChannelNotificationAuthorization = { context, viewerRevision in
            source?.source(for: context, viewerRevision: viewerRevision)
        }
    }
}
