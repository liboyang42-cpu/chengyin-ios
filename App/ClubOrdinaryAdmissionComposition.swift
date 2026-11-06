import Foundation

/// No issuer or production enablement. Hosts must inject exact context-bound approval.
@MainActor enum ClubOrdinaryAdmissionComposition {
    static func approval(context: RuntimeDependencyContext,
                         select: (RuntimeDependencyContext) -> ClubOrdinaryAdmissionApproval?) -> ClubOrdinaryAdmissionApproval? {
        guard let value = select(context), value.matches(context) else { return nil }
        return value
    }
    static func journal(namespace: String) -> (any ClubOrdinaryAdmissionJournaling)? {
        guard !namespace.isEmpty,
              let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return ClubOrdinaryAdmissionFileJournal(root: root.appendingPathComponent("ClubOrdinaryAdmissionPending", isDirectory: true), namespace: namespace)
    }
}
