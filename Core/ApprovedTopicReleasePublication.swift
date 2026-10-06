import Foundation

/// The command binds exactly the summary the author reviewed. Only `fields` is sent.
public struct ApprovedTopicReleasePublishCommand: Equatable {
    public let topicID: Int
    public let auditTaskID: Int
    public let auditTaskVersion: Int
    public let auditSnapshotHash: String
    public let expectedHeadRevision: Int
    public let expectedManifestHash: String
    public let requestID: String
    public init(prepared: ApprovedTopicReleasePreparation, requestID: UUID = UUID()) {
        topicID = prepared.topicID; auditTaskID = prepared.auditTaskID; auditTaskVersion = prepared.auditTaskVersion
        auditSnapshotHash = prepared.auditSnapshotHash; expectedHeadRevision = prepared.headRevision
        expectedManifestHash = prepared.manifestHash; self.requestID = requestID.uuidString
    }
    public var fields: [String: ProjectEditJSON] {
        ["topicId": .number(Decimal(topicID)), "auditTaskId": .number(Decimal(auditTaskID)),
         "auditTaskVersion": .number(Decimal(auditTaskVersion)), "auditSnapshotHash": .string(auditSnapshotHash),
         "expectedHeadRevision": .number(Decimal(expectedHeadRevision)), "expectedManifestHash": .string(expectedManifestHash), "requestId": .string(requestID)]
    }
    static func decode(_ value: ProjectEditJSON, prepared: ApprovedTopicReleasePreparation) throws -> Self {
        guard let fields = value.object, let id = fields["requestId"]?.text.flatMap(UUID.init(uuidString:)) else { throw ApprovedTopicReleaseError.invalidResponse }
        let expected = Self(prepared: prepared, requestID: id)
        guard fields == expected.fields else { throw ApprovedTopicReleaseError.invalidResponse }; return expected
    }
}

/// An immutable-release receipt is still distinct from current public visibility or player eligibility.
public struct ApprovedTopicReleasePublicationReceipt: Equatable {
    public let releaseID: Int
    public let topicID: Int
    public let sourceConfigVersion: Int
    public let auditTaskID: Int
    public let auditRecordID: Int
    public let auditTaskVersion: Int
    public let schemaVersion: Int
    public let manifestHash: String
    public let auditSnapshotHash: String
    public let currentlyApproved: Bool
    public static func decode(_ value: ProjectEditJSON, command: ApprovedTopicReleasePublishCommand, prepared: ApprovedTopicReleasePreparation) throws -> Self {
        guard let row = value.object, Set(row.keys) == ["releaseId", "topicId", "sourceConfigVersion", "auditTaskId", "auditRecordId", "auditTaskVersion", "schemaVersion", "manifestHash", "auditSnapshotHash", "currentlyApproved"],
              let release = row["releaseId"]?.integer, release > 0,
              row["topicId"]?.integer == command.topicID, row["sourceConfigVersion"]?.integer == prepared.sourceConfigVersion,
              row["auditTaskId"]?.integer == command.auditTaskID, let record = row["auditRecordId"]?.integer, record > 0,
              row["auditTaskVersion"]?.integer == command.auditTaskVersion, row["schemaVersion"]?.integer == 1,
              row["manifestHash"]?.text == command.expectedManifestHash,
              row["auditSnapshotHash"]?.text == command.auditSnapshotHash,
              case .bool(let approved)? = row["currentlyApproved"] else { throw ApprovedTopicReleaseError.invalidResponse }
        return .init(releaseID: release, topicID: command.topicID, sourceConfigVersion: prepared.sourceConfigVersion,
                     auditTaskID: command.auditTaskID, auditRecordID: record, auditTaskVersion: command.auditTaskVersion, schemaVersion: 1,
                     manifestHash: command.expectedManifestHash, auditSnapshotHash: command.auditSnapshotHash, currentlyApproved: approved)
    }
    var fields: ProjectEditJSON {
        .object(["releaseId": .number(Decimal(releaseID)), "topicId": .number(Decimal(topicID)), "sourceConfigVersion": .number(Decimal(sourceConfigVersion)),
                 "auditTaskId": .number(Decimal(auditTaskID)), "auditRecordId": .number(Decimal(auditRecordID)), "auditTaskVersion": .number(Decimal(auditTaskVersion)),
                 "schemaVersion": .number(Decimal(schemaVersion)), "manifestHash": .string(manifestHash), "auditSnapshotHash": .string(auditSnapshotHash), "currentlyApproved": .bool(currentlyApproved)])
    }
}

