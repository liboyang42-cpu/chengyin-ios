import Foundation

/// Normal entry over the received H5 gate. A declared surface can be admitted.
/// Opening the container stays on the missing original SDK and is never success.
public struct H5DeclaredSessionEntry: Equatable {
    public private(set) var gate = H5SessionCapabilityGate()

    public init() {}

    public mutating func admit(host: String, capability: String, sdkVersion: String, frozen: H5FrozenCapability) throws {
        try gate.admitDeclaredSurface(host: host, capability: capability, sdkVersion: sdkVersion, frozen: frozen)
    }

    public mutating func open() -> H5SessionFailure {
        do {
            try gate.openH5Session()
        } catch let error as H5SessionFailure {
            return error
        } catch {
            return .waitingSource(capability: "h5.sdk.original")
        }
    }
}
