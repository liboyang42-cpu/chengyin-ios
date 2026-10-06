#if DEBUG
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Explicitly test-only server bytes through the real client. No network, audit approval, media upload or release is performed.
@MainActor public final class ApprovedTopicReviewSynthetic: ApprovedTopicReviewServing, ApprovedTopicReviewObserving {
    public enum Scenario: Equatable { case ready, unknownOnce }
    public static func captureFields(topicID: Int = 7901, observedAuditTaskID: Int = 3301) -> ProjectEditJSON {
        let node: ProjectEditJSON = .object(["id": .number(301), "templateId": .number(73), "nodeTime": .number(17), "templateCategoryId": .number(4),
            "name": .string("Test-only captured node"), "description": .string("  e\u{301}\n"), "address": .string("Test-only captured address"), "longitude": .string("121.5"), "latitude": .string("31.2"),
            "imageReference": .null, "templateTitle": .string("Test-only QA"), "templateCategoryIds": .string("7,999"), "templateContentHash": .string("sha256:" + String(repeating: "b", count: 64)),
            "questionText": .string("Test-only captured question?"), "ruleInstructions": .null, "answerPresent": .bool(true)])
        let chapter: ProjectEditJSON = .object(["id": .number(201), "name": .string("Test-only captured chapter"), "description": .null,
            "blocks": .array([.object(["type": .string("text"), "key": .string("story"), "content": .string("Test-only captured story"), "node": .null]),
                              .object(["type": .string("node"), "key": .string("node"), "content": .null, "node": node])])])
        return .object(["contract": .string("questify.topic-release.review-preparation.v1"), "topicId": .number(Decimal(topicID)), "observedAuditTaskId": .number(Decimal(observedAuditTaskID)),
            "observedAuditTaskVersion": .number(0), "sourceConfigVersion": .number(1), "snapshotHash": .string(String(repeating: "c", count: 64)), "approvalProof": .bool(false), "releaseAllocated": .bool(false),
            "summary": .object(["name": .string("Test-only current review capture"), "description": .null, "categoryIds": .string("7,999"), "coverReference": .string("fixture://review-cover/reference-only"),
                "productType": .number(1), "publishMode": .string("pro"), "secretValuesExcluded": .bool(true), "publicationEligibilityChecked": .bool(false), "chapters": .array([chapter])])])
    }
    public static func selectedCoverFields(owner: Int, topicID: Int = 7901, releaseBound: Bool = false) -> ProjectEditJSON {
        let id = "11111111-1111-4111-8111-111111111111", version = "22222222-2222-4222-8222-222222222222", hash = String(repeating: "a", count: 64)
        var fields: [String: ProjectEditJSON] = ["kind": .string("OWNED_TOPIC_COVER_REVIEW_INPUT_V1"), "schemaVersion": .number(1), "topicId": .number(Decimal(topicID)), "topicConfigVersion": .number(1), "selectionVersion": .number(9), "contentSlotId": .number(51),
            "assetReference": .object(["kind": .string("OWNED_TOPIC_COVER_V1"), "id": .string(id), "assetId": .string(id), "sourceVersion": .string(version), "contentHash": .string(hash), "owner": .number(Decimal(owner)), "ownerMemberId": .number(Decimal(owner)), "policyVersion": .string("OWNED_TOPIC_COVER_V1")]),
            "authorDisplayReference": .object(["kind": .string("OWNED_TOPIC_COVER_AUTHENTICATED_CONTENT_V1"), "audience": .string("AUTHOR_ONLY"), "path": .string("/api/topic/cover/\(id)/content?sourceVersion=\(version)&contentHash=\(hash)"), "contentHash": .string(hash)]),
            "legacyTopicImageReference": .string("fixture://review-cover/reference-only"), "bindingState": .string("AUTHOR_PREVIEW_ONLY"), "legacyImageBindingVerified": .bool(false), "publicPlayerReadable": .bool(false), "approvalProof": .bool(false)]
        if releaseBound {
            fields["bindingState"] = .string("REPLACE_LEGACY_IMAGE_IN_W02_RELEASE")
            fields["playerReadContract"] = .string("PLAYER_PINNED_RUN_ONLY")
        }
        return .object(fields)
    }
    public static func receiptFields(command: [String: ProjectEditJSON], taskID: Int = 4402) -> ProjectEditJSON {
        .object(["topicId": command["topicId"] ?? .null, "auditTaskId": .number(Decimal(taskID)), "sourceConfigVersion": command["sourceConfigVersion"] ?? .null,
            "submittedTaskVersion": .number(0), "submittedTaskStatus": .number(0), "snapshotHash": command["snapshotHash"] ?? .null, "requestId": command["requestId"] ?? .null,
            "approvalProof": .bool(false), "releaseAllocated": .bool(false)])
    }
    public static func observationFields(receipt: ProjectEditJSON, status: ApprovedTopicReviewObservation.Status = .pending, changedCapture: Bool = false) -> ProjectEditJSON {
        let row = receipt.object ?? [:]
        return .object(["contract": .string("questify.topic-release.review-observation.v1"), "topicId": row["topicId"] ?? .null, "auditTaskId": row["auditTaskId"] ?? .null,
            "requestId": row["requestId"] ?? .null, "submittedTaskVersion": row["submittedTaskVersion"] ?? .null,
            "observedTaskVersion": .number(Decimal((row["submittedTaskVersion"]?.integer ?? 0) + (status == .pending ? 0 : 1))), "observedTaskStatus": .number(Decimal(status.rawValue)),
            "submittedSnapshotHash": row["snapshotHash"] ?? .null, "observedSnapshotHash": changedCapture ? .string(String(repeating: "d", count: 64)) : (row["snapshotHash"] ?? .null),
            "matchesSubmittedCapture": .bool(!changedCapture), "approvalProof": .bool(false), "releaseAllocated": .bool(false)])
    }
    @MainActor private final class Wire: HTTPTransport {
        let scenario: Scenario
        let selectedCoverOwner: Int?
        let selectedCoverReleaseBound: Bool
        var requests: [URLRequest] = []
        var stored: [String: ([String: ProjectEditJSON], ProjectEditJSON)] = [:]
        var unknownSent = false
        var observedStatus = ApprovedTopicReviewObservation.Status.pending
        var beforeReceipt: (() -> Void)?
        var selectedCoverInput: (() -> ProjectEditJSON?)?
        init(scenario: Scenario, selectedCoverOwner: Int?, selectedCoverReleaseBound: Bool, beforeReceipt: (() -> Void)?) { self.scenario = scenario; self.selectedCoverOwner = selectedCoverOwner; self.selectedCoverReleaseBound = selectedCoverReleaseBound; self.beforeReceipt = beforeReceipt }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            guard request.httpMethod == "POST", let path = request.url?.path, let bytes = request.httpBody,
                  let body = try? JSONDecoder().decode([String: ProjectEditJSON].self, from: bytes) else { throw APIError.invalidRequest }
            requests.append(request)
            if path == "/" + ApprovedTopicReviewPath.prepare {
                guard Set(body.keys) == ["topicId", "observedAuditTaskId"], let topic = body["topicId"]?.integer, let task = body["observedAuditTaskId"]?.integer else { throw APIError.invalidRequest }
                var capture = ApprovedTopicReviewSynthetic.captureFields(topicID: topic, observedAuditTaskID: task).object ?? [:]
                if let owner = selectedCoverOwner, var summary = capture["summary"]?.object {
                    summary["selectedCover"] = ApprovedTopicReviewSynthetic.selectedCoverFields(owner: owner, topicID: topic, releaseBound: selectedCoverReleaseBound); capture["summary"] = .object(summary)
                }
                if let input = selectedCoverInput?(), var summary = capture["summary"]?.object {
                    summary["selectedCover"] = input; capture["summary"] = .object(summary)
                    capture["sourceConfigVersion"] = input.object?["topicConfigVersion"]
                }
                return try response(.object(capture))
            }
            guard path == "/" + ApprovedTopicReviewPath.submit || path == "/" + ApprovedTopicReviewPath.status || path == "/" + ApprovedTopicReviewPath.current,
                  Set(body.keys) == ["topicId", "observedAuditTaskId", "observedAuditTaskVersion", "sourceConfigVersion", "snapshotHash", "requestId"],
                  let id = body["requestId"]?.text, UUID(uuidString: id)?.uuidString == id else { throw APIError.invalidRequest }
            if let prior = stored[id] {
                guard prior.0 == body else { return try response(nil, status: 409) }
                if path == "/" + ApprovedTopicReviewPath.current { return try response(ApprovedTopicReviewSynthetic.observationFields(receipt: prior.1, status: observedStatus)) }
                return try response(prior.1)
            }
            guard path == "/" + ApprovedTopicReviewPath.submit else { return try response(nil, status: 409) }
            let receipt = ApprovedTopicReviewSynthetic.receiptFields(command: body, taskID: 4402 + stored.count); stored[id] = (body, receipt)
            if scenario == .unknownOnce, !unknownSent { unknownSent = true; return try response(nil, status: 503) }
            beforeReceipt?(); beforeReceipt = nil; return try response(receipt)
        }
        private func response(_ value: ProjectEditJSON?, status: Int = 200) throws -> (Data, Int) {
            var fields: [String: ProjectEditJSON] = ["code": .number(Decimal(status))]; if let value { fields["data"] = value }; return (try JSONEncoder().encode(fields), status)
        }
    }
    private let wire: Wire
    private let client: ApprovedTopicReviewClient
    public var prepareCount: Int { wire.requests.filter { $0.url?.path == "/" + ApprovedTopicReviewPath.prepare }.count }
    public var submitCount: Int { wire.requests.filter { $0.url?.path == "/" + ApprovedTopicReviewPath.submit }.count }
    public var statusCount: Int { wire.requests.filter { $0.url?.path == "/" + ApprovedTopicReviewPath.status }.count }
    public var observationCount: Int { wire.requests.filter { $0.url?.path == "/" + ApprovedTopicReviewPath.current }.count }
    public func simulateObservedStatus(_ status: ApprovedTopicReviewObservation.Status) { wire.observedStatus = status }
    public var taskCount: Int { wire.stored.count }
    public var requestIDs: [String] { wire.requests.compactMap { request in
        guard let bytes = request.httpBody, let body = try? JSONDecoder().decode([String: ProjectEditJSON].self, from: bytes) else { return nil }; return body["requestId"]?.text
    } }
    public init(session: ProjectEditSession, scenario: Scenario = .ready, observationEnabled: Bool = false, selectedCoverEnabled: Bool = false, selectedCoverReleaseBound: Bool = false, beforeReceipt: (() -> Void)? = nil, selectedCoverInput: (() -> ProjectEditJSON?)? = nil, currentSession: @escaping () -> ProjectEditSession?) throws {
        let wire = Wire(scenario: scenario, selectedCoverOwner: selectedCoverEnabled ? session.accountID : nil, selectedCoverReleaseBound: selectedCoverReleaseBound, beforeReceipt: beforeReceipt); self.wire = wire; wire.selectedCoverInput = selectedCoverInput
        let configuration = try APIConfiguration(baseURL: URL(string: "https://example.com")!)
        var paths: Set<String> = [ApprovedTopicReviewPath.prepare, ApprovedTopicReviewPath.submit, ApprovedTopicReviewPath.status]
        if observationEnabled { paths.insert(ApprovedTopicReviewPath.current) }
        let approval = try OperationEndpointApproval(baseURL: configuration.baseURL, namespace: session.storageNamespace, accountID: session.accountID, paths: paths)
        client = .init(configuration: configuration, approval: approval, transport: wire,
            currentCredentials: { currentSession().flatMap { try? .init(session: $0, token: "synthetic-review-token") } })
    }
    public func isCurrent(session: ProjectEditSession) -> Bool { client.isCurrent(session: session) }
    public func canPrepare(session: ProjectEditSession) -> Bool { client.canPrepare(session: session) }
    public func canSubmit(session: ProjectEditSession) -> Bool { client.canSubmit(session: session) }
    public func canReadStatus(session: ProjectEditSession) -> Bool { client.canReadStatus(session: session) }
    public func canObserve(session: ProjectEditSession) -> Bool { client.canObserve(session: session) }
    public func observe(_ record: ApprovedTopicReviewJournal.Record, session: ProjectEditSession) async throws -> ApprovedTopicReviewObservation { try await client.observe(record, session: session) }
    public func prepare(_ origin: ApprovedTopicReleaseReadTarget, session: ProjectEditSession) async throws -> ApprovedTopicReviewCapture { try await client.prepare(origin, session: session) }
    public func submit(_ record: ApprovedTopicReviewJournal.Record, session: ProjectEditSession) async throws -> ApprovedTopicReviewReceipt { try await client.submit(record, session: session) }
    public func status(_ record: ApprovedTopicReviewJournal.Record, session: ProjectEditSession) async throws -> ApprovedTopicReviewReceipt { try await client.status(record, session: session) }
}
#endif
