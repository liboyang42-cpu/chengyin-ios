import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Dormant acquired original root-comment family. No legacy event or current post is an original receipt.
@MainActor public struct ClubCommentOriginalService: ClubCommunityPendingOutcomeQuerying {
    private let baseURL: URL
    private let transport: any HTTPTransport
    public let allowsAuthoritativeQueries: Bool
    public let allowsWrites: Bool
    public init(baseURL: URL, transport: any HTTPTransport, readsEnabled: Bool = false, writesEnabled: Bool = false) {
        self.baseURL=baseURL; self.transport=transport
        allowsAuthoritativeQueries=readsEnabled; allowsWrites=readsEnabled && writesEnabled
    }
    private func request(_ suffix: String, fields: [String:Any], session: ClubCommunitySession, record: ClubCommunityPendingRecord) throws -> URLRequest {
        guard baseURL.scheme == "https", baseURL.host != nil, baseURL.user == nil, baseURL.password == nil,
              session.identity.isSignedIn, session.identity.accountID == record.target.accountID,
              let token = session.token, AuthRequestBuilder.isValidToken(token) else { throw ClubCommunityFailure.stale }
        var request=URLRequest(url:baseURL.appendingPathComponent("api/club/post/operation/comment/"+suffix))
        request.httpMethod="POST";request.httpShouldHandleCookies=false;request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(token,forHTTPHeaderField:"Authorization");request.setValue("application/json",forHTTPHeaderField:"Content-Type")
        request.httpBody=try JSONSerialization.data(withJSONObject:fields,options:[.sortedKeys]);return request
    }
    public func queryOutcome(for record: ClubCommunityPendingRecord, session: ClubCommunitySession, check: () throws -> Void) async throws -> ClubCommunityPendingQueryResult {
        guard allowsAuthoritativeQueries else { throw ClubCommunityFailure.unavailable }
        let identity=try ClubCommentOriginalIdentity(record)
        let request=try request("receipt",fields:identity.fields,session:session,record:record)
        try Task.checkCancellation();try check()
        let (data,status)=try await transport.send(request)
        try Task.checkCancellation();try check()
        return try identity.result(ClubCommunityService.decode(data,status:status))
    }
    static func validateContent(_ operation: ClubCommunityOperation) throws {
        guard case .comment(let content) = operation, !content.isEmpty,
              content == content.trimmingCharacters(in: .whitespacesAndNewlines), content.utf16.count <= 300 else {
            throw ClubCommunityFailure.invalid
        }
    }
    func submit(_ review: ClubCommunityReview, record: ClubCommunityPendingRecord, session: ClubCommunitySession, check: () throws -> Void) async throws {
        guard allowsWrites else { throw ClubCommunityFailure.unavailable }
        let identity=try ClubCommentOriginalIdentity(record)
        guard record.operationID == review.id, record.operationKind == review.operation.labelKey,
              review.evidence.identity == session.identity else { throw ClubCommunityFailure.stale }
        guard case .comment(let content) = review.operation, !content.isEmpty,
              content == content.trimmingCharacters(in: .whitespacesAndNewlines), content.utf16.count <= 300 else {
            throw ClubCommunityFailure.invalid
        }
        var fields=identity.fields;fields["content"]=content
        let request=try request("create",fields:fields,session:session,record:record)
        try Task.checkCancellation();try check()
        let value: ClubCommunityPendingQueryResult
        do {
            let (data,status)=try await transport.send(request)
            try Task.checkCancellation();try check()
            value=try identity.result(ClubCommunityService.decode(data,status:status))
        } catch { throw ClubCommunityFailure.unknown }
        switch value {
        case .resolved(.acknowledged): return
        case .resolved(.rejected(_,let code)): throw ClubCommunityFailure.rejected(code)
        case .stillPending: throw ClubCommunityFailure.unknown
        }
    }
}