extension ApprovedTopicReleasePreparation {
    /// Local persistence of this already-decoded readable subset. No private answer/guide or bearer credential is serialized.
    var persistedFields: ProjectEditJSON {
        func text(_ value: String?) -> ProjectEditJSON { value.map(ProjectEditJSON.string) ?? .null }
        let chapterRows = chapters.map { chapter -> ProjectEditJSON in
            let blocks = chapter.blocks.map { block -> ProjectEditJSON in
                var node: ProjectEditJSON = .null
                if let n = block.node {
                    node = .object(["id": .number(Decimal(n.id)), "templateId": .number(Decimal(n.templateID)), "nodeTime": .number(Decimal(n.nodeTime)),
                        "name": text(n.name), "description": text(n.description), "address": text(n.address), "longitude": text(n.longitude), "latitude": text(n.latitude),
                        "imgUrl": text(n.imageReference), "templateTitle": text(n.templateTitle), "templateCategoryId": n.templateCategoryID.map { ProjectEditJSON.number(Decimal($0)) } ?? .null, "templateCategoryIds": text(n.templateCategoryIDs), "templateContentHash": .string(n.templateContentHash),
                        "questionText": text(n.questionText), "ruleInstructions": text(n.ruleInstructions), "answerPresent": .bool(n.answerPresent)])
                }
                return .object(["type": .string(block.isNode ? "node" : "text"), "key": text(block.key), "content": text(block.content), "node": node])
            }
            return .object(["id": .number(Decimal(chapter.id)), "name": text(chapter.name), "description": text(chapter.description), "blocks": .array(blocks)])
        }
        var fields: [String: ProjectEditJSON] = ["contract": .string(contract), "topicId": .number(Decimal(topicID)), "auditTaskId": .number(Decimal(auditTaskID)), "auditTaskVersion": .number(Decimal(auditTaskVersion)),
            "auditSnapshotHash": .string(auditSnapshotHash), "manifestHash": .string(manifestHash), "headRevision": .number(Decimal(headRevision)), "sourceConfigVersion": .number(Decimal(sourceConfigVersion)),
            "name": text(name), "description": text(description), "categoryIds": text(categoryIDs), "currentlyApproved": .bool(true), "releaseAllocated": .bool(false), "secretValuesExcluded": .bool(true), "chapters": .array(chapterRows)]
        if let selectedCover { fields["selectedCover"] = selectedCover.persistedFields }
        return .object(fields)
    }
}

