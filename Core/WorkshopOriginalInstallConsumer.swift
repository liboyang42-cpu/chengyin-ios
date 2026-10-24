import Foundation

/// Read projection for one original install receipt. Recovery stays on
/// `ModInstallationController.recover` and its pending store. This type does not
/// persist a request id, and it does not mint a server pass.
public struct WorkshopInstallIdentity: Equatable, Sendable {
    public let licenseId: String
    public let moduleId: String
    public let releaseId: String
    public let contentHash: String
    public let termsHash: String
    public init?(licenseId: String, moduleId: String, releaseId: String, contentHash: String, termsHash: String) {
        guard WorkshopModuleImportGate.idOK(licenseId), WorkshopModuleImportGate.idOK(moduleId),
              WorkshopModuleImportGate.idOK(releaseId), WorkshopModuleImportGate.sha256Hex(contentHash),
              WorkshopModuleImportGate.sha256Hex(termsHash) else { return nil }
        self.licenseId = licenseId
        self.moduleId = moduleId
        self.releaseId = releaseId
        self.contentHash = contentHash
        self.termsHash = termsHash
    }
}

public struct WorkshopOriginalInstallFact: Equatable, Sendable {
    public let requestID: String
    public let state: String
    public init?(requestID: String, state: String) {
        guard WorkshopOriginalInstallConsumer.canonicalRequestID(requestID) != nil,
              ["PREPARED", "INSTALLED_PRIVATE_DRAFT", "FAILED", "CANCELLED"].contains(state) else { return nil }
        self.requestID = requestID
        self.state = state
    }
}

public enum WorkshopOriginalInstallError: Error, Equatable {
    case invalidRequest
    case unknown
}

public protocol WorkshopOriginalInstallReading: Sendable {
    func request(_ requestID: String, identity: WorkshopInstallIdentity) async throws -> WorkshopOriginalInstallFact
}

public struct WorkshopOriginalInstallConsumer: Equatable, Sendable {
    public init() {}

    public static func canonicalRequestID(_ value: String) -> String? {
        guard let id = UUID(uuidString: value), id.uuidString.lowercased() == value else { return nil }
        return value
    }

    public func read(requestID: String, identity: WorkshopInstallIdentity,
                     source: any WorkshopOriginalInstallReading) async throws -> WorkshopOriginalInstallFact {
        guard Self.canonicalRequestID(requestID) != nil else { throw WorkshopOriginalInstallError.invalidRequest }
        let fact = try await source.request(requestID, identity: identity)
        guard fact.requestID == requestID else { throw WorkshopOriginalInstallError.unknown }
        return fact
    }

    public func rejectSelfReport(requestID: String) throws {
        guard Self.canonicalRequestID(requestID) != nil else { throw WorkshopOriginalInstallError.invalidRequest }
        var run = WorkshopRunServerVerification()
        try run.bind(originalRequestID: requestID)
        try run.applyJavaScriptClear(originalRequestID: requestID)
    }
}
