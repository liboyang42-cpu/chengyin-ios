import Foundation

/// After a reviewed questify.mod release, read the original install receipt and
/// recover it. A declaration is not a release. The same request id returns the
/// same receipt. A page or JavaScript self-report is rejected and is not installed.
/// The zip is not opened, payload bytes are not invented, and a client result
/// is not a server pass. The public registry stays closed.
public struct WorkshopInstallRecoverEntry: Equatable {
    public private(set) var release = WorkshopModReleaseEntry()
    public let reader = WorkshopInstallReadEntry()
    public private(set) var answers = H5AnswerProtection()
    public private(set) var receipt: WorkshopOriginalInstallFact?
    public let opensZip = false
    public let clientResultIsServerPass = false

    public init() {}

    public mutating func submitManifest(_ object: [String: String], entry: String, originalRequestID: String) throws {
        try release.submitManifest(object, entry: entry, originalRequestID: originalRequestID)
    }

    public mutating func releaseReviewed(termsHash: String, reviewed: Bool) throws {
        try release.release(termsHash: termsHash, reviewed: reviewed)
    }

    public mutating func install() throws {
        try release.install()
    }

    public mutating func installAgain() throws {
        try release.installAgain()
    }

    public func readReceipt(requestID: String, identity: WorkshopInstallIdentity,
                            source: any WorkshopOriginalInstallReading) async throws -> WorkshopOriginalInstallFact {
        guard accepts(requestID, identity: identity) else { throw WorkshopOriginalInstallError.invalidRequest }
        let fact = try await reader.read(requestID: requestID, identity: identity, source: source)
        guard fact.requestID == requestID else { throw WorkshopOriginalInstallError.unknown }
        return fact
    }

    public mutating func recover(requestID: String, identity: WorkshopInstallIdentity,
                                source: any WorkshopOriginalInstallReading) async throws -> WorkshopOriginalInstallFact {
        let fact = try await readReceipt(requestID: requestID, identity: identity, source: source)
        if let existing = receipt, existing.requestID == requestID {
            guard existing == fact else { throw WorkshopOriginalInstallError.unknown }
        }
        receipt = fact
        return fact
    }

    public func rejectPageClear(requestID: String) throws {
        try reader.rejectPageClear(requestID: requestID)
    }

    public mutating func rejectJavaScriptClear(requestID: String) throws {
        guard WorkshopOriginalInstallConsumer.canonicalRequestID(requestID) != nil else {
            throw WorkshopOriginalInstallError.invalidRequest
        }
        try answers.succeedFromJSReport()
    }

    /// A client payload is not a server pass. The shell is not opened and the bytes are not kept.
    public func recordClientResult(_ payload: [String: String]) -> Bool {
        guard let requestID = release.imports.gate.originalRequestID,
              WorkshopOriginalInstallConsumer.canonicalRequestID(requestID) != nil else { return false }
        var host = H5PlatformHost()
        _ = host.receive(protocolVersion: "1.0", requestID: requestID, sequence: 1,
                         method: "result.submit", payload: payload)
        return host.passed
    }

    /// Opening the archive stays closed. No zip is read and no payload bytes are kept.
    public func openArchive() -> WorkshopInstallFailure {
        var journey = release.journey
        return journey.consumeRuntime()
    }

    /// Public author-publish registry stays closed.
    public func registerPublic() -> WorkshopPackagePublishFailure {
        var publish = release.freezeEntry.publish
        do {
            try publish.registerPublicAuthorPublish()
        } catch let error as WorkshopPackagePublishFailure {
            return error
        } catch {
            return .publicRegistryReserved
        }
    }

    private func accepts(_ requestID: String, identity: WorkshopInstallIdentity) -> Bool {
        guard release.released, requestID == release.imports.gate.originalRequestID,
              WorkshopOriginalInstallConsumer.canonicalRequestID(requestID) != nil,
              let manifest = release.imports.gate.manifest,
              let frozen = release.freezeEntry.publish.frozen else { return false }
        return identity.moduleId == manifest.id && identity.contentHash == manifest.contentHash
            && identity.contentHash == frozen.contentHash && identity.termsHash == frozen.termsHash
    }
}
