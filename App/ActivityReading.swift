import Foundation

/// Read-only dependency shared by the production session and offline UI fixtures.
@MainActor
protocol ActivityReading: AnyObject {
    var isConfigured: Bool { get }
    func activities(page: Int, keyword: String) async throws -> [ActivitySummary]
    func activityDetail(id: Int) async throws -> ActivityDetailAccess
}

extension AppSession: ActivityReading {}
