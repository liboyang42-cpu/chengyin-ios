import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Consumes an independently supplied approval for owned coupon metadata only.
@MainActor @Observable public final class ProfileOwnedCouponReadAccess {
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
              approval.paths == ProfileOwnedCouponReadRoute.paths else { throw APIError.invalidConfiguration }
        self.context = context; endpoints = approval
    }
    public func revoke() { isRevoked = true }
    public func matches(_ current: RuntimeDependencyContext) -> Bool {
        !isRevoked && ContentDraftContextFence.matches(context, current)
    }
}

/// Only the request emitted by AccountCollectionService for owned metadata.
public struct ProfileOwnedCouponReadRoute: Equatable {
    public static let path = "api/coupon/myrecvlist"
    public static let paths: Set<String> = [path]
    public let keyword: String?
    public init?(request: URLRequest, baseURL: URL) {
        guard let url = request.url, url.query == nil, url.fragment == nil,
              url.absoluteString.utf8.elementsEqual(baseURL.appendingPathComponent(Self.path).absoluteString.utf8),
              request.httpMethod == "POST", request.httpBodyStream == nil,
              request.value(forHTTPHeaderField: "Accept") == "application/json",
              let type = request.value(forHTTPHeaderField: "Content-Type"), type.hasPrefix("multipart/form-data; boundary="),
              let body = request.httpBody, body.count <= 32_768, let text = String(data: body, encoding: .utf8) else { return nil }
        let boundary = String(type.dropFirst("multipart/form-data; boundary=".count))
        guard !boundary.isEmpty, boundary.count <= 70,
              boundary.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) else { return nil }
        let prefix = "--\(boundary)\r\nContent-Disposition: form-data; name=\"keyword\"\r\n\r\n"
        let suffix = "\r\n--\(boundary)--\r\n"
        let fields: [String: String]
        if text == "--\(boundary)--\r\n" { fields = [:]; keyword = nil }
        else {
            guard text.hasPrefix(prefix), text.hasSuffix(suffix), text.count > prefix.count + suffix.count else { return nil }
            let value = String(text.dropFirst(prefix.count).dropLast(suffix.count))
            fields = ["keyword": value]; keyword = value
        }
        guard let canonical = try? AuthRequestBuilder.makeFormRequest(url: url, fields: fields, token: nil, boundary: boundary),
              canonical.httpBody == body else { return nil }
    }
    /// Check owner identity before projecting metadata; redemption secrets are never decoded.
    public func validateResponse(_ response: (Data, Int), accountID: Int) throws {
        guard (200..<300).contains(response.1) else { return }
        struct Status: Decodable { let code: Int }
        struct Row: Decodable { let id: Int; let memberId: Int }
        struct Envelope: Decodable { let data: [Row] }
        do {
            let code = try JSONDecoder().decode(Status.self, from: response.0).code
            guard code == 200 else { return }
            let rows = try JSONDecoder().decode(Envelope.self, from: response.0).data
            guard accountID > 0, rows.allSatisfy({ $0.id > 0 && $0.memberId == accountID }),
                  Set(rows.map(\.id)).count == rows.count else { throw APIError.malformedResponse }
        } catch { throw APIError.malformedResponse }
    }
}
