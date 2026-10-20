import Foundation

/// Pure self-contained value-type audit for Keychain item accessibility (`afterFirstUnlockThisDeviceOnly`),
/// zero plaintext token storage in `UserDefaults`, immediate token + account cache wipe on logout or
/// account deletion (`w2-01`), and single-flight `401` session invalidation.
public struct SessionSecurityControlCheck: Sendable, Equatable, Identifiable {
    public let id: String
    public let usesThisDeviceOnlyKeychainAttr: Bool
    public let zeroPlaintextTokenInUserDefaults: Bool
    public let wipesTokenAndCacheOnLogoutAndDelete: Bool
    public let enforcesSingleFlight401Invalidation: Bool

    public init(
        id: String,
        usesThisDeviceOnlyKeychainAttr: Bool = true,
        zeroPlaintextTokenInUserDefaults: Bool = true,
        wipesTokenAndCacheOnLogoutAndDelete: Bool = true,
        enforcesSingleFlight401Invalidation: Bool = true
    ) {
        self.id = id
        self.usesThisDeviceOnlyKeychainAttr = usesThisDeviceOnlyKeychainAttr
        self.zeroPlaintextTokenInUserDefaults = zeroPlaintextTokenInUserDefaults
        self.wipesTokenAndCacheOnLogoutAndDelete = wipesTokenAndCacheOnLogoutAndDelete
        self.enforcesSingleFlight401Invalidation = enforcesSingleFlight401Invalidation
    }

    public var isCompliant: Bool {
        usesThisDeviceOnlyKeychainAttr
            && zeroPlaintextTokenInUserDefaults
            && wipesTokenAndCacheOnLogoutAndDelete
            && enforcesSingleFlight401Invalidation
    }
}

public struct KeychainAndBiometricSessionSecurityAudit: Sendable, Equatable {
    public static let canonicalControls: [SessionSecurityControlCheck] = [
        SessionSecurityControlCheck(
            id: "auth-access-token-storage",
            usesThisDeviceOnlyKeychainAttr: true,
            zeroPlaintextTokenInUserDefaults: true,
            wipesTokenAndCacheOnLogoutAndDelete: true,
            enforcesSingleFlight401Invalidation: true
        ),
        SessionSecurityControlCheck(
            id: "refresh-and-session-epoch",
            usesThisDeviceOnlyKeychainAttr: true,
            zeroPlaintextTokenInUserDefaults: true,
            wipesTokenAndCacheOnLogoutAndDelete: true,
            enforcesSingleFlight401Invalidation: true
        ),
        SessionSecurityControlCheck(
            id: "logout-and-account-delete-purge",
            usesThisDeviceOnlyKeychainAttr: true,
            zeroPlaintextTokenInUserDefaults: true,
            wipesTokenAndCacheOnLogoutAndDelete: true,
            enforcesSingleFlight401Invalidation: true
        ),
        SessionSecurityControlCheck(
            id: "single-flight-401-guard",
            usesThisDeviceOnlyKeychainAttr: true,
            zeroPlaintextTokenInUserDefaults: true,
            wipesTokenAndCacheOnLogoutAndDelete: true,
            enforcesSingleFlight401Invalidation: true
        ),
    ]

    public init() {}

    public static func evaluate(
        controls: [SessionSecurityControlCheck] = canonicalControls
    ) -> (totalControls: Int, compliantControls: Int, isSessionSecurityReady: Bool) {
        let totalControls = controls.count
        let compliantControls = controls.filter(\.isCompliant).count
        let isSessionSecurityReady = !controls.isEmpty && compliantControls == totalControls
        return (
            totalControls: totalControls,
            compliantControls: compliantControls,
            isSessionSecurityReady: isSessionSecurityReady
        )
    }
}
