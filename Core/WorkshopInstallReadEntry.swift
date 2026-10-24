import Foundation

/// Reads one original install receipt. A page that says it finished does not
/// become installed. The request id is not replaced.
public struct WorkshopInstallReadEntry: Equatable, Sendable {
    public let consumer = WorkshopOriginalInstallConsumer()
    public init() {}

    public func read(requestID: String, identity: WorkshopInstallIdentity,
                     source: any WorkshopOriginalInstallReading) async throws -> WorkshopOriginalInstallFact {
        try await consumer.read(requestID: requestID, identity: identity, source: source)
    }

    public func rejectPageClear(requestID: String) throws {
        try consumer.rejectSelfReport(requestID: requestID)
    }
}
