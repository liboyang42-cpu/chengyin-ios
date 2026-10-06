#if DEBUG
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Deterministic test-only server bytes through the real HTTP preparation client.
@MainActor public final class ApprovedTopicReleaseSyntheticSource: ApprovedTopicReleasePreparing {
    public enum Scenario: Equatable { case ready, changedOnce, wrongTopic }
    @MainActor private final class Wire: HTTPTransport {
        let topicID: Int
        let scenario: Scenario
        let selectedCoverOwner: Int?
        var requests = 0
        init(topicID: Int, scenario: Scenario, selectedCoverOwner: Int?) { self.topicID = topicID; self.scenario = scenario; self.selectedCoverOwner = selectedCoverOwner }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            guard request.httpMethod == "POST", request.url?.path == "/api/approved-topic-release/v1/prepare",
                  let data = request.httpBody,
                  let fields = try? JSONDecoder().decode([String: ProjectEditJSON].self, from: data),
                  fields == ["topicId": .number(Decimal(topicID)), "auditTaskId": .number(3301)] else { throw APIError.invalidRequest }
            requests += 1
            if scenario == .changedOnce, requests == 1 { return (Data(#"{"code":409,"errorCode":"APPROVED_RELEASE_CHANGED"}"#.utf8), 409) }
            return (try ApprovedTopicReleaseSyntheticSource.preparationData(topicID: scenario == .wrongTopic ? topicID + 1 : topicID, selectedCoverOwner: selectedCoverOwner), 200)
        }
    }
    private let wire: Wire
    private let client: ApprovedTopicReleasePreparationClient
    public var requestCount: Int { wire.requests }
    public init(session: ProjectEditSession, topicID: Int = 7901, scenario: Scenario = .ready, selectedCoverEnabled: Bool = false, currentSession: @escaping () -> ProjectEditSession?) throws {
        let wire = Wire(topicID: topicID, scenario: scenario, selectedCoverOwner: selectedCoverEnabled ? session.accountID : nil); self.wire = wire
        let api = try APIConfiguration(baseURL: URL(string: "https://example.com")!)
        let approval = try OperationEndpointApproval(baseURL: api.baseURL, namespace: session.storageNamespace, accountID: session.accountID, paths: [ApprovedTopicReleasePaths.prepare])
        client = .init(configuration: api, approval: approval, transport: wire, currentCredentials: {
            currentSession().flatMap { try? .init(session: $0, token: "synthetic-release-read-token") }
        })
    }
    public func isCurrent(session: ProjectEditSession) -> Bool { client.isCurrent(session: session) }
    public func prepare(_ target: ApprovedTopicReleaseReadTarget, session: ProjectEditSession) async throws -> ApprovedTopicReleasePreparation {
        try await client.prepare(target, session: session)
    }
    public static func preparationData(topicID: Int = 7901, selectedCoverOwner: Int? = nil) throws -> Data {
        let node: ProjectEditJSON = .object(["id": .number(301), "templateId": .number(73), "nodeTime": .number(17),
            "name": .string("Server-captured node"), "description": .string("Frozen node description"),
            "address": .string("Server-captured address"), "longitude": .string("121.5"), "latitude": .string("31.2"), "imgUrl": .null,
            "templateTitle": .string("Synthetic captured QA"), "templateCategoryId": .number(4), "templateCategoryIds": .string("7,999"),
            "templateContentHash": .string("sha256:" + String(repeating: "b", count: 64)),
            "questionText": .string("Server-captured question?"), "ruleInstructions": .null, "answerPresent": .bool(true)])
        let body: ProjectEditJSON = .object(["contract": .string(ApprovedTopicReleasePreparation.textCityContract), "topicId": .number(Decimal(topicID)), "auditTaskId": .number(3301),
            "auditTaskVersion": .number(2), "auditSnapshotHash": .string(String(repeating: "c", count: 64)), "manifestHash": .string(String(repeating: "a", count: 64)),
            "headRevision": .number(0), "sourceConfigVersion": .number(1), "name": .string("Synthetic server-approved title"), "description": .null,
            "categoryIds": .string("7,999"), "currentlyApproved": .bool(true), "releaseAllocated": .bool(false), "secretValuesExcluded": .bool(true),
            "chapters": .array([.object(["id": .number(201), "name": .string("Server-captured chapter"), "description": .null,
                "blocks": .array([.object(["type": .string("text"), "key": .string("first"), "content": .string("Server-captured story"), "node": .null]),
                                  .object(["type": .string("node"), "key": .string("second"), "content": .null, "node": node])])])])])
        var fields = body.object ?? [:]
        if let owner = selectedCoverOwner { fields["selectedCover"] = ApprovedTopicReviewSynthetic.selectedCoverFields(owner: owner, topicID: topicID, releaseBound: true) }
        return try JSONEncoder().encode(["code": ProjectEditJSON.number(200), "data": .object(fields)])
    }
}
#endif
