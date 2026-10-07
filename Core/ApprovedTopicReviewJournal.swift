import Foundation

/// Editor-local exact review intentions. A submission acknowledgment never replaces the original V2 receipt.
@MainActor public final class ApprovedTopicReviewJournal {
    public struct Record: Equatable, Sendable {
        public let ownerKey: String
        public let originOperationID: UUID
        public let command: ApprovedTopicReviewCommand
        public let capture: ApprovedTopicReviewCapture
        public fileprivate(set) var receipt: ApprovedTopicReviewReceipt?
        func serializedFields() throws -> ProjectEditJSON {
            try .object(["originOperationId": .string(originOperationID.uuidString), "command": .object(command.fields), "capture": capture.serializedFields(), "receipt": receipt?.fields ?? .null])
        }
    }
    public struct Snapshot: Equatable, Sendable {
        public let ownerKey: String, topicID: Int
        public let records: [Record]
        fileprivate let raw: Data?
        public var current: Record? { records.last }
        public func receipt(for origin: ApprovedTopicReleaseReadTarget) -> ApprovedTopicReviewReceipt? {
            guard ownerKey == origin.ownerKey, topicID == origin.topicID,
                  let row = current, row.originOperationID == origin.operationID, row.command.observedAuditTaskID == origin.auditTaskID else { return nil }
            return row.receipt
        }
    }
    private let storage: any ProjectEditDataStorage
    public init(storage: any ProjectEditDataStorage) { self.storage = storage }
    private func key(session: ProjectEditSession, topicID: Int) -> String {
        "approved-topic-review.v1." + Data((session.ownerKey + ":" + String(topicID)).utf8).base64EncodedString()
    }
    public func read(session: ProjectEditSession, topicID: Int) throws -> Snapshot {
        guard topicID > 0 else { throw ApprovedTopicReleaseError.invalidResponse }
        let raw = try storage.read(key(session: session, topicID: topicID))
        guard let raw else { return .init(ownerKey: session.ownerKey, topicID: topicID, records: [], raw: nil) }
        return try decode(raw, session: session, topicID: topicID)
    }
    private func decode(_ raw: Data, session: ProjectEditSession, topicID: Int) throws -> Snapshot {
        let root = try ApprovedTopicReleaseWire.envelope(raw)
        guard Set(root.keys) == ["version", "ownerKey", "topicId", "records"], root["version"]?.integer == 1,
              root["ownerKey"]?.text == session.ownerKey, root["topicId"]?.integer == topicID,
              let rows = root["records"]?.array, !rows.isEmpty, rows.count <= 32 else { throw ApprovedTopicReleaseError.invalidResponse }
        var requestIDs = Set<String>(), origins = Set<UUID>()
        let records = try rows.enumerated().map { index, value -> Record in
            guard let row = value.object, Set(row.keys) == ["originOperationId", "command", "capture", "receipt"],
                  let operationText = row["originOperationId"]?.text, let operation = UUID(uuidString: operationText), operation.uuidString == operationText,
                  origins.insert(operation).inserted, let commandValue = row["command"], let commandFields = commandValue.object,
                  let task = commandFields["observedAuditTaskId"]?.integer, task > 0, let captured = row["capture"] else { throw ApprovedTopicReleaseError.invalidResponse }
            let capture = try ApprovedTopicReviewCapture.decode(captured, topicID: topicID, observedAuditTaskID: task)
            guard capture.selectedCover == nil || capture.selectedCover?.ownerMemberID == session.accountID else { throw ApprovedTopicReleaseError.invalidResponse }
            let command = try ApprovedTopicReviewCommand.decode(commandValue, capture: capture)
            guard requestIDs.insert(command.requestID).inserted else { throw ApprovedTopicReleaseError.invalidResponse }
            let receipt: ApprovedTopicReviewReceipt?
            if row["receipt"] == .null { receipt = nil }
            else { guard let value = row["receipt"] else { throw ApprovedTopicReleaseError.invalidResponse }; receipt = try .decode(value, command: command) }
            guard index == rows.count - 1 || receipt != nil else { throw ApprovedTopicReleaseError.invalidResponse }
            return .init(ownerKey: session.ownerKey, originOperationID: operation, command: command, capture: capture, receipt: receipt)
        }
        return .init(ownerKey: session.ownerKey, topicID: topicID, records: records, raw: raw)
    }
    private func replace(_ expected: Snapshot, records: [Record], session: ProjectEditSession) throws -> Snapshot {
        guard expected.ownerKey == session.ownerKey, try read(session: session, topicID: expected.topicID) == expected else { throw ApprovedTopicReleaseError.changedContext }
        let value: [String: ProjectEditJSON] = ["version": .number(1), "ownerKey": .string(session.ownerKey), "topicId": .number(Decimal(expected.topicID)), "records": .array(try records.map { try $0.serializedFields() })]
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; let data = try encoder.encode(value)
        guard try decode(data, session: session, topicID: expected.topicID).records == records else { throw ApprovedTopicReleaseError.invalidResponse }
        try storage.write(data, key: key(session: session, topicID: expected.topicID))
        let observed = try read(session: session, topicID: expected.topicID)
        guard observed.raw == data, observed.records == records else { throw ApprovedTopicReleaseError.persistenceUnavailable }; return observed
    }
    /// One explicit review request per acknowledged edit operation. A later edit/resubmit has a new origin; unresolved old requests cannot be displaced.
    public func canBegin(_ capture: ApprovedTopicReviewCapture, origin: ApprovedTopicReleaseReadTarget, expected: Snapshot) -> Bool {
        do { try ApprovedTopicReviewRequestBody.preflight(.init(capture: capture), capture: capture) } catch { return false }
        return capture.coverBindingAllowsReview && expected.ownerKey == origin.ownerKey && expected.topicID == origin.topicID && capture.topicID == origin.topicID && capture.observedAuditTaskID == origin.auditTaskID
            && expected.records.count < 32 && !expected.records.contains(where: { $0.originOperationID == origin.operationID })
            && (expected.current == nil || expected.current?.receipt != nil)
    }
    public func begin(_ capture: ApprovedTopicReviewCapture, origin: ApprovedTopicReleaseReadTarget, expected: Snapshot, session: ProjectEditSession, requestID: UUID = UUID()) throws -> Snapshot {
        guard canBegin(capture, origin: origin, expected: expected) else { throw ApprovedTopicReleaseError.changedReview }
        let command = ApprovedTopicReviewCommand(capture: capture, requestID: requestID)
        try ApprovedTopicReviewRequestBody.preflight(command, capture: capture)
        let record = Record(ownerKey: session.ownerKey, originOperationID: origin.operationID, command: command, capture: capture, receipt: nil)
        return try replace(expected, records: expected.records + [record], session: session)
    }
    public func record(_ receipt: ApprovedTopicReviewReceipt, expected: Snapshot, session: ProjectEditSession) throws -> Snapshot {
        guard let current = expected.current else { throw ApprovedTopicReleaseError.changedReview }
        _ = try ApprovedTopicReviewReceipt.decode(receipt.fields, command: current.command)
        if let prior = current.receipt { guard prior == receipt else { throw ApprovedTopicReleaseError.changedReview } }
        var records = expected.records; records[records.count - 1].receipt = receipt
        return try replace(expected, records: records, session: session)
    }
}
