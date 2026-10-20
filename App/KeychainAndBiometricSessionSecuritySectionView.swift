import SwiftUI
#if canImport(QuestifyCore)
import QuestifyCore
#endif

/// Self-contained presentation row for one Keychain or session security control.
public struct SessionSecurityControlRow: Sendable, Equatable, Identifiable {
    public let id: String
    public let controlCode: String
    public let title: String
    public let enforcementDetail: String
    public let isEnforced: Bool

    public init(
        id: String,
        controlCode: String,
        title: String,
        enforcementDetail: String,
        isEnforced: Bool = true
    ) {
        self.id = id
        self.controlCode = controlCode
        self.title = title
        self.enforcementDetail = enforcementDetail
        self.isEnforced = isEnforced
    }

    public var statusBadgeText: String {
        isEnforced ? "ENFORCED • SECURE" : "VIOLATION • REVIEW REQUIRED"
    }
}

/// Self-contained presentation snapshot for Keychain & session security controls:
/// 1. Keychain `ThisDeviceOnly` protection
/// 2. Zero `UserDefaults` token leak
/// 3. Logout / account-deletion full wipe & preventRestore tombstone
/// 4. Single-flight `401` guard status
public struct KeychainSessionSecuritySnapshot: Sendable, Equatable {
    public let rows: [SessionSecurityControlRow]
    public let keychainUsesThisDeviceOnly: Bool
    public let userDefaultsTokenLeakCount: Int
    public let logoutWipeAndTombstoneActive: Bool
    public let singleFlight401GuardActive: Bool

    public init(
        rows: [SessionSecurityControlRow] = Self.defaultRows,
        keychainUsesThisDeviceOnly: Bool = true,
        userDefaultsTokenLeakCount: Int = 0,
        logoutWipeAndTombstoneActive: Bool = true,
        singleFlight401GuardActive: Bool = true
    ) {
        self.rows = rows
        self.keychainUsesThisDeviceOnly = keychainUsesThisDeviceOnly
        self.userDefaultsTokenLeakCount = max(0, userDefaultsTokenLeakCount)
        self.logoutWipeAndTombstoneActive = logoutWipeAndTombstoneActive
        self.singleFlight401GuardActive = singleFlight401GuardActive
    }

    public static let defaultRows: [SessionSecurityControlRow] = [
        SessionSecurityControlRow(
            id: "sec-01-keychain-device-only",
            controlCode: "SEC-01",
            title: "Keychain ThisDeviceOnly Protection",
            enforcementDetail: "Credentials and game recovery slots use device-only Keychain accessibility bound to bundle, market, endpoint, and session realm"
        ),
        SessionSecurityControlRow(
            id: "sec-02-zero-userdefaults-leak",
            controlCode: "SEC-02",
            title: "Zero UserDefaults Token Leak",
            enforcementDetail: "Session tokens and identity proofs are never persisted in UserDefaults, plist files, or OSLog signposts"
        ),
        SessionSecurityControlRow(
            id: "sec-03-logout-full-wipe",
            controlCode: "SEC-03",
            title: "Logout & Account-Deletion Full Wipe",
            enforcementDetail: "Closes local vault and writes preventRestore tombstone before remote logout; wipes account-scoped caches and pending journals"
        ),
        SessionSecurityControlRow(
            id: "sec-04-single-flight-401",
            controlCode: "SEC-04",
            title: "Single-Flight 401 & Epoch Fence Guard",
            enforcementDetail: "Coalesces concurrent 401 responses per session epoch; stale or cross-account 401 callbacks cannot invalidate a newer session"
        )
    ]

    public static let defaultReady = KeychainSessionSecuritySnapshot()

    public var isAllSecure: Bool {
        rows.count == 4 &&
        keychainUsesThisDeviceOnly &&
        userDefaultsTokenLeakCount == 0 &&
        logoutWipeAndTombstoneActive &&
        singleFlight401GuardActive &&
        rows.allSatisfy(\.isEnforced)
    }
}

