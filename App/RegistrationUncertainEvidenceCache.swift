import Foundation

/// Ephemeral display authority only. It never changes or resolves a retained create intent.
struct RegistrationUncertainEvidenceScope: Equatable {
    let readerID: ObjectIdentifier
    let identity: ProfileReadIdentity
    let intent: RegistrationCreateIntent
    let visitID: UUID

    @MainActor static func capture(flow: RegistrationUIFlow, reader: any ProfileReading,
                                   isActive: Bool) -> Self? {
        guard isActive, flow.hasCurrentSession, let identity = flow.identity,
              reader.isConfigured, reader.identity == identity,
              let intent = flow.coordinator.retainedIntent,
              case .outcomeUnknown(let requestID, _) = flow.creationState,
              requestID == intent.requestID else { return nil }
        return .init(readerID: ObjectIdentifier(reader), identity: identity, intent: intent, visitID: flow.resultOrderVisitID)
    }
}

/// A completion belongs to one explicit read in one visible scope, not a later reopening.
struct RegistrationUncertainEvidenceCache {
    struct Read: Equatable {
        let id = UUID()
        let scope: RegistrationUncertainEvidenceScope
    }
    private(set) var read: Read?
    private(set) var reading = false
    private(set) var failed = false
    private(set) var evidence: RegistrationUncertainOutcomeEvidence?

    func isCurrent(_ scope: RegistrationUncertainEvidenceScope?) -> Bool {
        guard let scope else { return false }
        return read?.scope == scope
    }
    mutating func begin(_ scope: RegistrationUncertainEvidenceScope) -> Read {
        let next = Read(scope: scope)
        read = next; reading = true; failed = false; evidence = nil
        return next
    }
    mutating func finish(_ result: RegistrationUncertainOutcomeEvidence, for token: Read,
                         current scope: RegistrationUncertainEvidenceScope?) {
        guard read == token, isCurrent(scope) else { return }
        reading = false; failed = false
        // Not applicable is absence of authority/evidence, never a terminal empty result.
        evidence = result == .notApplicable ? nil : result
    }
    mutating func fail(for token: Read, current scope: RegistrationUncertainEvidenceScope?, cancelled: Bool) {
        guard read == token, isCurrent(scope) else { return }
        reading = false; failed = !cancelled; evidence = nil
    }
    mutating func clear() { self = .init() }
}
