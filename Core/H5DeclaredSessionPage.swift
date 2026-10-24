import Foundation

/// The declared H5 page calls the received session and import gates, then the platform shell.
/// Appearance does not admit, compare, import, or open. A client result is not a pass.
public struct H5DeclaredSessionPage: Equatable {
    public private(set) var session = H5DeclaredSessionEntry()
    public private(set) var imports = WorkshopModuleImportEntry()
    public private(set) var host = H5PlatformHost()

    public init() {}

    public mutating func admit(host: String, capability: String, sdkVersion: String, frozen: H5FrozenCapability) throws {
        try session.admit(host: host, capability: capability, sdkVersion: sdkVersion, frozen: frozen)
    }

    public mutating func compareServerHash(serverFrozenHash: String, expectedHash: String, originalRequestID: String) throws {
        try session.compareServerHash(serverFrozenHash: serverFrozenHash, expectedHash: expectedHash,
                                      originalRequestID: originalRequestID)
    }

    public mutating func rejectClientAnswers(_ answers: [String: String]) -> H5AnswerProtectionFailure {
        session.rejectClientAnswers(answers)
    }

    public mutating func importMetadata(_ object: [String: String], entry: String, originalRequestID: String) throws {
        try imports.importMetadata(object, entry: entry, originalRequestID: originalRequestID)
    }

    public mutating func openShell(launch: H5LaunchDescription?) -> H5HostOutcome {
        host.open(admitted: session.gate.phase == .admitted, launch: launch)
    }

    public mutating func receive(protocolVersion: String, requestID: String, sequence: Int,
                                 method: String, payload: [String: String]) -> H5HostOutcome {
        host.receive(protocolVersion: protocolVersion, requestID: requestID, sequence: sequence,
                     method: method, payload: payload)
    }
}
