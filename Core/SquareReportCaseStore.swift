import Foundation

/// Retains only an acknowledged case number scoped to account, deployment and
/// typed target. Report descriptions, reasons, tokens and raw server data are not stored.
@MainActor public final class SquareReportCaseStore {
    private let defaults: UserDefaults?
    private var memory: [String: Int] = [:]
    private init(defaults: UserDefaults?) { self.defaults = defaults }
    public static func persistent() -> SquareReportCaseStore { .init(defaults: .standard) }
    public static func ephemeral() -> SquareReportCaseStore { .init(defaults: nil) }
    private func key(_ target: SquareReportTarget, _ identity: SquareGovernanceIdentity) -> String {
        "square.report.case.\(identity.namespace.utf8.count):\(identity.namespace):\(identity.accountID):\(target.type):\(target.id)"
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
