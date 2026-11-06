import Foundation
import CoreFoundation
import CryptoKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum ClubRoleRevocationFailure: Error { case unavailable, stale, invalid, forbidden, unknown, persistence, locked }
/// Independently reviewed deployment input. Existing typed grants are supplied, never created here.
public struct ClubRoleRevocationApproval: Equatable {
    public let endpoints: OperationEndpointApproval
    public let scopes: Set<ClubGovernanceScope>
    public let grants: Set<ClubGovernanceActionGrant>
    public let reviewedPolicyVersion: String
    public let reads: Bool, writes: Bool
    public init(endpoints: OperationEndpointApproval, scopes: Set<ClubGovernanceScope>, grants: Set<ClubGovernanceActionGrant>, reviewedPolicyVersion: String, reads: Bool = false, writes: Bool = false) throws {
        guard !scopes.isEmpty, scopes.allSatisfy({ scope in
            guard let club = scope.clubID, club > 0 else { return false }
            return scope == ClubGovernanceScope(clubID: club, activityID: scope.activityID) && (scope.activityID == nil || scope.activityID! > 0)
        }), grants.allSatisfy({ $0.operation == .revokeRole && scopes.contains($0.scope) }),
            !reviewedPolicyVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !writes || reads else { throw APIError.invalidConfiguration }
        self.endpoints = endpoints; self.scopes = scopes; self.grants = grants; self.reviewedPolicyVersion = reviewedPolicyVersion; self.reads = reads; self.writes = writes
    }
    public func permits(_ context: RuntimeDependencyContext, scope: ClubGovernanceScope, writing: Bool) -> Bool {
        let required = writing ? ClubRoleRevocationRoute.paths : ClubRoleRevocationRoute.readPaths
        return context.market == .china && reads && (!writing || writes) && scopes.contains(scope)
            && context.baseURL == endpoints.baseURL && context.session.accountID == endpoints.accountID
            && context.session.namespace == endpoints.namespace && required.isSubset(of: endpoints.paths)
    }
    public func sameReadAuthority(as other: Self) -> Bool {
        endpoints == other.endpoints && scopes == other.scopes && reviewedPolicyVersion == other.reviewedPolicyVersion && reads == other.reads
    }
    public var productionApproval: ClubGovernanceProductionApproval? {
        guard writes else { return nil }
        return try? .init(market: .china, endpoints: endpoints, grants: grants, reviewedPolicyVersion: reviewedPolicyVersion)
    }
}
/// Exact original JSON routes. Not a generic club path or arbitrary scope grant.
public struct ClubRoleRevocationRoute {
    public static let receiptPath = "api/club/roles/revoke-receipt"
    public static let writePath = "api/club/roles/revoke"
    public static let readPaths: Set<String> = [receiptPath, "api/club/detail", "api/club/members", "api/club/access/me", "api/club/roles/list"]
    public static let paths = readPaths.union([writePath])
    public let path: String, scope: ClubGovernanceScope
    public let command: ClubGovernanceCommand?
    public var writing: Bool { path == Self.writePath }
    public init?(request: URLRequest, baseURL: URL) {
        guard request.httpMethod == "POST", request.httpBodyStream == nil,
              request.value(forHTTPHeaderField: "Content-Type") == "application/json", let url = request.url,
              let path = Self.paths.first(where: { baseURL.appendingPathComponent($0) == url }),
              let bytes = request.httpBody, bytes.count < 4096, let text = String(data: bytes, encoding: .utf8),
              (try? ContentDraftJSON.parse(text)) != nil,
              let fields = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any],
              let club = Self.integer(fields[path == "api/club/detail" ? "id" : "clubId"], positive: true) else { return nil }
        var keys: Set<String> = path == "api/club/detail" ? ["id"] : ["clubId"]
        var activity: Int?
        if fields["activityId"] != nil {
            guard !["api/club/detail", "api/club/members"].contains(path), let value = Self.integer(fields["activityId"], positive: true) else { return nil }
            activity = value; keys.insert("activityId")
        }
        if path == Self.writePath || path == Self.receiptPath {
            keys.formUnion(["assignmentId", "version", "requestId"])
            guard Self.integer(fields["assignmentId"], positive: true) != nil,
                  let version = Self.integer(fields["version"], positive: false), version <= Int(Int32.max),
                  let id = fields["requestId"] as? String, Self.requestID(id) else { return nil }
            if path == Self.writePath {
                keys.insert("reason")
                guard fields["reason"] as? String == ClubGovernanceFormDraft.revokeRoleReason else { return nil }
            } else {
                keys.formUnion(["targetMemberId", "roleCode", "reasonSHA256"])
                guard Self.integer(fields["targetMemberId"], positive: true) != nil,
                      let role = fields["roleCode"] as? String, Self.roles(activity).contains(role),
                      let hash = fields["reasonSHA256"] as? String, Self.hash(hash) else { return nil }
            }
        }
        guard Set(fields.keys) == keys else { return nil }
        self.path = path; scope = .init(clubID: club, activityID: activity)
        if path == Self.writePath {
            guard let values = try? JSONDecoder().decode([String: ClubGovernanceValue].self, from: bytes),
                  let command = try? ClubGovernanceCommand(operation: .revokeRole, scope: scope, values: values.filter { !["clubId", "activityId"].contains($0.key) }),
                  command.fields == values else { return nil }
            self.command = command
        } else { command = nil }
    }
    static func roles(_ activity: Int?) -> Set<String> { activity == nil ? ["CLUB_CO_OWNER", "CLUB_OPERATOR"] : ["EVENT_LEAD", "EVENT_CHECKIN"] }
    public static func requestID(_ value: String) -> Bool {
        guard value.hasPrefix("club-native-") else { return false }
        let uuid = String(value.dropFirst(12)); return UUID(uuidString: uuid)?.uuidString == uuid
    }
    static func hash(_ value: String) -> Bool { value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) } }
    static func digest(_ text: String) -> String { SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined() }
    private static func integer(_ value: Any?, positive: Bool) -> Int? {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), let v = Int(n.stringValue), v >= (positive ? 1 : 0) else { return nil }; return v
    }
}
public struct ClubRoleRevocationReceipt: Decodable, Equatable {
    public let clubId: Int, activityId: Int?, assignmentId: Int, targetMemberId: Int, version: Int
    public let requestId: String, roleCode: String, reasonSHA256: String, state: String
    public let auditId: Int?, appliedAt: Int64?
    func validate(_ entry: ClubRoleRevocationEntry) throws {
        guard clubId == entry.clubID, activityId == entry.activityID, assignmentId == entry.assignmentID,
              targetMemberId == entry.targetMemberID, version == entry.assignmentVersion, requestId == entry.requestID,
              roleCode == entry.roleCode, reasonSHA256 == entry.reasonSHA256, ["UNKNOWN", "APPLIED"].contains(state),
              state != "APPLIED" || ((auditId ?? 0) > 0 && (appliedAt ?? 0) > 0) else { throw ClubRoleRevocationFailure.invalid }
    }
}
@MainActor public final class ClubRoleRevocationClient {
    private let transport: any HTTPTransport
    private let current: () -> RuntimeDependencyContext?
    private let approval: (RuntimeDependencyContext) -> ClubRoleRevocationApproval?
    private let unauthorized: (RuntimeDependencyContext) -> Void
    public init(transport: any HTTPTransport, current: @escaping () -> RuntimeDependencyContext?, approval: @escaping (RuntimeDependencyContext) -> ClubRoleRevocationApproval?, unauthorized: @escaping (RuntimeDependencyContext) -> Void = { _ in }) {
        self.transport = transport; self.current = current; self.approval = approval; self.unauthorized = unauthorized
    }
    public func receipt(_ entry: ClubRoleRevocationEntry, context: RuntimeDependencyContext) async throws -> ClubRoleRevocationReceipt {
        try entry.validate(context)
        guard current() == context, let issued = approval(context), issued.permits(context, scope: entry.scope, writing: false) else { throw ClubRoleRevocationFailure.unavailable }
        var request = URLRequest(url: context.baseURL.appendingPathComponent(ClubRoleRevocationRoute.receiptPath)); request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.setValue(context.session.token, forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: entry.fields, options: [.sortedKeys])
        guard ClubRoleRevocationRoute(request: request, baseURL: context.baseURL) != nil, current() == context, approval(context)?.sameReadAuthority(as: issued) == true, !Task.isCancelled else { throw ClubRoleRevocationFailure.stale }
        let (data, status) = try await transport.send(request)
        guard current() == context, approval(context)?.sameReadAuthority(as: issued) == true, !Task.isCancelled else { throw ClubRoleRevocationFailure.stale }
        guard data.count <= 1_048_576, let text = String(data: data, encoding: .utf8), (try? ContentDraftJSON.parse(text)) != nil else { throw ClubRoleRevocationFailure.invalid }
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        if status == 401 || envelope.code == 401 { unauthorized(context); throw ClubRoleRevocationFailure.forbidden }
        if status == 403 || envelope.code == 403 { throw ClubRoleRevocationFailure.forbidden }
        guard (200..<300).contains(status), envelope.code == 200, let receipt = envelope.data else { throw ClubRoleRevocationFailure.unknown }
        try receipt.validate(entry); return receipt
    }
    private struct Envelope: Decodable { let code: Int; let data: ClubRoleRevocationReceipt? }
}
