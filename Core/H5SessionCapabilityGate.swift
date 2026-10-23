import Foundation

/// Exclusive H5 session capability gate. Allow only a signed domain allowlist
/// plus the SDK capability set from a frozen package. Missing original H5/SDK
/// spec is WAITING_SOURCE. Version incompatibility rejects. Do not open
/// arbitrary H5 (DiscoveryContracts already bans arbitrary banner H5).
public enum H5SessionFailure: Error, Equatable {
    case waitingSource(capability: String)
    case unsignedDomain
    case capabilityNotGranted
    case versionIncompatible
    case arbitraryH5Forbidden
    case notAdmitted
    case invalidSurface
    public var isWaitingSource: Bool {
        if case .waitingSource = self { return true }
        return false
    }
}

public enum H5SessionPhase: String, Equatable, Sendable {
    case idle, admitted, waitingSource
}

public struct H5FrozenCapability: Equatable, Sendable {
    public let signedDomains: [String]
    public let sdkCapabilities: [String]
    public let packageVersion: String
    public let contentHash: String
    public init?(signedDomains: [String], sdkCapabilities: [String],
                 packageVersion: String, contentHash: String) {
        guard !signedDomains.isEmpty, signedDomains.count <= 32,
              signedDomains.allSatisfy(WorkshopModuleImportGate.idOK),
              Set(signedDomains).count == signedDomains.count,
              !sdkCapabilities.isEmpty, sdkCapabilities.count <= 32,
              sdkCapabilities.allSatisfy(WorkshopModuleImportGate.idOK),
              Set(sdkCapabilities).count == sdkCapabilities.count,
              WorkshopModuleImportGate.versionOK(packageVersion),
              WorkshopModuleImportGate.sha256Hex(contentHash) else { return nil }
        self.signedDomains = signedDomains
        self.sdkCapabilities = sdkCapabilities
        self.packageVersion = packageVersion
        self.contentHash = contentHash
    }
}

/// Declared-surface admission only. Opening a real H5 container needs original spec.
public struct H5SessionCapabilityGate: Equatable {
    public private(set) var phase: H5SessionPhase = .idle
    public private(set) var frozen: H5FrozenCapability?
    public private(set) var admittedHost: String?
    public private(set) var admittedCapability: String?
    public private(set) var failure: H5SessionFailure?
    public init() {}
    public mutating func admitDeclaredSurface(host: String, capability: String,
                                              sdkVersion: String, frozen: H5FrozenCapability) throws {
        guard WorkshopModuleImportGate.idOK(host), WorkshopModuleImportGate.idOK(capability),
              WorkshopModuleImportGate.versionOK(sdkVersion) else { throw fail(.invalidSurface) }
        guard frozen.signedDomains.contains(host) else { throw fail(.unsignedDomain) }
        guard frozen.sdkCapabilities.contains(capability) else { throw fail(.capabilityNotGranted) }
        guard sdkVersion == frozen.packageVersion else { throw fail(.versionIncompatible) }
        self.frozen = frozen
        admittedHost = host
        admittedCapability = capability
        phase = .admitted
        failure = nil
    }
    public mutating func openArbitraryH5(_ url: String) throws {
        _ = url
        throw fail(.arbitraryH5Forbidden)
    }
    /// Missing original H5 container / SDK spec. Never a fake success open.
    public mutating func openH5Session() throws -> Never {
        throw fail(.waitingSource(capability: "h5.sdk.original"))
    }
    public mutating func consumeH5ContainerOriginal() throws -> Never {
        throw fail(.waitingSource(capability: "h5.container.original"))
    }
    public mutating func consumeH5SDKOriginal() throws -> Never {
        throw fail(.waitingSource(capability: "h5.sdk.original"))
    }
    @discardableResult
    private mutating func fail(_ error: H5SessionFailure) -> H5SessionFailure {
        failure = error
        if error.isWaitingSource { phase = .waitingSource }
        return error
    }
}
