import Foundation

/// Client capability switches for reform plan v9 world / market / game-state scope
/// (W02, W03, W16, W18, W19, W20 and decisions U01–U08). Every switch is OFF by
/// default and there is no remote or persisted source that turns one on. The
/// contracts gated here are client-side proposals awaiting reviewed server
/// contracts; enabling one in a build is a separate, reviewed change.
public struct ReformWorldCapabilities: Equatable, Sendable {
    public enum Feature: String, CaseIterable, Sendable {
        /// W02 season / theme release pinning reads.
        case themeRelease
        /// U01 App image + video publishing media chain.
        case publishMedia
        /// W03 authoritative run action submission.
        case runAuthority
        /// U08 standard qmod manifest intake (H5 stays design-only, never a case here).
        case qmodManifest
        /// W18.4 explicit module upgrade drafts.
        case moduleUpgrade
        /// U02 in-app multi-select friend invites.
        case friendMultiInvite
        /// W16 / U05–U07 team-first stranger meeting.
        case teamFirstMeeting
        /// W16 / U07 NFC handshake. Unverified on devices; QR remains the fallback.
        case meetingNFC
        /// W19 return-home resource restore.
        case homeReturnRestore
        /// W20 CITY action writes (the existing read surface is gated separately).
        case cityActions
    }
    private let enabled: Set<Feature>
    /// The only public constructor. Release and Debug builds both start here.
    public static let disabled = ReformWorldCapabilities(enabled: [])
    private init(enabled: Set<Feature>) { self.enabled = enabled }
    public func allows(_ feature: Feature) -> Bool { enabled.contains(feature) }
    #if DEBUG
    /// Offline fixtures and Core tests only. Never reachable from release code.
    public static func syntheticFixture(_ features: Set<Feature>) -> ReformWorldCapabilities {
        ReformWorldCapabilities(enabled: features.subtracting([.meetingNFC]))
    }
    #endif
}

/// Shared bounded wire validators for the reform world contracts.
enum ReformWire {
    static func id(_ value: String) -> Bool {
        value.range(of: "\\A[A-Za-z0-9][A-Za-z0-9_.:-]{0,95}\\z", options: .regularExpression) != nil
    }
    static func requestID(_ value: String) -> Bool {
        value.range(of: "\\A[A-Za-z0-9._:-]{8,64}\\z", options: .regularExpression) != nil
    }
    static func sha256(_ value: String) -> Bool {
        value.range(of: "\\A[0-9a-f]{64}\\z", options: .regularExpression) != nil
    }
    static func version(_ value: Int64) -> Bool { (0...9_007_199_254_740_991).contains(value) }
    static func label(_ value: String, limit: Int = 160) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.utf16.count <= limit &&
        !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    }
}
