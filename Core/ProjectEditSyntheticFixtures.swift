#if DEBUG
import Foundation

@MainActor public final class ProjectEditMemoryStorage: ProjectEditDataStorage {
    public var data: [String: Data] = [:]
    public var failWrites = false
    public var failReads = false
    public init() {}
    public func read(_ key: String) throws -> Data? { if failReads { throw ProjectEditError.persistenceUnavailable }; return data[key] }
    public func write(_ value: Data, key: String) throws { if failWrites { throw ProjectEditError.persistenceUnavailable }; data[key] = value }
    public func remove(_ key: String) throws { if failWrites { throw ProjectEditError.persistenceUnavailable }; data[key] = nil }
}
public enum ProjectEditSyntheticFixtures {
    public static func draft(product: ProjectEditProduct = .city) -> ProjectEditDraft {
        var d = ProjectEditDraft(product: product)
        d.name = "Synthetic harbor trail"; d.subtitle = "Fixture route"; d.description = "A fictional route used only to test native authoring."
        d.startDate = "2030-05-01"; d.endDate = "2030-05-30"; d.recruitDeadline = "2030-04-20"
        // Displayed as text only. Never requested or uploaded.
        d.imgUrl = "fixture://cover/harbor"; d.categoryIDs = [7]; d.collaboratorIDs = [901]
        var c = ProjectEditChapter(); c.name = "The first clue"; c.description = "Find the old lighthouse on the fictional harbor."
        var n = ProjectEditNode(); n.name = "Lighthouse"; n.address = "Synthetic boardwalk"; n.longitude = "121.5"; n.latitude = "31.2"; n.templateID = 41
        c.nodes = [n]; d.chapters = [c]
        var t = ProjectEditTicket(); t.name = "Free fixture ticket"; t.price = "0"; t.meetingPoint = "Synthetic boardwalk"
        t.startTime = "2030-05-02 10:00"; t.endTime = "2030-05-02 12:00"; d.tickets = [t]
        return d
    }
    public static func snapshot(scope: ProjectEditScope = .full) -> ProjectEditSnapshot {
        var d = draft(); d.baseRevision = "fixture-r1"; d.publishToCreative = false
        return .init(topicID: 7101, scope: scope, draft: d)
    }
}
@MainActor public final class ProjectEditSyntheticService: ProjectEditServing {
    public enum Scenario { case accepted, rejected, notSent, unknown, bundlePending }
    public var authority: ProjectEditServiceAuthority { .synthetic }
    public var scenario: Scenario
    public var snapshot: ProjectEditSnapshot
    public var capability = ProjectEditCapability(canProPublish: true, remaining: nil)
    public private(set) var submissions: [ProjectEditPending] = []
    public var beforePreflight: (() async -> Void)?
    public var beforeSubmit: (() async -> Void)?
    private var receipts: [UUID: ProjectEditWriteOutcome] = [:]
    public init(scenario: Scenario = .accepted, snapshot: ProjectEditSnapshot = ProjectEditSyntheticFixtures.snapshot()) { self.scenario = scenario; self.snapshot = snapshot }
    public func preflight(topicID: Int?, session: ProjectEditSession) async throws -> ProjectEditPreflight {
        if let beforePreflight { await beforePreflight() }
        return .init(capability: capability, snapshot: topicID == nil ? nil : snapshot)
    }
    public func submit(_ operation: ProjectEditPending, session: ProjectEditSession) async -> ProjectEditWriteOutcome {
        if let receipt = receipts[operation.operationID] { return receipt }
        submissions.append(operation)
        if let beforeSubmit { await beforeSubmit() }
        let result: ProjectEditWriteOutcome
        switch scenario {
        case .bundlePending:
            let topic = operation.identity.topicID ?? 7901
            let raw: ProjectEditJSON = .object(["topicId": .number(Decimal(topic)), "auditTaskId": .number(3301), "reviewState": .string("PENDING"), "published": .bool(true), "bundledTemplateIds": .array([.number(41)])])
            guard let value = try? ProjectEditBundleAcknowledgment.decode(raw, expectedTopicID: operation.identity.topicID) else { return .unknown }
            result = .bundleAcknowledged(operationID: operation.operationID, acknowledgment: value)
        case .accepted: result = .simulatedReceipt(operationID: operation.operationID, topicID: operation.identity.topicID ?? 7901)
        case .rejected: result = .rejected
        case .notSent: result = .notSent
        case .unknown: return .unknown
        }
        receipts[operation.operationID] = result; return result
    }
    public func terminalReceipt(operationID: UUID, session: ProjectEditSession) async throws -> ProjectEditWriteOutcome? { receipts[operationID] }
}
#endif
