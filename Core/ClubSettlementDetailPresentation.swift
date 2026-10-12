import Foundation

public enum ClubSettlementDisplayStatus: String, Equatable {
    case pending, credited, unverified, void
    public var localizationKey: String { "club.settlementDetail.status." + rawValue }
}
public struct ClubSettlementDetailRecord: Identifiable, Equatable {
    public let id: Int
    public let topicID: Int
    public let name: String
    /// All monetary and timeline text is supplied by the server, never calculated here.
    public let amountText: String?
    public let status: ClubSettlementDisplayStatus
    public let originalAmountText: String
    public let executedAdjustmentText: String
    public let netAmountText: String
    public let arrivedText: String
    public let paidText: String
    public var amountLabelKey: String {
        switch status {
        case .pending: return "club.settlementDetail.amount.pending"
        case .void: return "club.settlementDetail.amount.void"
        case .credited, .unverified: return "club.settlementDetail.amount.credited"
        }
    }
}
public struct ClubSettlementDetailPresentation: Equatable {
    public let scope: ClubGovernanceScope
    public let records: [ClubSettlementDetailRecord]
    private let context: ClubGovernanceReadContext
    public init(snapshot: ClubGovernanceSnapshot, context: ClubGovernanceReadContext) throws {
        try context.scope.validate()
        guard context.operation == .settlement, context.accepts(snapshot), (context.scope.clubID ?? 0) > 0,
              context.identity?.isSignedIn == true else { throw ClubGovernanceFailure.targetChanged }
        guard snapshot.permissions?.allows(ClubGovernanceRead.settlement.permission, scope: context.scope) == true else { throw ClubGovernanceFailure.forbidden }
        let value = try ClubGovernanceValidation.validate(snapshot.value, operation: .settlement, scope: context.scope)
        if value["clubId"] != .null, value["clubId"].int != context.scope.clubID { throw ClubGovernanceFailure.targetChanged }
        guard let rows = value["topics"].array else { throw ClubGovernanceFailure.malformed }
        records = try rows.map { row in
            if row["clubId"] != .null, row["clubId"].int != context.scope.clubID { throw ClubGovernanceFailure.targetChanged }
            guard let id = row["id"].int, let topicID = row["topicId"].int,
                  let name = row["name"].string, let original = row["originalAmountText"].string,
                  let adjustment = row["executedAdjustmentText"].string, let net = row["netAmountText"].string,
                  let arrived = row["arrivedText"].string, let paid = row["paidText"].string else { throw ClubGovernanceFailure.malformed }
            let status: ClubSettlementDisplayStatus
            switch row["status"].string {
            case "pending": status = .pending
            case "void": status = .void
            case "settled": status = row["amountStatus"] == .string("unverified") ? .unverified : .credited
            default: throw ClubGovernanceFailure.malformed
            }
            return .init(id: id, topicID: topicID, name: name, amountText: row["amountText"].string, status: status,
                         originalAmountText: original, executedAdjustmentText: adjustment, netAmountText: net,
                         arrivedText: arrived, paidText: paid)
        }
        scope = context.scope; self.context = context
    }
    public func target(recordID: Int, context: ClubGovernanceReadContext, snapshotGeneration: UInt64, namespace: String) -> ClubSettlementDetailTarget? {
        guard self.context == context, let record = records.first(where: { $0.id == recordID }) else { return nil }
        return .init(record: record, context: context, snapshotGeneration: snapshotGeneration, namespace: namespace)
    }
    /// Re-read by exact settlement row ID; topic ID verifies the selected row's identity.
    public func record(for target: ClubSettlementDetailTarget) throws -> ClubSettlementDetailRecord? {
        guard scope == target.readScope, target.acceptsReadContext(context) else { throw ClubGovernanceFailure.targetChanged }
        guard let record = records.first(where: { $0.id == target.recordID }) else { return nil }
        guard record.topicID == target.topicID else { throw ClubGovernanceFailure.targetChanged }
        return record
    }
}
public struct ClubSettlementDetailTarget: Identifiable, Equatable {
    public let id = UUID()
    public let recordID: Int
    public let topicID: Int
    public let readScope: ClubGovernanceScope
    private let record: ClubSettlementDetailRecord
    private let context: ClubGovernanceReadContext
    private let snapshotGeneration: UInt64
    private let namespace: String
    fileprivate init(record: ClubSettlementDetailRecord, context: ClubGovernanceReadContext, snapshotGeneration: UInt64, namespace: String) {
        recordID = record.id; topicID = record.topicID; readScope = context.scope
        self.record = record; self.context = context; self.snapshotGeneration = snapshotGeneration; self.namespace = namespace
    }
    fileprivate func acceptsReadContext(_ other: ClubGovernanceReadContext) -> Bool {
        context.operation == other.operation && context.scope == other.scope && context.identity == other.identity &&
        context.authorizationGeneration == other.authorizationGeneration && context.accessIdentity == other.accessIdentity
    }
    public func acceptsRead(context: ClubGovernanceReadContext, namespace: String) -> Bool {
        acceptsReadContext(context) && self.namespace == namespace
    }
    public func isCurrent(presentation: ClubSettlementDetailPresentation, context: ClubGovernanceReadContext, snapshotGeneration: UInt64, namespace: String) -> Bool {
        self.context == context && self.snapshotGeneration == snapshotGeneration && self.namespace == namespace &&
        presentation.scope == readScope && presentation.records.contains(record)
    }
}
