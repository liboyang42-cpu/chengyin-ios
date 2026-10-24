import Foundation

/// The declared H5 page calls the received session and import gates.
/// Appearance does not admit, compare, import, or open. Opening stays on the original SDK.
public struct H5DeclaredSessionPage: Equatable {
    public private(set) var session = H5DeclaredSessionEntry()
    public private(set) var imports = WorkshopModuleImportEntry()

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

    public mutating func open() -> H5SessionFailure {
        session.open()
    }
}
