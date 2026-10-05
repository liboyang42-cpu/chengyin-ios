import Foundation
import Combine

/// Read-only dependency shared by the production session and offline UI fixtures.
@MainActor
protocol ActivityReading: AnyObject {
    var isConfigured: Bool { get }
    var activityListIsConfigured: Bool { get }
    var activityListUnavailableMessageKey: String? { get }
    var activityPresentationIdentity: String { get }
    var activityPresentationChanges: AnyPublisher<Void, Never> { get }
    func activities(page: Int, keyword: String) async throws -> [ActivitySummary]
    func activityDetail(id: Int) async throws -> ActivityDetailAccess
}
extension ActivityReading {
    var activityListIsConfigured: Bool { isConfigured }
    var activityListUnavailableMessageKey: String? { nil }
    var activityPresentationIdentity: String { "offline-activity-reader" }
    var activityPresentationChanges: AnyPublisher<Void, Never> { Empty<Void, Never>().eraseToAnyPublisher() }
}
extension AppSession: ActivityReading {
    /// Same independently reviewed homeAndSearch grant; detail approval stays separate.
    var activityListIsConfigured: Bool { activityListReadAvailability == .available }
    var activityListUnavailableMessageKey: String? {
        activityListReadAvailability == .homeReadNotApproved ? "readConfiguration.activityListReadNotApproved" : activityListReadAvailability.messageKey
    }
    var activityPresentationIdentity: String { "\(sessionRevision):\(contentDetailRevision)" }
    var activityPresentationChanges: AnyPublisher<Void, Never> { objectWillChange.eraseToAnyPublisher() }
}
struct ActivityListReadIdentity: Hashable {
    let reader: ObjectIdentifier
    let scope: String
    let configured: Bool
    @MainActor init(_ reader: any ActivityReading) {
        self.reader = ObjectIdentifier(reader)
        scope = reader.activityPresentationIdentity
        configured = reader.activityListIsConfigured
    }
}
