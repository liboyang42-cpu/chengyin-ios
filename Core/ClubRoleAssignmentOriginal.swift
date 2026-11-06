import Foundation
import CoreFoundation
import CryptoKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum ClubRoleAssignmentFailure: Error { case unavailable, stale, invalid, forbidden, unknown, persistence, locked }
/// Independently reviewed deployment input. Existing typed grants are supplied, never created here.
public struct ClubRoleAssignmentApproval: Equatable {
    public let endpoints: OperationEndpointApproval
    public let scopes: Set<ClubGovernanceScope>
    public let grants: Set<ClubGovernanceActionGrant>
    public let reviewedPolicyVersion: String
    public let reads: Bool, writes: Bool
    public init(endpoints: OperationEndpointApproval, scopes: Set<ClubGovernanceScope>, grants: Set<ClubGovernanceActionGrant>, reviewedPolicyVersion: String, reads: Bool = false, writes: Bool = false) throws {
        guard !scopes.isEmpty, scopes.allSatisfy({ scope in
            guard let club = scope.clubID, club > 0 else { return false }
            return scope == ClubGovernanceScope(clubID: club, activityID: scope.activityID) && (scope.activityID == nil || scope.activityID! > 0)
        }), grants.allSatisfy({ $0.operation == .assignRole && scopes.contains($0.scope) }),
            !reviewedPolicyVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !writes || reads else { throw APIError.invalidConfiguration }
        self.endpoints = endpoints; self.scopes = scopes; self.grants = grants; self.reviewedPolicyVersion = reviewedPolicyVersion; self.reads = reads; self.writes = writes
    }
    public func permits(_ context: RuntimeDependencyContext, scope: ClubGovernanceScope, writing: Bool) -> Bool {
        let required = writing ? ClubRoleAssignmentRoute.paths : ClubRoleAssignmentRoute.readPaths
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
/// Exact original assign request and independent historical read. No expiry feature is invented.
public struct ClubRoleAssignmentRoute {
    public static let receiptPath = "api/club/roles/assign-receipt"
    public static let writePath = "api/club/roles/assign"
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
              let club = Self.positive(fields[path == "api/club/detail" ? "id" : "clubId"]) else { return nil }
        var keys: Set<String> = path == "api/club/detail" ? ["id"] : ["clubId"]
        var activity: Int?
        if fields["activityId"] != nil {
            guard !["api/club/detail", "api/club/members"].contains(path), let value = Self.positive(fields["activityId"]) else { return nil }
            activity = value; keys.insert("activityId")
        }
        if path == Self.writePath || path == Self.receiptPath {
            keys.formUnion(["targetMemberId", "roleCode", "requestId"])
            guard Self.positive(fields["targetMemberId"]) != nil,
                  let role = fields["roleCode"] as? String, ClubRoleRevocationRoute.roles(activity).contains(role),
                  let id = fields["requestId"] as? String, ClubRoleRevocationRoute.requestID(id) else { return nil }
            if path == Self.receiptPath { keys.insert("expiresAtEpochMs"); guard fields["expiresAtEpochMs"] is NSNull else { return nil } }
        }
        guard Set(fields.keys) == keys else { return nil }
        self.path = path; scope = .init(clubID: club, activityID: activity)
        if path == Self.writePath {
            guard let values = try? JSONDecoder().decode([String: ClubGovernanceValue].self, from: bytes),
                  let command = try? ClubGovernanceCommand(operation: .assignRole, scope: scope, values: values.filter { !["clubId", "activityId"].contains($0.key) }),
                  command.fields == values else { return nil }
            self.command = command
        } else { command = nil }
    }
    private static func positive(_ value: Any?) -> Int? {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), let v = Int(n.stringValue), v > 0 else { return nil }; return v
    }
}
public struct ClubRoleAssignmentReceipt: Decodable, Equatable {
    public let clubId: Int, activityId: Int?, targetMemberId: Int
    public let requestId: String, roleCode: String, state: String
    public let expiresAtEpochMs: Int64?, assignmentId: Int?, version: Int?, auditId: Int?, appliedAt: Int64?
    func validate(_ entry: ClubRoleAssignmentEntry) throws {
        guard clubId == entry.clubID, activityId == entry.activityID, targetMemberId == entry.targetMemberID,
              requestId == entry.requestID, roleCode == entry.roleCode, expiresAtEpochMs == nil,
              ["UNKNOWN", "APPLIED"].contains(state), state != "APPLIED" || (version == 0 && (assignmentId ?? 0) > 0 && (auditId ?? 0) > 0 && (appliedAt ?? 0) > 0) else { throw ClubRoleAssignmentFailure.invalid }
    }
}
@MainActor public final class ClubRoleAssignmentClient {
    private let transport: any HTTPTransport
    private let current: () -> RuntimeDependencyContext?
    private let approval: (RuntimeDependencyContext) -> ClubRoleAssignmentApproval?
    private let unauthorized: (RuntimeDependencyContext) -> Void
    public init(transport: any HTTPTransport, current: @escaping () -> RuntimeDependencyContext?, approval: @escaping (RuntimeDependencyContext) -> ClubRoleAssignmentApproval?, unauthorized: @escaping (RuntimeDependencyContext) -> Void = { _ in }) {
        self.transport = transport; self.current = current; self.approval = approval; self.unauthorized = unauthorized
    }
    public func receipt(_ entry: ClubRoleAssignmentEntry, context: RuntimeDependencyContext) async throws -> ClubRoleAssignmentReceipt {
        try entry.validate(context)
        guard current() == context, let issued = approval(context), issued.permits(context, scope: entry.scope, writing: false) else { throw ClubRoleAssignmentFailure.unavailable }
        var request = URLRequest(url: context.baseURL.appendingPathComponent(ClubRoleAssignmentRoute.receiptPath)); request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.setValue(context.session.token, forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: entry.fields, options: [.sortedKeys])
        guard ClubRoleAssignmentRoute(request: request, baseURL: context.baseURL) != nil, current() == context, approval(context)?.sameReadAuthority(as: issued) == true, !Task.isCancelled else { throw ClubRoleAssignmentFailure.stale }
        let (data, status) = try await transport.send(request)
        guard current() == context, approval(context)?.sameReadAuthority(as: issued) == true, !Task.isCancelled else { throw ClubRoleAssignmentFailure.stale }
        guard data.count <= 1_048_576, let text = String(data: data, encoding: .utf8), (try? ContentDraftJSON.parse(text)) != nil else { throw ClubRoleAssignmentFailure.invalid }
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        if status == 401 || envelope.code == 401 { unauthorized(context); throw ClubRoleAssignmentFailure.forbidden }
        if status == 403 || envelope.code == 403 { throw ClubRoleAssignmentFailure.forbidden }
        guard (200..<300).contains(status), envelope.code == 200, let receipt = envelope.data else { throw ClubRoleAssignmentFailure.unknown }
        guard let raw = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let value = raw["data"] as? [String: Any], value["expiresAtEpochMs"] is NSNull else { throw ClubRoleAssignmentFailure.invalid }
        try receipt.validate(entry); return receipt
    }
    private struct Envelope: Decodable { let code: Int; let data: ClubRoleAssignmentReceipt? }
}
