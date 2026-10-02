#if DEBUG
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Fabricated offline protocol examples; not a deployed-policy or live-case claim.
public enum SquareReportFixtures {
    public static func policy(version: String = "SYNTHETIC_POLICY_V1") -> SquareGovernanceJSON {
        let rows: [(String, String)] = [("DANGEROUS", "现实人身危险或违法行为"), ("MINOR_SAFETY", "未成年人安全"), ("SELF_HARM", "自伤或自杀风险"), ("SEXUAL_CONTENT", "色情低俗内容"), ("HARASSMENT", "人身攻击或骚扰"), ("HATE", "仇恨或歧视"), ("FRAUD", "诈骗"), ("IMPERSONATION", "冒充他人"), ("FALSE_INFORMATION", "虚假信息"), ("SPAM", "垃圾广告或站外导流"), ("PRIVACY", "隐私泄露"), ("INTELLECTUAL_PROPERTY", "知识产权或内容盗用"), ("OTHER", "其他")]
        return .object(["policyVersion": .string(version), "targetTypes": .array([.string("CONTENT"), .string("COMMENT")]),
            "reasonCodes": .array(rows.map { .string($0.0) }), "anonymityPolicy": .string("SUBJECT_HIDDEN"),
            "emergencyGuidanceCode": .string("CONTACT_LOCAL_EMERGENCY_SERVICES"),
            "reasons": .array(rows.enumerated().map { index, row in .object(["code": .string(row.0), "label": .string(row.1),
                "priority": .string(index < 3 ? "URGENT" : "STANDARD"), "firstResponseMinutes": .integer(index < 3 ? 15 : 1440), "emergency": .bool(index < 3)]) })])
    }
    public static func postData(id: Int = 701, version: Int = 3) -> Data {
        Data("{\"post\":{\"id\":\(id),\"authorId\":81,\"version\":\(version),\"lifecycle\":\"PUBLISHED\",\"body\":\"Synthetic versioned community post\",\"authorNickname\":\"Example walker\",\"audience\":\"PUBLIC\",\"commentPolicy\":\"EVERYONE\"},\"viewerCanComment\":true,\"media\":[],\"references\":[]}".utf8)
    }
    public static func post(id: Int = 701, version: Int = 3) throws -> SquarePost {
        try JSONDecoder().decode(SquarePost.self, from: postData(id: id, version: version)).qualified(as: .communityV1)
    }
    public static func comments(postID: Int = 701) throws -> [SquareComment] {
        let data = Data("[{\"id\":802,\"post_id\":\(postID),\"author_id\":82,\"version\":2,\"body\":\"Synthetic community comment\",\"lifecycle\":\"PUBLISHED\",\"author_approval_state\":\"VISIBLE\",\"parent_id\":null,\"author_nickname\":\"Example explorer\"}]".utf8)
        return try JSONDecoder().decode([SquareComment].self, from: data).map { $0.qualified(as: .communityV1) }
    }
}

public final class SquareReportFixtureTransport: SquareReportOfflineTransport {
    public var scenario: String
    public private(set) var requests: [URLRequest] = []
    public var policyReads = 0
    public var onRequest: ((URLRequest) async throws -> Void)?
    private var submitted: SquareGovernanceJSON?
    public init(scenario: String = "content") { self.scenario = scenario }
    public func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); try await onRequest?(request)
        let value: SquareGovernanceJSON
        let path = request.url?.path ?? ""
        if path.hasSuffix("/capabilities") {
            policyReads += 1
            value = .object(["reporting": SquareReportFixtures.policy(version: scenario == "reportPolicyChanged" && policyReads > 1 ? "SYNTHETIC_POLICY_V2" : "SYNTHETIC_POLICY_V1")])
        } else if path.hasSuffix("/community/reports") && request.httpMethod == "POST" {
            if scenario == "reportUnknown" { throw URLError(.timedOut) }
            guard let body = request.httpBody, case .object(var fields) = try JSONDecoder().decode(SquareGovernanceJSON.self, from: body) else { throw SquareReportFailure.invalid }
            fields["id"] = .integer(9901); fields["stage"] = .string("SUBMITTED"); fields["version"] = .integer(0)
            value = .object(fields); submitted = value
        } else if path.hasSuffix("/community-trust/reports/9901"), case .object(var fields)? = submitted {
            fields["stage"] = .string("INVESTIGATING"); fields["publicStage"] = .string("IN_REVIEW"); value = .object(fields)
        } else { throw SquareReportFailure.invalid }
        return (try JSONEncoder().encode(SquareGovernanceJSON.object(["code": .integer(200), "data": value])), 200)
    }
}
#endif
