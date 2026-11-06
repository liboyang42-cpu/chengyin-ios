import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Result of the existing POST `api/ai/npc/chat/data/delete` (BK-EXISTING).
/// The server hard-deletes the caller's own NPC chat log rows and returns
/// `{deleted:n}` for that one table. It is not full erasure: request receipts,
/// gateway audit rows and a reply still in flight are outside this count and may
/// later reappear in the export (AI-DELETE remains DRAFT).
public enum NPCChatLogDeletionOutcome: Equatable {
    /// The server confirmed this many log rows. Zero is a confirmed zero.
    case deleted(count: Int)
    /// The request may have reached the server but no valid confirmation came
    /// back. It is never resent automatically; only an export readback can tell.
    case unknown
}

public enum NPCChatLogDeletion {
    public static let path = "api/ai/npc/chat/data/delete"
    /// Decodes the confirmed count only. A business rejection is definite; any
    /// other unreadable 2xx body is an unknown outcome, never a guessed zero.
    public static func decode(_ bytes: Data) throws -> NPCChatLogDeletionOutcome {
        struct Envelope: Decodable {
            let code: Int
            let data: Payload?
            struct Payload: Decodable { let deleted: Int? }
        }
        guard bytes.count <= 65_536, let envelope = try? JSONDecoder().decode(Envelope.self, from: bytes) else { return .unknown }
        guard envelope.code == 200 else { throw NPCChatDataFailure.rejected }
        guard let deleted = envelope.data?.deleted, deleted >= 0 else { return .unknown }
        return .deleted(count: deleted)
    }
}

/// Dormant adapter for the existing log-deletion endpoint. Default OFF: it needs
/// its own exact endpoint approval; the export read approval, chat/model grants
/// and generic compliance writes cannot authorize it. Identity comes only from
/// the existing Authorization header. No user ID, request ID or retry is sent.
@MainActor public final class NPCChatLogDeletionService {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    private let current: () -> ComplianceSession?
    private let token: () -> String?
    private let approval: () -> OperationEndpointApproval?
    public init(configuration: APIConfiguration, transport: any HTTPTransport, current: @escaping () -> ComplianceSession?,
                token: @escaping () -> String?, approval: @escaping () -> OperationEndpointApproval? = { nil }) {
        self.configuration = configuration; self.transport = transport; self.current = current; self.token = token; self.approval = approval
    }
    public func canDelete(session: ComplianceSession) -> Bool {
        guard session.valid, current() == session, let credential = token(), AuthRequestBuilder.isValidToken(credential),
              let approval = approval() else { return false }
        return approval.allows(configuration: configuration, namespace: session.namespace, accountID: session.accountID, path: NPCChatLogDeletion.path)
    }
    /// Throws only when nothing was sent, or when the server definitely rejected
    /// the request. Once dispatched, a lost or unreadable response is `.unknown`.
    public func delete(session: ComplianceSession) async throws -> NPCChatLogDeletionOutcome {
        guard canDelete(session: session), let credential = token(), let accepted = approval() else { throw NPCChatDataFailure.unavailable }
        var request = URLRequest(url: configuration.baseURL.appendingPathComponent(NPCChatLogDeletion.path))
        request.httpMethod = "POST"; request.cachePolicy = .reloadIgnoringLocalCacheData; request.timeoutInterval = 20
        request.setValue(credential, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.httpBody = Data("{}".utf8) // Same empty body as the mini program; the server reads no fields.
        try Task.checkCancellation()
        guard current() == session, token() == credential, approval() == accepted else { throw NPCChatDataFailure.staleSession }
        let bytes: Data, status: Int
        do { (bytes, status) = try await transport.send(request) }
        catch { return .unknown }
        guard current() == session, token() == credential else { throw NPCChatDataFailure.staleSession }
        guard status != 401 else { throw NPCChatDataFailure.signedOut }
        guard (200..<300).contains(status) else { return .unknown }
        return try NPCChatLogDeletion.decode(bytes)
    }
}
