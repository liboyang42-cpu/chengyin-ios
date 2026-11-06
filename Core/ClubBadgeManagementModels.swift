import Foundation
import CryptoKit
import CoreFoundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum ClubBadgeManagementFailure: Error {
    case unavailable, stale, invalid, forbidden, persistence, pending, unknown
    case server(String)
    public var message: String {
        switch self {
        case .unavailable: return "俱乐部勋章暂未开放，请稍后重试。"
        case .stale: return "账号或页面已变化，请重新读取。"
        case .invalid: return "勋章数据未能确认，请刷新。"
        case .forbidden: return "当前身份不能管理本俱乐部勋章。"
        case .persistence: return "未能安全保存操作记录，已暂停提交；请勿重复创建或颁发。"
        case .pending: return "还有结果未确认的操作，请先读取原操作结果。"
        case .unknown: return "结果尚未确认；不会自动再次创建或颁发。"
        case .server(let text): return text
        }
    }
}

public struct ClubBadgeRecord: Decodable, Equatable, Identifiable {
    public var id: String { badgeCode }
    public let badgeCode: String
    public let badgeName: String?
    public let badgeDesc: String?
    public let iconUrl: String?
    public let clubId: Int?
    public var displayName: String {
        let name = badgeName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "未命名勋章" : name
    }
}

public struct ClubBadgeCreateDraft: Equatable {
    public var name: String = ""
    public var description: String = ""
    public init() {}
    public var normalizedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    public var normalizedDescription: String { description.trimmingCharacters(in: .whitespacesAndNewlines) }
    public var validation: String? {
        if normalizedName.isEmpty { return "请填写勋章名。" }
        // Original Java writer truncates at 120 UTF-16 units; do not let a surrogate pair
        // be split even when the mini-program's scalar count would allow the input.
        if normalizedName.utf16.count > 120 { return "勋章名最多 120 个字（表情可能占两位）。" }
        if normalizedDescription.utf16.count > 255 { return "说明最多 255 个字（表情可能占两位）。" }
        return nil
    }
    public func fields(clubID: Int) throws -> [String: Any] {
        guard clubID > 0, validation == nil else { throw ClubBadgeManagementFailure.invalid }
        var fields: [String: Any] = ["clubId": clubID, "badgeName": normalizedName]
        if !normalizedDescription.isEmpty { fields["badgeDesc"] = normalizedDescription }
        return fields // No icon upload, unlock rule, asset type or threshold is authored here.
    }
}

/// Deployment acceptance is independent of owner/capability. No production grant is fabricated.
public struct ClubBadgeManagementApproval: Equatable {
    public let revision = UUID()
    public let endpoints: OperationEndpointApproval
    public let clubIDs: Set<Int>
    public let reviewedPolicyVersion: String
    public let reads: Bool, writes: Bool
    public init(endpoints: OperationEndpointApproval, clubIDs: Set<Int>, reviewedPolicyVersion: String,
                reads: Bool = false, writes: Bool = false) throws {
        guard !clubIDs.isEmpty, clubIDs.allSatisfy({ $0 > 0 }), !reviewedPolicyVersion.isEmpty,
              !writes || reads else { throw APIError.invalidConfiguration }
        self.endpoints = endpoints; self.clubIDs = clubIDs; self.reviewedPolicyVersion = reviewedPolicyVersion
        self.reads = reads; self.writes = writes
    }
    public func permits(_ context: RuntimeDependencyContext, clubID: Int, writing: Bool) -> Bool {
        let paths = writing ? ClubBadgeManagementRoute.paths : ClubBadgeManagementRoute.readPaths
        return context.market == .china && reads && (!writing || writes) && clubIDs.contains(clubID)
            && context.baseURL == endpoints.baseURL && context.session.accountID == endpoints.accountID
            && context.session.namespace == endpoints.namespace && paths.isSubset(of: endpoints.paths)
    }
    public func sameReadAuthority(as other: Self) -> Bool {
        revision == other.revision && endpoints == other.endpoints && clubIDs == other.clubIDs && reviewedPolicyVersion == other.reviewedPolicyVersion && reads == other.reads
    }
}

