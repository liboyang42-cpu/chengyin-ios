import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Consumes an independently supplied exact-purpose approval; never issues or widens one.
@MainActor @Observable public final class ProfileInviteHistoryReadAccess {
    public let context: RuntimeDependencyContext
    public let endpoints: OperationEndpointApproval
    public let revision = UUID()
    public private(set) var isRevoked = false
    public init(context: RuntimeDependencyContext, approval: OperationEndpointApproval) throws {
        guard context.market == .china, ["player", "club", "merchant"].contains(context.role),
              context.session.accountID > 0, AuthRequestBuilder.isValidToken(context.session.token),
              approval.baseURL.absoluteString.utf8.elementsEqual(context.baseURL.absoluteString.utf8),
              approval.namespace.utf8.elementsEqual(context.session.namespace.utf8),
              approval.accountID == context.session.accountID,
              approval.paths == ProfileInviteHistoryReadRoute.paths else { throw APIError.invalidConfiguration }
        self.context = context; endpoints = approval
    }
    public func revoke() { isRevoked = true }
    public func matches(_ current: RuntimeDependencyContext) -> Bool {
        !isRevoked && ContentDraftContextFence.matches(context, current)
    }
}

/// Only the existing invitation page and its first bounded reward-ledger page.
public struct ProfileInviteHistoryReadRoute: Equatable {
    public static let invitations = "api/user/invite_list"
    public static let rewards = "api/user/points/list"
    public static let paths: Set<String> = [invitations, rewards]
    public let path: String
    public let page: Int
    public init?(request: URLRequest, baseURL: URL) {
        guard let url = request.url, url.query == nil, url.fragment == nil,
              let path = Self.paths.first(where: { url.absoluteString.utf8.elementsEqual(baseURL.appendingPathComponent($0).absoluteString.utf8) }),
              request.httpMethod == "POST", request.httpBodyStream == nil,
              request.value(forHTTPHeaderField: "Accept") == "application/json",
              let type = request.value(forHTTPHeaderField: "Content-Type"), type.hasPrefix("multipart/form-data; boundary="),
              let body = request.httpBody, body.count <= 1024, let text = String(data: body, encoding: .utf8) else { return nil }
        let boundary = String(type.dropFirst("multipart/form-data; boundary=".count))
        guard !boundary.isEmpty, boundary.count <= 70,
              boundary.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) else { return nil }
        let prefix = "--\(boundary)\r\nContent-Disposition: form-data; name=\"pageNum\"\r\n\r\n"
        guard text.hasPrefix(prefix), let end = text.range(of: "\r\n", range: text.index(text.startIndex, offsetBy: prefix.count)..<text.endIndex) else { return nil }
        let pageText = String(text[text.index(text.startIndex, offsetBy: prefix.count)..<end.lowerBound])
        guard let page = Int(pageText), page > 0, pageText == String(page), path != Self.rewards || page == 1 else { return nil }
        let fields = ["pageNum": pageText, "pageSize": path == Self.invitations ? "100" : "200"]
        guard let canonical = try? AuthRequestBuilder.makeFormRequest(url: url, fields: fields, token: nil, boundary: boundary), canonical.httpBody == body else { return nil }
        self.path = path; self.page = page
    }
}
