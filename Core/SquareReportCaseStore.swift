import Foundation

/// Retains an acknowledged case number and minimal original request identity/hash scoped
/// to account, deployment and typed target. Descriptions, tokens and raw responses are not stored.
@MainActor public final class SquareReportCaseStore {
    private let defaults: UserDefaults?
    private var memory: [String: Int] = [:]
    private var originals: [String: Data] = [:]
    init(defaults: UserDefaults?) { self.defaults = defaults }
    public static func persistent() -> SquareReportCaseStore { .init(defaults: .standard) }
    public static func ephemeral() -> SquareReportCaseStore { .init(defaults: nil) }
    private func key(_ target: SquareReportTarget, _ identity: SquareGovernanceIdentity) -> String {
        "square.report.case.\(identity.namespace.utf8.count):\(identity.namespace):\(identity.accountID):\(target.type):\(target.id)"
    }
    private func originalKey(_ target: SquareReportTarget, _ identity: SquareGovernanceIdentity) -> String {
        key(target, identity) + ".original-v1"
    }
    func original(target: SquareReportTarget, identity: SquareGovernanceIdentity) throws -> SquareReportOriginalIntent? {
        let name = originalKey(target, identity)
        let bytes: Data?
        if let defaults {
            guard let stored = defaults.object(forKey: name) else { return nil }
            guard let data = stored as? Data else { throw SquareReportFailure.unknown }
            bytes = data
        } else { bytes = originals[name] }
        guard let bytes else { return nil }
        guard let intent = try? JSONDecoder().decode(SquareReportOriginalIntent.self, from: bytes) else { throw SquareReportFailure.unknown }
        try intent.validate(target: target, identity: identity)
        return intent
    }
    /// Synchronous MainActor write + readback BEFORE dispatch. Never replace an earlier request.
    func reserveOriginal(_ review: SquareReportReview) throws {
        let target = review.snapshot.target, identity = review.snapshot.identity
        let intent = try SquareReportOriginalIntent(review)
        try intent.validate(target: target, identity: identity)
        if let old = try original(target: target, identity: identity) {
            guard old == intent else { throw SquareReportFailure.locked }
            return
        }
        let name = originalKey(target, identity), data = try JSONEncoder().encode(intent)
        if let defaults { defaults.set(data, forKey: name) } else { originals[name] = data }
        guard try original(target: target, identity: identity) == intent else { throw SquareReportFailure.unknown }
    }
    func reference(target: SquareReportTarget, identity: SquareGovernanceIdentity) throws -> Int? {
        let name = key(target, identity)
        if let saved = defaults?.object(forKey: name) {
            guard let id = saved as? Int, id > 0 else { throw SquareReportFailure.malformed }; return id
        }
        return memory[name]
    }
    func record(_ caseID: Int, target: SquareReportTarget, identity: SquareGovernanceIdentity) {
        guard caseID > 0 else { return }
        let name = key(target, identity); memory[name] = caseID; defaults?.set(caseID, forKey: name)
    }
}
