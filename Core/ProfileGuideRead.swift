import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Separate read-purpose approval; never a public-profile, media or write permission.
@MainActor @Observable public final class ProfileGuideReadAccess {
    public let context: RuntimeDependencyContext
    public let endpoints: OperationEndpointApproval
    public let revision = UUID()
    public private(set) var isRevoked = false
    public init(context: RuntimeDependencyContext, approval: OperationEndpointApproval) throws {
        try ProfileFavoritesRequestContract.validate(context, approval, paths: ProfileGuideReadRoute.paths)
        self.context = context; endpoints = approval
    }
    public func revoke() { isRevoked = true }
    public func matches(_ current: RuntimeDependencyContext) -> Bool {
        !isRevoked && ContentDraftContextFence.matches(context, current)
    }
}
public enum ProfileGuideReadRoute: Equatable {
    case list
    case detail(Int)
    public static let listPath = "api/common/infomation_list"
    public static let detailPath = "api/common/infomation_detail"
    public static let paths: Set<String> = [listPath, detailPath]
    public var path: String { switch self { case .list: return Self.listPath; case .detail: return Self.detailPath } }
    public init?(request: URLRequest, baseURL: URL) {
        if request.url?.absoluteString.utf8.elementsEqual(baseURL.appendingPathComponent(Self.listPath).absoluteString.utf8) == true,
           request.httpMethod == "POST", request.httpBody == nil, request.httpBodyStream == nil,
           request.value(forHTTPHeaderField: "Content-Type") == nil,
           request.value(forHTTPHeaderField: "Accept") == "application/json" { self = .list; return }
        guard let (_, fields) = ProfileFavoritesRequestContract.fields(request, baseURL: baseURL, paths: [Self.detailPath]),
              Set(fields.keys) == ["id"], let id = ProfileFavoritesRequestContract.positive(fields["id"]) else { return nil }
        self = .detail(id)
    }
    public func validateResponse(_ response: (Data, Int)) throws {
        guard try ProfileFavoritesRequestContract.isSuccess(response) else { return }
        do {
            switch self {
            case .list:
                struct Envelope: Decodable { let data: [SocialInformation] }
                let rows = try JSONDecoder().decode(Envelope.self, from: response.0).data
                guard rows.allSatisfy({ $0.id > 0 }), Set(rows.map(\.id)).count == rows.count else { throw APIError.malformedResponse }
            case .detail(let expected):
                struct Envelope: Decodable {
                    let data: SocialValue
                    enum CodingKeys: String, CodingKey { case data }
                    init(from decoder: Decoder) throws {
                        let c = try decoder.container(keyedBy: CodingKeys.self)
                        data = try c.decode(SocialValue.self, forKey: .data)
                    }
                }
                let data = try JSONDecoder().decode(Envelope.self, from: response.0).data
                if data.isNull || data.object?.isEmpty == true { return }
                struct Member: Decodable { let id: Int }
                struct Strict: Decodable { let data: Member }
                guard try JSONDecoder().decode(Strict.self, from: response.0).data.id == expected else { throw APIError.malformedResponse }
            }
        } catch { throw APIError.malformedResponse }
    }
}

/// Captured public source row plus current list receipt. This cannot grant a route by itself.
@MainActor @Observable public final class ProfileGuideArticleSelection {
    public let id = UUID()
    public let row: SocialInformation
    public let context: RuntimeDependencyContext
    public let viewerRevision: UInt64
    private let current: () -> Bool
    public private(set) var isRetired = false
    init(row: SocialInformation, context: RuntimeDependencyContext, viewerRevision: UInt64, current: @escaping () -> Bool) {
        self.row = row; self.context = context; self.viewerRevision = viewerRevision; self.current = current
    }
    public var isCurrent: Bool {
        guard !isRetired else { return false }
        guard current() else { isRetired = true; return false }
        return true
    }
    public func retire() { isRetired = true }
}
