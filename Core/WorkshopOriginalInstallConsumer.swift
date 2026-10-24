import Foundation

/// Reads the original install receipt for one request id. It does not keep a second
/// install ledger and it does not turn a local projection into a server pass.
public struct WorkshopOriginalInstallFact: Equatable, Sendable {
    public let requestID: String
    public let state: String
    public init?(requestID: String, state: String) {
        guard WorkshopModuleImportGate.requestIDOK(requestID),
              ["PREPARED", "INSTALLED_PRIVATE_DRAFT", "FAILED", "CANCELLED"].contains(state) else { return nil }
        self.requestID = requestID
        self.state = state
    }
}

public protocol WorkshopOriginalInstallReading {
    func read(requestID: String) -> WorkshopOriginalInstallFact?
}

public struct WorkshopOriginalInstallRecord: Codable, Equatable, Sendable {
    public let originalRequestID: String
    public let revoked: Bool
}

public struct WorkshopOriginalInstallConsumer: Equatable {
    public private(set) var originalRequestID: String?
    public private(set) var revoked = false
    public init() {}

    public mutating func open(entry: String, requestID: String, gate: inout WorkshopModuleImportGate) throws {
        try gate.importFromNormalEntry(entry: entry, format: .metadataManifestV1, originalRequestID: requestID)
        if let existing = originalRequestID {
            guard existing == requestID else { throw WorkshopModuleImportFailure.requestMismatch }
            return
        }
        originalRequestID = requestID
        revoked = false
    }

    /// A missing row is UNKNOWN. It is not an install and it does not mint another request.
    public func read(_ source: any WorkshopOriginalInstallReading) -> WorkshopOriginalInstallFact? {
        guard let originalRequestID, !revoked else { return nil }
        guard let fact = source.read(requestID: originalRequestID), fact.requestID == originalRequestID else { return nil }
        return fact
    }

    public mutating func revoke() { revoked = true }

    public func acceptLate(_ fact: WorkshopOriginalInstallFact) -> Bool {
        !revoked && fact.requestID == originalRequestID
    }

    public func record() -> WorkshopOriginalInstallRecord? {
        guard let originalRequestID else { return nil }
        return WorkshopOriginalInstallRecord(originalRequestID: originalRequestID, revoked: revoked)
    }

    public static func restored(_ record: WorkshopOriginalInstallRecord) -> WorkshopOriginalInstallConsumer? {
        guard WorkshopModuleImportGate.requestIDOK(record.originalRequestID) else { return nil }
        var consumer = WorkshopOriginalInstallConsumer()
        consumer.originalRequestID = record.originalRequestID
        consumer.revoked = record.revoked
        return consumer
    }

    public func rejectSelfReport() throws {
        var run = WorkshopRunServerVerification()
        if let originalRequestID {
            try? run.bind(originalRequestID: originalRequestID)
        }
        try run.applyJavaScriptClear(originalRequestID: originalRequestID ?? "rejected")
    }
}
