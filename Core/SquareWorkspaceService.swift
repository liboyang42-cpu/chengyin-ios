import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Injected transport only. No factory, credentials, provider, or network is created here.
@MainActor public struct SquareWorkspaceService {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    private var authorize: () throws -> Void = {}
    public init(configuration: APIConfiguration, transport: any HTTPTransport) { self.configuration = configuration; self.transport = transport }
    public func scoped(authorize: @escaping () throws -> Void) -> Self { var copy = self; copy.authorize = authorize; return copy }
    private func request(_ method: String, _ path: String, token: String, body: [String: Any]? = nil, query: [String: String] = [:]) throws -> URLRequest {
        guard AuthRequestBuilder.isValidToken(token) else { throw SquareWorkspaceFailure.invalid }
        var components = URLComponents(url: configuration.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query.keys.sorted().map { URLQueryItem(name: $0, value: query[$0]) } }
        guard let url = components.url else { throw SquareWorkspaceFailure.invalid }
        var r = URLRequest(url: url); r.httpMethod = method; r.httpShouldHandleCookies = false
        r.cachePolicy = .reloadIgnoringLocalCacheData; r.timeoutInterval = 20
        r.setValue(token, forHTTPHeaderField: "Authorization"); r.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body { r.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]); r.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        return r
    }
    private func send(_ r: URLRequest, mutation: Bool) async throws -> [String: Any] {
        try Task.checkCancellation(); try authorize()
        let response: (Data, Int)
        do { response = try await transport.send(r) } catch { throw mutation ? SquareWorkspaceFailure.unknown : error }
        do { try authorize() } catch { throw mutation ? SquareWorkspaceFailure.unknown : error }
        guard !Task.isCancelled else { throw mutation ? SquareWorkspaceFailure.unknown : CancellationError() }
        guard (200..<300).contains(response.1), let root = try? JSONSerialization.jsonObject(with: response.0) as? [String: Any],
              let code = root["code"] as? Int else { throw mutation ? SquareWorkspaceFailure.unknown : SquareWorkspaceFailure.malformed }
        guard code == 200 else { throw SquareWorkspaceFailure.rejected(code) }; return root
    }
    private func objectData(_ value: Any?) throws -> Data {
        guard let value, JSONSerialization.isValidJSONObject(value) else { throw SquareWorkspaceFailure.malformed }
        return try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    }
    public func guideline(token: String) async throws -> SquareWorkspaceGuideline {
        let root = try await send(request("GET", "api/v1/community/guidelines/active", token: token), mutation: false)
        guard let data = root["data"] as? [String: Any], let id = data["id"] as? Int, id > 0 else { throw SquareWorkspaceFailure.malformed }
        return try .init(id: id, raw: objectData(data))
    }
    public func drafts(cursor: Int? = nil, token: String) async throws -> SquareWorkspacePage {
        if let cursor, cursor <= 0 { throw SquareWorkspaceFailure.invalid }
        var query = ["limit": "30"]; if let cursor { query["cursor"] = String(cursor) }
        let root = try await send(request("GET", "api/v1/community/drafts", token: token, query: query), mutation: false)
        guard let data = root["data"] as? [String: Any], let rows = data["items"] as? [[String: Any]] else { throw SquareWorkspaceFailure.malformed }
        let items = try rows.map { try SquareWorkspacePost(data: objectData($0)) }
        return .init(items: items, nextCursor: data["nextCursor"] as? Int, hasMore: rows.count >= 30)
    }
    public func revisions(postID: Int, token: String) async throws -> Data {
        guard postID > 0 else { throw SquareWorkspaceFailure.invalid }
        let root = try await send(request("GET", "api/v1/community/posts/\(postID)/revisions", token: token), mutation: false)
        guard root["data"] is [[String: Any]] else { throw SquareWorkspaceFailure.malformed }; return try objectData(root["data"])
    }
    public func options(type: String, token: String) async throws -> [SquareWorkspaceOption] {
        guard ["ACTIVITY", "TOPIC", "ROUTE", "CLUB", "POI", "MEMBER"].contains(type) else { throw SquareWorkspaceFailure.invalid }
        let root = try await send(request("GET", "api/v1/community/reference-options/\(type)", token: token, query: ["limit": "30"]), mutation: false)
        guard let rows = root["data"] as? [[String: Any]] else { throw SquareWorkspaceFailure.malformed }
        return try rows.map { row in
            guard let id = row["id"] as? Int, id > 0, let name = row["name"] as? String else { throw SquareWorkspaceFailure.malformed }
            return .init(id: id, name: name, cityCode: (row["city_code"] ?? row["cityCode"]) as? String)
        }
    }
    public func detail(postID: Int, lane: SquareWorkspaceLane = .communityV1, token: String) async throws -> SquareWorkspacePost {
        guard postID > 0 else { throw SquareWorkspaceFailure.invalid }
        let r = lane == .legacy
            ? try AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent("api/creativesquare/info"), fields: ["id": String(postID)], token: token)
            : try request("GET", "api/v1/community/posts/\(postID)", token: token)
        let root = try await send(r, mutation: false)
        let post = try SquareWorkspacePost(data: objectData(root["data"]), lane: lane)
        guard post.id == postID else { throw SquareWorkspaceFailure.malformed }; return post
    }
    public func legacyRequest(draft: SquareWorkspaceDraft, token: String) throws -> URLRequest {
        try draft.validate(publishing: true, lane: .legacy)
        var fields = ["contents": draft.body.trimmingCharacters(in: .whitespacesAndNewlines)]
        if let id = draft.postID { fields["id"] = String(id) }
        else {
            fields["pics"] = draft.media.map(\.objectKey).joined(separator: ";")
            if let address = draft.address, !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { fields["address"] = address }
            fields["request_id"] = draft.workflowID
        }
        if let reference = draft.reference { fields["data_id"] = String(reference.id); fields["data_type"] = String(reference.legacyType) }
        // Source edit omits pics/address/coordinates/request_id; coordinates are intentionally never collected.
        return try AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent("api/creativesquare/action"), fields: fields, token: token)
    }
    public func legacyPublish(draft: SquareWorkspaceDraft, token: String) async throws {
        _ = try await send(legacyRequest(draft: draft, token: token), mutation: true)
        // Legacy acknowledgment contains no guaranteed post ID or publication state.
    }
    public func uploadRequest(bytes: Data, mimeType: String, communityProof: Bool, token: String) throws -> URLRequest {
        guard !bytes.isEmpty, bytes.count <= 12 * 1024 * 1024, ["image/jpeg", "image/png", "image/webp"].contains(mimeType) else { throw SquareWorkspaceFailure.invalid }
        var r = try request("POST", "api/common/uploadOSS", token: token)
        let boundary = "Square-" + UUID().uuidString
        let ext = mimeType == "image/png" ? "png" : mimeType == "image/webp" ? "webp" : "jpg"
        var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"image.\(ext)\"\r\nContent-Type: \(mimeType)\r\n\r\n".utf8)
        body.append(bytes); body.append(Data("\r\n".utf8))
        if communityProof { body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"bizType\"\r\n\r\nCOMMUNITY_POST\r\n".utf8)) }
        body.append(Data("--\(boundary)--\r\n".utf8)); r.httpBody = body
        r.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type"); return r
    }
    public func upload(bytes: Data, mimeType: String, communityProof: Bool, token: String) async throws -> SquareWorkspaceMedia {
        let root = try await send(uploadRequest(bytes: bytes, mimeType: mimeType, communityProof: communityProof, token: token), mutation: true)
        guard let url = root["url"] as? String, !url.isEmpty else { throw SquareWorkspaceFailure.unknown }
        let media = SquareWorkspaceMedia(objectKey: url, byteSize: root["byteSize"] as? Int, mimeType: root["mimeType"] as? String, uploadReceipt: root["uploadReceipt"] as? String)
        if communityProof && !media.hasProof { throw SquareWorkspaceFailure.missingMediaProof }; return media
    }
    public func acknowledge(guidelineID: Int, workflowID: String, token: String) async throws {
        guard guidelineID > 0, workflowID.count >= 8 else { throw SquareWorkspaceFailure.invalid }
        _ = try await send(request("POST", "api/v1/community/guidelines/ack", token: token, body: ["guidelineVersionId": guidelineID, "requestId": "guideline-\(guidelineID)-\(workflowID)", "scene": "PUBLISH"]), mutation: true)
    }
    public func upsert(draft: SquareWorkspaceDraft, guidelineID: Int, publishing: Bool, token: String) async throws -> SquareWorkspacePost {
        try draft.validate(publishing: publishing, lane: .communityV1)
        guard guidelineID > 0, publishing || draft.postID == nil || draft.sourceLifecycle == "DRAFT" else { throw SquareWorkspaceFailure.invalid }
        var ids = draft.retainedMediaIDs + draft.media.compactMap(\.existingMediaID)
        for (index, media) in draft.media.filter({ $0.existingMediaID == nil }).enumerated() {
            let root = try await send(request("POST", "api/v1/community/media/register", token: token, body: ["uploadRequestId": "media-\(index)-\(draft.workflowID)", "mediaType": "IMAGE", "objectKey": media.objectKey, "uploadReceipt": media.uploadReceipt!, "mimeType": media.mimeType!, "byteSize": media.byteSize!]), mutation: true)
            guard let data = root["data"] as? [String: Any], let id = data["id"] as? Int, id > 0 else { throw SquareWorkspaceFailure.unknown }; ids.append(id)
        }
        let reference = draft.reference
        let references: [[String: Any]] = reference.map { [["referenceType": $0.type, "referenceId": $0.id, "snapshotJson": "{}", "privacySnapshot": "PUBLIC_SAFE"]] } ?? []
        var payload: [String: Any] = ["clientRequestId": "post-\(draft.workflowID)", "communityId": draft.communityID as Any? ?? NSNull(), "postType": reference?.type == "ACTIVITY" ? "ACTIVITY_RECAP" : reference?.type == "ROUTE" ? "ROUTE_DISCOVERY" : "MOMENT", "body": draft.body.trimmingCharacters(in: .whitespacesAndNewlines), "audience": draft.audience, "commentPolicy": draft.commentPolicy, "replyApprovalEnabled": draft.replyApprovalEnabled ? 1 : 0, "slowModeSeconds": draft.slowModeSeconds, "locationPrecision": (draft.address ?? "").isEmpty ? "NONE" : "CITY", "cityCode": draft.cityCode as Any? ?? NSNull(), "poiName": draft.address as Any? ?? NSNull(), "disclosureType": draft.disclosureType, "safetyLabels": draft.safetyLabels, "guidelineVersionId": guidelineID, "mediaIds": ids, "topicCodes": reference?.type == "TOPIC" ? [String(reference!.id)] : [], "mentionedMemberIds": draft.mentionedMemberIDs, "references": references]
        if draft.postID != nil {
            guard let version = draft.expectedVersion else { throw SquareWorkspaceFailure.invalid }
            payload["expectedVersion"] = version
        }
        let path = "api/v1/community/posts" + (draft.postID.map { "/\($0)" } ?? "")
        let root = try await send(request(draft.postID == nil ? "POST" : "PATCH", path, token: token, body: payload), mutation: true)
        do { return try SquareWorkspacePost(data: objectData(root["data"])) } catch { throw SquareWorkspaceFailure.unknown }
    }
    public func publish(post: SquareWorkspacePost, workflowID: String, token: String) async throws -> SquareWorkspacePost {
        guard post.lane == .communityV1, let version = post.version, version >= 0,
              post.lifecycle == "DRAFT", workflowID.count >= 8 else { throw SquareWorkspaceFailure.invalid }
        let root = try await send(request("POST", "api/v1/community/posts/\(post.id)/publish", token: token, body: ["expectedVersion": version, "requestId": "publish-\(workflowID)"]), mutation: true)
        do {
            let result = try SquareWorkspacePost(data: objectData(root["data"]))
            guard result.id == post.id else { throw SquareWorkspaceFailure.unknown }; return result
        } catch { throw SquareWorkspaceFailure.unknown }
    }
    public func withdrawLocation(post: SquareWorkspacePost, requestID: String, token: String) async throws {
        guard post.lane == .communityV1, let version = post.version, version >= 0,
              requestID.hasPrefix("location-withdraw-") else { throw SquareWorkspaceFailure.invalid }
        _ = try await send(request("DELETE", "api/v1/community/posts/\(post.id)/location", token: token, body: ["expectedVersion": version, "requestId": requestID]), mutation: true)
    }
}
