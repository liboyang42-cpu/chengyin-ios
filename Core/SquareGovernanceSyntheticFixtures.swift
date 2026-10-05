import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public final class SquareGovernanceSyntheticTransport: SquareGovernanceOfflineTransport {
    public private(set) var requests: [URLRequest] = []
    public var mutationFailure: SquareGovernanceFailure?
    public init() {}
    public func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        let data: SquareGovernanceJSON
        if request.httpMethod != "GET" {
            if let mutationFailure { throw mutationFailure }
            data = .null
        } else {
            switch request.url?.path {
            case "/api/v1/community/me/enforcements": data = .object(["items": .array([.object(["id": .integer(91), "enforcement_type": .string("CONTENT_ACTION"), "rule_code": .string("SYNTHETIC"), "status": .string("ACTIVE"), "appeal_status": .null])])])
            case "/api/v1/community/notifications": data = .object(["items": .array([.object(["id": .integer(81), "post_id": .integer(71), "read_at": .null, "payload_json": .string("{\"action\":\"APPEAL_SUBMITTED\"}")])])])
            case "/api/v1/community/notification-preferences": data = .object(["interactionEnabled": .bool(true), "mentionEnabled": .bool(true), "socialEnabled": .bool(false)])
            default: throw SquareGovernanceFailure.invalid
            }
        }
        return (try JSONEncoder().encode(SquareGovernanceJSON.object(["code": .integer(200), "data": data])), 200)
    }
}
@MainActor public final class SquareGovernanceSyntheticAccess: SquareGovernanceAccess {
    public var identity: SquareGovernanceIdentity? = .init(accountID: 11, epoch: 1, namespace: "square-governance-synthetic")
    public var token: String? = "synthetic-only-token"
    public var comments: [SquareGovernanceComment] = [
        .init(id: 61, postID: 71, postAuthorID: 11, raw: .object(["author_id": .integer(22), "version": .integer(3), "author_approval_state": .string("PENDING"), "lifecycle": .string("PUBLISHED")]), generation: .communityV1),
        .init(id: 62, postID: 71, postAuthorID: 22, raw: .object(["author_id": .integer(11), "version": .integer(5), "author_approval_state": .string("VISIBLE"), "lifecycle": .string("PUBLISHED")]), generation: .legacySquare)
    ]
    public init() {}
    public func freshComments() async throws -> [SquareGovernanceComment] { comments }
}
