import Foundation

/// Exclusive run pass/fail. Completion comes from a server receipt bound to
/// originalRequestID. JS / H5 self-reported clear is rejected. UNKNOWN keeps
/// the original intent, does not mint a new requestId, and does not treat the
/// current projection as success.
public enum WorkshopRunVerifyFailure: Error, Equatable {
    case waitingSource(capability: String)
    case jsSelfReportRejected
    case notBound
    case requestMismatch
    case notUnknown
    case invalidReceipt
    public var isWaitingSource: Bool {
        if case .waitingSource = self { return true }
        return false
    }
}

public enum WorkshopRunPhase: String, Equatable, Sendable {
    case idle, bound, passed, failed, unknown, waitingSource
}

public enum WorkshopRunIntent: String, Equatable, Sendable {
    case run
}

public enum WorkshopRunReceiptKind: String, Equatable, Sendable {
    case serverPass, serverFail, unknown
}

public struct WorkshopServerReceipt: Equatable, Sendable {
    public let originalRequestID: String
    public let kind: WorkshopRunReceiptKind
    /// Current projection is never success proof for UNKNOWN.
    public let projectionSucceeded: Bool
    public init?(originalRequestID: String, kind: WorkshopRunReceiptKind, projectionSucceeded: Bool) {
        guard WorkshopModuleImportGate.requestIDOK(originalRequestID) else { return nil }
        self.originalRequestID = originalRequestID
        self.kind = kind
        self.projectionSucceeded = projectionSucceeded
    }
}

public struct WorkshopRunOriginalRecord: Equatable, Sendable {
    public let originalRequestID: String
    public let intent: WorkshopRunIntent
    public let succeeded: Bool
    public let phase: WorkshopRunPhase
}

public struct WorkshopRunServerVerification: Equatable {
    public private(set) var phase: WorkshopRunPhase = .idle
    public private(set) var originalRequestID: String?
    public private(set) var originalIntent: WorkshopRunIntent?
    public private(set) var failure: WorkshopRunVerifyFailure?
    public init() {}
    public mutating func bind(originalRequestID: String?, intent: WorkshopRunIntent = .run) throws {
        guard let originalRequestID, WorkshopModuleImportGate.requestIDOK(originalRequestID) else {
            throw fail(.invalidReceipt)
        }
        if let existing = self.originalRequestID {
            guard existing == originalRequestID else { throw fail(.requestMismatch) }
            return
        }
        self.originalRequestID = originalRequestID
        originalIntent = intent
        phase = .bound
        failure = nil
    }
    public mutating func applyServerReceipt(_ receipt: WorkshopServerReceipt) throws {
        guard phase == .bound || phase == .unknown, let originalRequestID, let originalIntent else {
            throw fail(.notBound)
        }
        guard receipt.originalRequestID == originalRequestID else { throw fail(.requestMismatch) }
        _ = originalIntent
        switch receipt.kind {
        case .serverPass:
            phase = .passed
            failure = nil
        case .serverFail:
            phase = .failed
            failure = nil
        case .unknown:
            phase = .unknown
            failure = nil
        }
    }
    public mutating func applyJavaScriptClear(originalRequestID: String) throws {
        _ = originalRequestID
        throw fail(.jsSelfReportRejected)
    }
    public mutating func applyH5SelfReport(originalRequestID: String) throws {
        _ = originalRequestID
        throw fail(.jsSelfReportRejected)
    }
    /// UNKNOWN recover keeps original intent. Does not mint a new requestId.
    public mutating func recoverOriginal(originalRequestID: String) throws -> WorkshopRunOriginalRecord {
        guard phase == .unknown else { throw fail(.notUnknown) }
        guard let bound = self.originalRequestID, let intent = originalIntent else { throw fail(.notBound) }
        guard bound == originalRequestID else { throw fail(.requestMismatch) }
        return WorkshopRunOriginalRecord(originalRequestID: bound, intent: intent,
                                         succeeded: false, phase: .unknown)
    }
    public var currentProjectionIsSuccess: Bool { phase == .passed }
    public mutating func consumeUnpushedIOSCandidate() throws -> Never {
        throw fail(.waitingSource(capability: WorkshopModuleSourceInventory.unpushedIOS))
    }
    @discardableResult
    private mutating func fail(_ error: WorkshopRunVerifyFailure) -> WorkshopRunVerifyFailure {
        failure = error
        if error.isWaitingSource { phase = .waitingSource }
        return error
    }
}
