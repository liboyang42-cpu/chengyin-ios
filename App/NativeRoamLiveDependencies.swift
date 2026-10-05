import Foundation

/// Reviewed composition only. The shipped application leaves this dormant; launch flags and server
/// responses cannot grant live location, presence, discovery, settlement or credential access.
@MainActor struct NativeRoamLiveDependencies {
    let approval: RoamLiveApproval?
    let transport: (any HTTPTransport)?
    let makeLocation: (@MainActor () -> any RoamDeviceLocationProviding)?
    init(approval: RoamLiveApproval? = nil, transport: (any HTTPTransport)? = nil,
         makeLocation: (@MainActor () -> any RoamDeviceLocationProviding)? = nil) {
        self.approval = approval; self.transport = transport; self.makeLocation = makeLocation
    }
    static var dormant: Self { .init() }
    /// This factory does not request permission; RuntimeNativeLocationProvider creates its manager
    /// only in currentFix(), after the live screen's explicit purpose consent and Start gesture.
    static func approved(approval: RoamLiveApproval, transport: any HTTPTransport) -> Self {
        .init(approval: approval, transport: transport, makeLocation: { RuntimeNativeLocationProvider(enabled: approval.foregroundLocation) })
    }
}
