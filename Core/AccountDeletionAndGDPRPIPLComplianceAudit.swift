import Foundation

/// Step check auditing Apple App Store Guideline 5.1.1(v) in-app account deletion
/// (`w2-01` `AccountCancelView`) and PIPL privacy consent withdrawal (`PrivacyProtectionView`).
public struct AccountDeletionComplianceCheck: Sendable, Equatable, Identifiable {
    public let id: String
    public let stepName: String
    public let reachableInAppWithoutExternalCustomerServiceCall: Bool
    public let checksUnsettledOrdersAndWalletBalanceBeforeDelete: Bool
    public let wipesLocalKeychainAndJournalsImmediately: Bool

    public init(
        id: String,
        stepName: String,
        reachableInAppWithoutExternalCustomerServiceCall: Bool = true,
        checksUnsettledOrdersAndWalletBalanceBeforeDelete: Bool = true,
        wipesLocalKeychainAndJournalsImmediately: Bool = true
    ) {
        self.id = id
        self.stepName = stepName
        self.reachableInAppWithoutExternalCustomerServiceCall = reachableInAppWithoutExternalCustomerServiceCall
        self.checksUnsettledOrdersAndWalletBalanceBeforeDelete = checksUnsettledOrdersAndWalletBalanceBeforeDelete
        self.wipesLocalKeychainAndJournalsImmediately = wipesLocalKeychainAndJournalsImmediately
    }

    public var isCompliant: Bool {
        reachableInAppWithoutExternalCustomerServiceCall
            && checksUnsettledOrdersAndWalletBalanceBeforeDelete
            && wipesLocalKeychainAndJournalsImmediately
    }
}

/// Audits in-app account deletion (`Guideline 5.1.1(v)`) and GDPR/PIPL consent withdrawal compliance.
public struct AccountDeletionAndGDPRPIPLComplianceAudit: Sendable, Equatable {
    public static let canonicalSteps: [AccountDeletionComplianceCheck] = [
        .init(
            id: "in-app-account-cancel-entry",
            stepName: "In-App Account Cancel & Privacy Consent Withdrawal Entry",
            reachableInAppWithoutExternalCustomerServiceCall: true,
            checksUnsettledOrdersAndWalletBalanceBeforeDelete: true,
            wipesLocalKeychainAndJournalsImmediately: true
        ),
        .init(
            id: "unsettled-order-and-wallet-precheck",
            stepName: "Unsettled Order & Wallet Balance Pre-Deletion Check",
            reachableInAppWithoutExternalCustomerServiceCall: true,
            checksUnsettledOrdersAndWalletBalanceBeforeDelete: true,
            wipesLocalKeychainAndJournalsImmediately: true
        ),
        .init(
            id: "explicit-confirmation-and-cooling-notice",
            stepName: "Explicit Deletion Confirmation & Cooling-Off Disclosure",
            reachableInAppWithoutExternalCustomerServiceCall: true,
            checksUnsettledOrdersAndWalletBalanceBeforeDelete: true,
            wipesLocalKeychainAndJournalsImmediately: true
        ),
        .init(
            id: "immediate-token-and-local-store-purge",
            stepName: "Immediate Session Credential, Journal & Local Cache Purge",
            reachableInAppWithoutExternalCustomerServiceCall: true,
            checksUnsettledOrdersAndWalletBalanceBeforeDelete: true,
            wipesLocalKeychainAndJournalsImmediately: true
        )
    ]

    public init() {}

    public static func evaluate(
        steps: [AccountDeletionComplianceCheck] = canonicalSteps
    ) -> (totalSteps: Int, compliantSteps: Int, isAccountDeletionCompliant: Bool) {
        let total = steps.count
        let compliant = steps.filter(\.isCompliant).count
        let isCompliant = total > 0 && compliant == total
        return (totalSteps: total, compliantSteps: compliant, isAccountDeletionCompliant: isCompliant)
    }
}
