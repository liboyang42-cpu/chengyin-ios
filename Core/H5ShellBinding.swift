import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Copies the installed host rule. A blank value, a non-https value, userinfo,
/// a query, a fragment, or a path is not an origin. An https origin with a host
/// and none of those is kept unchanged. The ticket must not appear in that string.
/// This type does not invent a URL or a nonce.
public enum H5ShellBinding {
    public static func keptOrigin(_ suppliedHost: String?, ticket: String?) -> String? {
        guard let suppliedHost else { return nil }
        let supplied = suppliedHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard supplied.hasPrefix("https://") else { return nil }
        let authority = supplied.dropFirst("https://".count)
        guard !authority.isEmpty,
              authority.allSatisfy({ !"/?#@\\ ".contains($0) }),
              let parts = URLComponents(string: supplied),
              parts.scheme == "https",
              parts.user == nil,
              parts.password == nil,
              let host = parts.host, !host.isEmpty,
              parts.percentEncodedQuery == nil,
              parts.percentEncodedFragment == nil,
              parts.path.isEmpty else { return nil }
        if let ticket, !ticket.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, supplied.contains(ticket) {
            return nil
        }
        return supplied
    }

    /// One call to the existing parent open. A missing parentOrigin, shellURL, or
    /// launchTicket returns nil and does not fill the missing field. launchTicket
    /// is passed only as the nonce argument H5LaunchDescription already has.
    @discardableResult
    public static func openExistingShell(parentOrigin: String?, shellURL: URL?, launchTicket: String?,
                                         parent: inout H5ShellParentFlow) -> URLRequest? {
        guard let parentOrigin, !parentOrigin.isEmpty,
              let shellURL,
              let launchTicket, !launchTicket.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let kept = keptOrigin(parentOrigin, ticket: launchTicket),
              shellURL.absoluteString == kept,
              let launch = H5LaunchDescription(parentOrigin: kept, nonce: launchTicket, mainToken: nil) else {
            return nil
        }
        return parent.open(shellURL: shellURL, launch: launch)
    }
}