/// Optional first-party envelope around the ORIGINAL writer. Without its deployed producer,
/// the legacy create API has NO UUID receipt contract. A local UUID alone never proves success.
public struct ClubBadgeManagementRoute {
    public static let detailPath = "api/club/detail", membersPath = "api/club/members"
    public static let listPath = "api/club/badge/list", createPath = "api/club/badge/create", grantPath = "api/club/badge/grant"
    public static let receiptPath = "api/club/badge/original-receipt"
    public static let requestHeader = "X-Club-Badge-Request-Id", sourceHeader = "X-Club-Badge-Source-SHA256"
    public static let readPaths: Set<String> = [detailPath, membersPath, listPath, receiptPath]
    public static let paths = readPaths.union([createPath, grantPath])
    public let path: String, clubID: Int
    public var writing: Bool { path == Self.createPath || path == Self.grantPath }
    public init?(request: URLRequest, baseURL: URL) {
        guard request.httpMethod == "POST", request.httpBodyStream == nil,
              request.value(forHTTPHeaderField: "Content-Type") == "application/json",
              let path = Self.paths.first(where: { baseURL.appendingPathComponent($0) == request.url }),
              let data = request.httpBody, data.count < 16_384, let text = String(data: data, encoding: .utf8),
              (try? ContentDraftJSON.parse(text)) != nil,
              let fields = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let club = Self.positive(fields[(path == Self.detailPath || path == Self.listPath) ? "id" : "clubId"]) else { return nil }
        let requestID = request.value(forHTTPHeaderField: Self.requestHeader), source = request.value(forHTTPHeaderField: Self.sourceHeader)
        if path == Self.createPath || path == Self.grantPath {
            guard let requestID, Self.requestID(requestID), let source, Self.hash(source),
                  (try? Self.sourceHash(operation: path == Self.createPath ? "CREATE" : "GRANT", fields: fields)) == source else { return nil }
        } else {
            guard requestID == nil, source == nil else { return nil }
            if path == Self.receiptPath {
                guard Set(fields.keys) == ["clubId", "requestId", "operation", "sourceSHA256"],
                      let id = fields["requestId"] as? String, Self.requestID(id),
                      let op = fields["operation"] as? String, ["CREATE", "GRANT"].contains(op),
                      let hash = fields["sourceSHA256"] as? String, Self.hash(hash) else { return nil }
            } else {
                guard Set(fields.keys) == [(path == Self.detailPath || path == Self.listPath) ? "id" : "clubId"] else { return nil }
            }
        }
        self.path = path; clubID = club
    }
    public static func sourceHash(operation: String, fields: [String: Any]) throws -> String {
        guard let club = positive(fields["clubId"]) else { throw ClubBadgeManagementFailure.invalid }
        var pieces = ["CLUB_BADGE_V1", operation, String(club)]
        if operation == "CREATE" {
            let keys: Set<String> = fields["badgeDesc"] == nil ? ["clubId", "badgeName"] : ["clubId", "badgeName", "badgeDesc"]
            guard Set(fields.keys) == keys, let name = fields["badgeName"] as? String,
                  !name.isEmpty, name.utf16.count <= 120, name == name.trimmingCharacters(in: .whitespacesAndNewlines),
                  fields["badgeDesc"] == nil || fields["badgeDesc"] is String else { throw ClubBadgeManagementFailure.invalid }
            let desc = fields["badgeDesc"] as? String ?? ""
            guard desc.utf16.count <= 255, desc == desc.trimmingCharacters(in: .whitespacesAndNewlines) else { throw ClubBadgeManagementFailure.invalid }
            pieces += [digest(name), digest(desc)]
        } else if operation == "GRANT" {
            guard Set(fields.keys) == ["clubId", "memberId", "badgeCode"], let member = positive(fields["memberId"]),
                  let code = fields["badgeCode"] as? String, validCode(code) else { throw ClubBadgeManagementFailure.invalid }
            pieces += [String(member), digest(code)]
        } else { throw ClubBadgeManagementFailure.invalid }
        return digest(pieces.joined(separator: "\u{001f}"))
    }
    public static func digest(_ value: String) -> String { SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined() }
    public static func requestID(_ value: String) -> Bool { UUID(uuidString: value)?.uuidString.lowercased() == value }
    public static func hash(_ value: String) -> Bool { value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) } }
    public static func validCode(_ value: String) -> Bool { !value.isEmpty && value.utf8.count <= 255 && value == value.trimmingCharacters(in: .whitespacesAndNewlines) && !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) }
    static func positive(_ value: Any?) -> Int? {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), let result = Int(n.stringValue), result > 0 else { return nil }; return result
    }
}

public struct ClubBadgeOriginalReceipt: Codable, Equatable, Identifiable {
    public var id: String { requestId }
    public let protocolVersion: Int, clubId: Int, actorMemberId: Int
    public let requestId: String, operation: String, sourceSHA256: String, state: String
    public let badgeId: Int?, badgeCode: String?, memberId: Int?, appliedAt: Int64?, auditId: Int?
    public var isTerminal: Bool { ["CREATED", "GRANTED", "ALREADY_GRANTED"].contains(state) }
    public var message: String {
        switch state {
        case "CREATED": return "勋章已创建。"
        case "GRANTED": return "这枚勋章已经记在对方名下。"
        case "ALREADY_GRANTED": return "对方之前已经拿到这枚勋章，这次没有重复颁发。"
        default: return "原操作结果尚未确认；不会自动重复提交。"
        }
    }
    func validate(_ entry: ClubBadgeManagementEntry) throws {
        guard protocolVersion == 1, clubId == entry.clubID, actorMemberId == entry.accountID,
              requestId == entry.requestID, operation == entry.operation, sourceSHA256 == entry.sourceSHA256 else { throw ClubBadgeManagementFailure.invalid }
        if state == "UNKNOWN" {
            guard badgeId == nil, badgeCode == nil, memberId == nil, appliedAt == nil, auditId == nil else { throw ClubBadgeManagementFailure.invalid }
        } else {
            guard isTerminal, let code = badgeCode, ClubBadgeManagementRoute.validCode(code),
                  (badgeId ?? 0) > 0, (appliedAt ?? 0) > 0, (auditId ?? 0) > 0 else { throw ClubBadgeManagementFailure.invalid }
            if operation == "CREATE" {
                guard state == "CREATED", memberId == nil else { throw ClubBadgeManagementFailure.invalid }
            } else {
                guard ["GRANTED", "ALREADY_GRANTED"].contains(state), code == entry.badgeCode,
                      memberId == entry.memberID, (memberId ?? 0) > 0 else { throw ClubBadgeManagementFailure.invalid }
            }
        }
    }
}
