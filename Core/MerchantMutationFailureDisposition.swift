import Foundation

/// The client source does not guarantee that an HTTP/business error is pre-effect.
/// Access checks before reservation are already unsent; after dispatch begins, only
/// this typed local gate is evidence that no transport was used. No status range implies rollback.
public enum MerchantMutationFailureDisposition {
    public static func provesNoDispatch(_ error: Error) -> Bool {
        error as? MerchantBusinessFailure == .disabled
    }
}
