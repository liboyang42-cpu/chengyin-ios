import Foundation

/// Mini-program pages/shezhi shows "成为俱乐部主理人" and "成为商家" only to a signed-in
/// player view (`!isMerchantView && !isClubView`); the server role decides, never a local choice.
public enum SettingsIdentityApplications {
    public static func isOffered(toRole role: String?) -> Bool {
        guard let role else { return false }
        return role != "merchant" && role != "club"
    }
}