/// SwiftUI Section View displaying Keychain `ThisDeviceOnly` protection, zero `UserDefaults` token leak,
/// logout/account-deletion full wipe, and single-flight `401` guard status using `Text(verbatim:)` throughout.
@MainActor
public struct KeychainAndBiometricSessionSecuritySectionView: View {
    public let snapshot: KeychainSessionSecuritySnapshot

    public init(snapshot: KeychainSessionSecuritySnapshot = .defaultReady) {
        self.snapshot = snapshot
    }

    public var statusBadgeText: String {
        snapshot.isAllSecure
            ? "Session Security Gate: READY (4/4 Controls Enforced)"
            : "Session Security Gate: WARNING (Security Violation)"
    }

    public var thisDeviceOnlySummaryText: String {
        snapshot.keychainUsesThisDeviceOnly
            ? "Keychain Protection: WhenUnlockedThisDeviceOnly (Market & Realm Scoped)"
            : "Keychain Protection: WARNING — non-device-only protection class detected"
    }

    public var userDefaultsLeakSummaryText: String {
        "UserDefaults Token Leak Audit: \(snapshot.userDefaultsTokenLeakCount) leaked credential key(s)"
    }

    public var wipeAndTombstoneSummaryText: String {
        snapshot.logoutWipeAndTombstoneActive
            ? "Logout / Deletion Wipe: Active (Local vault closed + tombstone written before remote call)"
            : "Logout / Deletion Wipe: WARNING — incomplete local wipe or missing tombstone"
    }

    public var singleFlight401SummaryText: String {
        snapshot.singleFlight401GuardActive
            ? "Single-Flight 401 Guard: Active (Epoch-fenced; stale 401 callbacks ignored)"
            : "Single-Flight 401 Guard: WARNING — unfenced 401 handler"
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: "Keychain & Session Security Audit")
                    .font(.headline)
                    .accessibilityIdentifier("keychainSessionSecurity.title")
                Spacer()
                Text(verbatim: statusBadgeText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(snapshot.isAllSecure ? Color.green : Color.red)
                    .accessibilityIdentifier("keychainSessionSecurity.statusBadge")
            }

            Text(verbatim: thisDeviceOnlySummaryText)
                .font(.footnote.monospaced())
                .foregroundStyle(snapshot.keychainUsesThisDeviceOnly ? Color.secondary : Color.red)
                .accessibilityIdentifier("keychainSessionSecurity.thisDeviceOnlySummary")

            Text(verbatim: userDefaultsLeakSummaryText)
                .font(.footnote.monospaced())
                .foregroundStyle(snapshot.userDefaultsTokenLeakCount == 0 ? Color.secondary : Color.red)
                .accessibilityIdentifier("keychainSessionSecurity.userDefaultsLeakSummary")

            Text(verbatim: wipeAndTombstoneSummaryText)
                .font(.footnote)
                .foregroundStyle(snapshot.logoutWipeAndTombstoneActive ? Color.secondary : Color.red)
                .accessibilityIdentifier("keychainSessionSecurity.wipeAndTombstoneSummary")

            Text(verbatim: singleFlight401SummaryText)
                .font(.footnote)
                .foregroundStyle(snapshot.singleFlight401GuardActive ? Color.secondary : Color.red)
                .accessibilityIdentifier("keychainSessionSecurity.singleFlight401Summary")

            VStack(alignment: .leading, spacing: 8) {
                ForEach(snapshot.rows) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(verbatim: "[\(row.controlCode)] \(row.title)")
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Text(verbatim: row.statusBadgeText)
                                .font(.caption2.monospaced())
                                .foregroundStyle(row.isEnforced ? Color.green : Color.red)
                        }
                        Text(verbatim: row.enforcementDetail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .background(Color.secondary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .accessibilityIdentifier("keychainSessionSecurity.rowList")
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("keychainSessionSecurity.section")
    }
}
