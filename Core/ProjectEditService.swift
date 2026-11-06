import Foundation

public struct ProjectEditCapability: Equatable {
    public let canProPublish: Bool
    public let remaining: Int?
    public init(canProPublish: Bool, remaining: Int?) { self.canProPublish = canProPublish; self.remaining = remaining }
    public var allowsCreate: Bool { canProPublish && (remaining.map { $0 > 0 } ?? true) }
}
#if DEBUG
public enum ProjectEditServiceAuthority { case disabled, readOnly, approved, synthetic }
#else
public enum ProjectEditServiceAuthority { case disabled, readOnly, approved }
#endif
public struct ProjectEditPreflight: Equatable {
    public var capability: ProjectEditCapability
    public var snapshot: ProjectEditSnapshot?
    public init(capability: ProjectEditCapability, snapshot: ProjectEditSnapshot?) { self.capability = capability; self.snapshot = snapshot }
}
public enum ProjectEditWriteOutcome: Equatable {
    /// Fixture-only terminal receipt, kept separate from immediate HTTP acknowledgments.
    case simulatedReceipt(operationID: UUID, topicID: Int)
    /// Immediate server acknowledgment; not a later terminal receipt.
    case acknowledged(operationID: UUID, topicID: Int)
    /// Exact immediate V2 submission facts. PENDING + legacy published=true is not approval.
    case bundleAcknowledged(operationID: UUID, acknowledgment: ProjectEditBundleAcknowledgment)
    /// Same-transaction original writer fact, not a claim that review/publication/post-processing completed.
    case postProcessingReceipt(operationID: UUID, topicID: Int, bundle: ProjectEditBundleAcknowledgment?, receipt: ProjectEditPostProcessingReceipt)
    case committedReceipt(operationID: UUID, topicID: Int, bundle: ProjectEditBundleAcknowledgment?)
    case notSent, rejected, unknown
}
@MainActor public protocol ProjectEditServing: AnyObject {
    var authority: ProjectEditServiceAuthority { get }
    var supportsRequestReadback: Bool { get }
    var supportsRequestRetry: Bool { get }
    var supportsPostProcessingResume: Bool { get }
    func preflight(topicID: Int?, session: ProjectEditSession) async throws -> ProjectEditPreflight
    func submit(_ operation: ProjectEditPending, session: ProjectEditSession) async -> ProjectEditWriteOutcome
    func terminalReceipt(operation: ProjectEditPending, session: ProjectEditSession) async throws -> ProjectEditWriteOutcome?
    func resumePostProcessing(_ operation: ProjectEditPending, session: ProjectEditSession) async -> ProjectEditWriteOutcome
    func retrySameRequest(_ operation: ProjectEditPending, session: ProjectEditSession) async -> ProjectEditWriteOutcome
    func terminalReceipt(operationID: UUID, session: ProjectEditSession) async throws -> ProjectEditWriteOutcome?
}
public extension ProjectEditServing {
    var supportsRequestReadback: Bool { false }
    var supportsRequestRetry: Bool { false }
    var supportsPostProcessingResume: Bool { false }
    func resumePostProcessing(_ operation: ProjectEditPending, session: ProjectEditSession) async -> ProjectEditWriteOutcome { .unknown }
    func terminalReceipt(operation: ProjectEditPending, session: ProjectEditSession) async throws -> ProjectEditWriteOutcome? {
        try await terminalReceipt(operationID: operation.operationID, session: session)
    }
    func retrySameRequest(_ operation: ProjectEditPending, session: ProjectEditSession) async -> ProjectEditWriteOutcome { .unknown }
}
/// Default composition remains disabled. The separate HTTP adapter requires independently
/// scoped approval and a durable local lock; it never invents a reconciliation endpoint.
@MainActor public final class ProjectEditDisabledService: ProjectEditServing {
    public init() {}
    public var authority: ProjectEditServiceAuthority { .disabled }
    public func preflight(topicID: Int?, session: ProjectEditSession) async throws -> ProjectEditPreflight { throw ProjectEditError.notConfigured }
    public func submit(_ operation: ProjectEditPending, session: ProjectEditSession) async -> ProjectEditWriteOutcome { .notSent }
    public func terminalReceipt(operationID: UUID, session: ProjectEditSession) async throws -> ProjectEditWriteOutcome? { throw ProjectEditError.notConfigured }
}
