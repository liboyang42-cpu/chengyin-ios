import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Source-contract adapter. Normal member actions require SocialMemberActionFactory's
/// independent grants, durable lock and readback. Square actions remain separately gated.
public struct SocialActionService {
    private let builder: SocialActionRequestBuilder
    private let transport: any HTTPTransport
    public init(configuration: APIConfiguration, transport: any HTTPTransport) {
        builder = .init(configuration: configuration); self.transport = transport
    }
    public func perform(_ command: SocialActionCommand, snapshot: SocialActionSnapshot, identity: SocialAccountIdentity, token: String) async throws -> SocialActionReceipt {
        let request: URLRequest
        do {
            try Task.checkCancellation()
            request = try builder.make(command, snapshot: snapshot, identity: identity, token: token)
        } catch { throw SocialActionWriteFailure.notSent }
        let data: Data, status: Int
        do { (data, status) = try await transport.send(request) }
        catch { throw SocialActionWriteFailure.outcomeUnknown }
        guard !Task.isCancelled else { throw SocialActionWriteFailure.outcomeUnknown }
        guard (200..<300).contains(status), let envelope = try? JSONDecoder().decode(SocialValue.self, from: data),
              let code = envelope["code"].integer else { throw SocialActionWriteFailure.outcomeUnknown }
        guard code == 200 else { throw SocialActionWriteFailure.rejected }
        // Source methods return void after code=200. Never synthesize the post/comment,
        // author, moderation outcome, report-case ID, or a new reaction count.
        if command == .toggleFollow {
            let message = envelope["msg"].text ?? ""
            if message.contains("取消关注") { return .init(synthetic: false, followed: false) }
            if message.contains("关注成功") { return .init(synthetic: false, followed: true) }
            throw SocialActionWriteFailure.outcomeUnknown
        }
        if command == .startChat {
            guard let id = envelope["data"]["conversationId"].integer, id > 0 else { throw SocialActionWriteFailure.outcomeUnknown }
            return .init(synthetic: false, conversationID: id)
        }
        return .init(synthetic: false)
    }
}
