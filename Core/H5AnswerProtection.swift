import Foundation

/// Exclusive answer protection. Answers never ship in a client pack. Compare
/// only the server-side frozen author version. Client clock / JS report cannot
/// succeed. Same public-catalog rule as OfflinePackOperation.inspect.
public enum H5AnswerProtectionFailure: Error, Equatable {
    case waitingSource(capability: String)
    case answersMustNotShipInClientPack
    case jsSelfReportRejected
    case clientClockCannotSucceed
    case hashMismatch
    case invalidCompare
    case requestMismatch
    public var isWaitingSource: Bool {
        if case .waitingSource = self { return true }
        return false
    }
}

public enum H5AnswerProtectionPhase: String, Equatable, Sendable {
    case idle, matched, waitingSource
}

public struct H5AnswerProtection: Equatable {
    public private(set) var phase: H5AnswerProtectionPhase = .idle
    public private(set) var originalRequestID: String?
    public private(set) var matchedHash: String?
    public private(set) var failure: H5AnswerProtectionFailure?
    public init() {}
    public static func inspectClientPack(_ object: [String: String]) throws {
        try WorkshopModuleImportGate.inspect(object)
    }
    public mutating func compareClientPackAnswers(_ answers: [String: String]) throws {
        do { try Self.inspectClientPack(answers) } catch { throw fail(.answersMustNotShipInClientPack) }
        throw fail(.answersMustNotShipInClientPack)
    }
    public mutating func succeedFromJSReport() throws {
        throw fail(.jsSelfReportRejected)
    }
    public mutating func succeedFromClientClock(_ clientNow: Date) throws {
        _ = clientNow
        throw fail(.clientClockCannotSucceed)
    }
    /// Compare only server-side frozen author version. Never JS self-report.
    public mutating func compareServerFrozenAuthorVersion(serverFrozenHash: String,
                                                          expectedHash: String,
                                                          originalRequestID: String) throws {
        guard WorkshopModuleImportGate.sha256Hex(serverFrozenHash),
              WorkshopModuleImportGate.sha256Hex(expectedHash),
              WorkshopModuleImportGate.requestIDOK(originalRequestID) else {
            throw fail(.invalidCompare)
        }
        guard serverFrozenHash == expectedHash else { throw fail(.hashMismatch) }
        if let existing = self.originalRequestID {
            guard existing == originalRequestID, matchedHash == serverFrozenHash else {
                throw fail(.requestMismatch)
            }
            return
        }
        self.originalRequestID = originalRequestID
        matchedHash = serverFrozenHash
        phase = .matched
        failure = nil
    }
    public mutating func consumeH5SDKOriginal() throws -> Never {
        throw fail(.waitingSource(capability: WorkshopModuleSourceInventory.h5SdkOriginal))
    }
    @discardableResult
    private mutating func fail(_ error: H5AnswerProtectionFailure) -> H5AnswerProtectionFailure {
        failure = error
        if error.isWaitingSource { phase = .waitingSource }
        return error
    }
}