/// Main-actor, compare/read/write/read journal over the existing secure-storage interface.
/// Persistence failure never authorizes transport. Unconfirmed entries cannot be removed or replaced.
@MainActor public final class ApprovedTopicReleasePublicationJournal {
    public struct Record: Equatable {
        public let command: ApprovedTopicReleasePublishCommand
        public let prepared: ApprovedTopicReleasePreparation
        public fileprivate(set) var receipt: ApprovedTopicReleasePublicationReceipt?
        var fields: ProjectEditJSON { .object(["command": .object(command.fields), "prepared": prepared.persistedFields, "receipt": receipt?.fields ?? .null]) }
    }
    public struct Snapshot: Equatable {
        public let ownerKey: String
        public let topicID: Int
        public let records: [Record]
        fileprivate let raw: Data?
        public var current: Record? { records.last }
    }
    private let storage: any ProjectEditDataStorage
    public init(storage: any ProjectEditDataStorage) { self.storage = storage }
    private func key(session: ProjectEditSession, topicID: Int) -> String {
        "approved-topic-release.v1." + Data((session.ownerKey + ":" + String(topicID)).utf8).base64EncodedString()
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
        var ids = Set<String>()
        let records = try rows.enumerated().map { index, value -> Record in
            guard let row = value.object, Set(row.keys) == ["command", "prepared", "receipt"], let fields = row["command"]?.object,
                  let task = fields["auditTaskId"]?.integer, let summary = row["prepared"], let commandValue = row["command"] else { throw ApprovedTopicReleaseError.invalidResponse }
            let prepared = try ApprovedTopicReleasePreparation.decode(summary, topicID: topicID, auditTaskID: task)
            guard prepared.selectedCover == nil || prepared.selectedCover?.ownerMemberID == session.accountID else { throw ApprovedTopicReleaseError.invalidResponse }
            let command = try ApprovedTopicReleasePublishCommand.decode(commandValue, prepared: prepared)
            guard ids.insert(command.requestID).inserted else { throw ApprovedTopicReleaseError.invalidResponse }
            let receipt: ApprovedTopicReleasePublicationReceipt?
            if row["receipt"] == .null { receipt = nil } else {
                guard let value = row["receipt"] else { throw ApprovedTopicReleaseError.invalidResponse }
                receipt = try .decode(value, command: command, prepared: prepared)
            }
            guard index == rows.count - 1 || receipt != nil else { throw ApprovedTopicReleaseError.invalidResponse }
            return .init(command: command, prepared: prepared, receipt: receipt)
        }
        for index in records.indices.dropFirst() {
            guard canFollow(records[index].prepared, prior: records[index - 1]) else { throw ApprovedTopicReleaseError.invalidResponse }
        }
        return .init(ownerKey: session.ownerKey, topicID: topicID, records: records, raw: raw)
    }
    private func replace(_ expected: Snapshot, records: [Record], session: ProjectEditSession) throws -> Snapshot {
        guard expected.ownerKey == session.ownerKey, try read(session: session, topicID: expected.topicID) == expected else { throw ApprovedTopicReleaseError.changedContext }
        let envelope: [String: ProjectEditJSON] = ["version": .number(1), "ownerKey": .string(session.ownerKey), "topicId": .number(Decimal(expected.topicID)), "records": .array(records.map(\.fields))]
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(envelope)
        guard try decode(data, session: session, topicID: expected.topicID).records == records else { throw ApprovedTopicReleaseError.invalidResponse }
        try storage.write(data, key: key(session: session, topicID: expected.topicID))
        let observed = try read(session: session, topicID: expected.topicID)
        guard observed.raw == data, observed.records == records else { throw ApprovedTopicReleaseError.persistenceUnavailable }
        return observed
    }
    private func canFollow(_ prepared: ApprovedTopicReleasePreparation, prior: Record) -> Bool {
        let changed = prepared.manifestHash != prior.command.expectedManifestHash || prepared.auditTaskID != prior.command.auditTaskID
            || prepared.auditTaskVersion != prior.command.auditTaskVersion || prepared.auditSnapshotHash != prior.command.auditSnapshotHash
        return prior.receipt != nil && changed && prepared.headRevision > prior.command.expectedHeadRevision
            && prepared.sourceConfigVersion >= prior.prepared.sourceConfigVersion
    }
    public func canBegin(_ prepared: ApprovedTopicReleasePreparation, expected: Snapshot) -> Bool {
        prepared.topicID == expected.topicID && expected.records.count < 32
            && (expected.current.map { canFollow(prepared, prior: $0) } ?? true)
    }
    /// Called synchronously after an original confirmation is claimed, before any HTTP task is started.
    public func begin(_ prepared: ApprovedTopicReleasePreparation, expected: Snapshot, session: ProjectEditSession, requestID: UUID = UUID()) throws -> Snapshot {
        guard canBegin(prepared, expected: expected) else { throw ApprovedTopicReleaseError.changedReview }
        let record = Record(command: .init(prepared: prepared, requestID: requestID), prepared: prepared, receipt: nil)
        return try replace(expected, records: expected.records + [record], session: session)
    }
    /// A matching authoritative receipt resolves only the exact persisted intent; old replies cannot resolve another entry.
    public func record(_ receipt: ApprovedTopicReleasePublicationReceipt, expected: Snapshot, session: ProjectEditSession) throws -> Snapshot {
        guard let current = expected.current else { throw ApprovedTopicReleaseError.changedReview }
        _ = try ApprovedTopicReleasePublicationReceipt.decode(receipt.fields, command: current.command, prepared: current.prepared)
        if let prior = current.receipt {
            guard prior.releaseID == receipt.releaseID, prior.auditRecordID == receipt.auditRecordID else { throw ApprovedTopicReleaseError.changedReview }
        }
        var records = expected.records; records[records.count - 1].receipt = receipt
        return try replace(expected, records: records, session: session)
    }
}
