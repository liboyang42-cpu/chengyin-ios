import Foundation

/// Presentation invalidation only. Never clears a durable original request or dispatch lock.
public enum SquareReportReadPrivacy {
    public static func hidesPrivateState(after error: Error) -> Bool {
        guard let failure = error as? SquareReportFailure else { return false }
        switch failure {
        case .signedOut, .rejected(401), .rejected(403): return true
        default: return false
        }
    }
}
