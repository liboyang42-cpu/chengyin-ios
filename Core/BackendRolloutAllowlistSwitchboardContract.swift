import Foundation

/// Descriptor modeling a single fail-closed runtime rollout switch that defaults to `false`
/// in the repository until its backend and legal prerequisites are signed off.
public struct RolloutSwitchDescriptor: Sendable, Equatable, Identifiable {
    public let id: String
    public let switchName: String
    public let defaultsToFailClosedFalse: Bool
    public let hasDeterministicDisabledFallbackCopy: Bool
    public let prerequisiteSignoffTicket: String

    public init(
        id: String,
        switchName: String,
        defaultsToFailClosedFalse: Bool = true,
        hasDeterministicDisabledFallbackCopy: Bool = true,
        prerequisiteSignoffTicket: String
    ) {
        self.id = id
        self.switchName = switchName
        self.defaultsToFailClosedFalse = defaultsToFailClosedFalse
        self.hasDeterministicDisabledFallbackCopy = hasDeterministicDisabledFallbackCopy
        self.prerequisiteSignoffTicket = prerequisiteSignoffTicket
    }

    public var isSafeForRelease: Bool {
        let trimmedTicket = prerequisiteSignoffTicket.trimmingCharacters(in: .whitespacesAndNewlines)
        return defaultsToFailClosedFalse
            && hasDeterministicDisabledFallbackCopy
            && !trimmedTicket.isEmpty
    }
}

/// Deterministic switchboard contract modeling the 6 fail-closed runtime rollout switches
/// (`"switch-auth-sms-send"`, `"switch-auth-wechat-oauth"`, `"switch-auth-apple-signin"`,
/// `"switch-square-topic-like-write"`, `"switch-npc-chat-remote-delete"`, `"switch-asset-withdrawal-apply"`).
public struct BackendRolloutAllowlistSwitchboardContract: Sendable, Equatable {
    public static let canonicalSwitches: [RolloutSwitchDescriptor] = [
        RolloutSwitchDescriptor(
            id: "switch-auth-sms-send",
            switchName: "SMS Verification Send Gate (BK-AUTH-01)",
            defaultsToFailClosedFalse: true,
            hasDeterministicDisabledFallbackCopy: true,
            prerequisiteSignoffTicket: "SIGNOFF-BK-AUTH-01-SMS"
        ),
        RolloutSwitchDescriptor(
            id: "switch-auth-wechat-oauth",
            switchName: "WeChat Native OAuth Exchange Gate (BK-AUTH-02)",
            defaultsToFailClosedFalse: true,
            hasDeterministicDisabledFallbackCopy: true,
            prerequisiteSignoffTicket: "SIGNOFF-BK-AUTH-02-WECHAT"
        ),
        RolloutSwitchDescriptor(
            id: "switch-auth-apple-signin",
            switchName: "Sign in with Apple Token Exchange Gate (BK-AUTH-03)",
            defaultsToFailClosedFalse: true,
            hasDeterministicDisabledFallbackCopy: true,
            prerequisiteSignoffTicket: "SIGNOFF-BK-AUTH-03-APPLE"
        ),
        RolloutSwitchDescriptor(
            id: "switch-square-topic-like-write",
            switchName: "Square & Topic Like/Unlike Write Gate (BK-SOC-01 / BK-TOP-01)",
            defaultsToFailClosedFalse: true,
            hasDeterministicDisabledFallbackCopy: true,
            prerequisiteSignoffTicket: "SIGNOFF-BK-SOC-TOP-01-LIKE"
        ),
        RolloutSwitchDescriptor(
            id: "switch-npc-chat-remote-delete",
            switchName: "NPC Conversation Remote Delete Gate (BK-NPC-01)",
            defaultsToFailClosedFalse: true,
            hasDeterministicDisabledFallbackCopy: true,
            prerequisiteSignoffTicket: "SIGNOFF-BK-NPC-01-DELETE"
        ),
        RolloutSwitchDescriptor(
            id: "switch-asset-withdrawal-apply",
            switchName: "Wallet Asset Withdrawal Apply Gate (BK-ASSET-01)",
            defaultsToFailClosedFalse: true,
            hasDeterministicDisabledFallbackCopy: true,
            prerequisiteSignoffTicket: "SIGNOFF-BK-ASSET-01-WITHDRAW"
        ),
    ]

    public init() {}

    public static func evaluate(
        switches: [RolloutSwitchDescriptor] = canonicalSwitches
    ) -> (
        totalSwitches: Int,
        safeSwitches: Int,
        allDefaultFailClosed: Bool,
        isSwitchboardReady: Bool
    ) {
        let totalSwitches = switches.count
        let safeSwitches = switches.filter(\.isSafeForRelease).count
        let allDefaultFailClosed =
            totalSwitches > 0 && switches.allSatisfy(\.defaultsToFailClosedFalse)
        let canonicalIDs = Set(canonicalSwitches.map(\.id))
        let coveredIDs = Set(switches.map(\.id))
        let isSwitchboardReady =
            totalSwitches > 0
            && safeSwitches == totalSwitches
            && allDefaultFailClosed
            && canonicalIDs.isSubset(of: coveredIDs)
        return (
            totalSwitches: totalSwitches,
            safeSwitches: safeSwitches,
            allDefaultFailClosed: allDefaultFailClosed,
            isSwitchboardReady: isSwitchboardReady
        )
    }
}
