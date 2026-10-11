import Foundation
import Observation

/// Host association only. The existing reader remains the sole authority for account reads.
public struct ProfileSelfProjectsContext: Hashable {
    public let memberID: Int
    public let accountReader: ObjectIdentifier
    public let viewer: SocialAccountIdentity
    public let viewerRevision: UInt64
    public let projectsReader: ObjectIdentifier
    public let projectsScope: UUID
    @MainActor public static func capture(memberID: Int, accountReader: any SocialAccountReading,
        projectsReader: any CreatorContentReading, owner: SocialAccountIdentity, ownerScope: UUID,
        isCurrent: Bool) -> Self? {
        guard isCurrent, memberID > 0, owner.accountID == memberID, accountReader.identity == owner,
              accountReader.isConfigured, projectsReader.isAuthenticated, projectsReader.isConfigured,
              projectsReader.scope == ownerScope else { return nil }
        return .init(memberID: memberID, accountReader: ObjectIdentifier(accountReader), viewer: owner,
            viewerRevision: accountReader.presentationRevision, projectsReader: ObjectIdentifier(projectsReader), projectsScope: ownerScope)
    }
}
@MainActor public final class ProfileSelfProjectsScopedReader: CreatorContentReading {
    public let scope = UUID()
    private let expected: ProfileSelfProjectsContext
    private let accountReader: any SocialAccountReading
    private let reader: any CreatorContentReading
    private let isCurrent: @MainActor () -> Bool
    public init(context: ProfileSelfProjectsContext, accountReader: any SocialAccountReading,
        projectsReader: any CreatorContentReading, isCurrent: @escaping @MainActor () -> Bool) {
        expected = context; self.accountReader = accountReader; reader = projectsReader; self.isCurrent = isCurrent
    }
    public var isCurrentContext: Bool {
        ProfileSelfProjectsContext.capture(memberID: expected.memberID, accountReader: accountReader,
            projectsReader: reader, owner: expected.viewer, ownerScope: expected.projectsScope, isCurrent: isCurrent()) == expected
    }
    public var isAuthenticated: Bool { isCurrentContext && reader.isAuthenticated }
    public var isConfigured: Bool { isCurrentContext && reader.isConfigured }
    public var isOfflineExample: Bool { reader.isOfflineExample }
    public func projects(query: CreatorContentQuery) async throws -> CreatorContentProjectPage {
        try Task.checkCancellation()
        guard isCurrentContext else { throw CancellationError() }
        do {
            let page = try await reader.projects(query: query)
            try Task.checkCancellation()
            guard isCurrentContext else { throw CancellationError() }
            return page
        } catch {
            guard !Task.isCancelled, isCurrentContext else { throw CancellationError() }
            throw error
        }
    }
    /// The profile projection never grants access to creator income/center data.
    public func center() async throws -> CreatorContentCenter { throw APIError.invalidRequest }
}

public enum ProfileSelfProjectSchedule: String, Equatable { case upcoming, running, ended }
public enum ProfileSelfProjectCalendar {
    /// Same prefix contract as Mini toDayStr: dates are business-calendar labels, not device instants.
    public static func day(_ value: String?) -> String? {
        guard let text = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              let range = text.range(of: #"^\d{4}-\d{2}-\d{2}"#, options: .regularExpression) else { return nil }
        return String(text[range])
    }
    public static func today(at instant: Date = Date()) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let parts = calendar.dateComponents([.year, .month, .day], from: instant)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }
    public static func status(start: String?, end: String?, today: String) -> ProfileSelfProjectSchedule? {
        guard let start = day(start) else { return nil }
        let end = max(day(end) ?? start, start)
        if today < start { return .upcoming }
        if today > end { return .ended }
        return .running
    }
}
public struct ProfileSelfProjectsPreview: Equatable {
    public let rows: [CreatorContentProject]
    public let sourceTruncated: Bool
    public init(page: CreatorContentProjectPage, today: String) {
        var seen = Set<String>()
        // Backend type filters projectType (simple/pro/self_play), NOT bizType. Read all then filter.
        rows = Array(page.rows.filter { row in
            row.bizType == "topic" && row.sourceID > 0 && seen.insert(row.id).inserted &&
            ProfileSelfProjectCalendar.status(start: row.startTime, end: row.endTime, today: today) != .ended
        }.prefix(8))
        sourceTruncated = page.isTruncated
    }
}
@MainActor @Observable public final class ProfileSelfProjectsController {
    public private(set) var page: CreatorContentProjectPage?
    public private(set) var issue: CreatorContentIssue?
    public private(set) var isLoading = false
    public private(set) var loadedScope: UUID?
    private var generation: UInt64 = 0
    public init() {}
    public func suspend() { generation &+= 1; isLoading = false }
    public func retire() { suspend(); page = nil; issue = nil; loadedScope = nil }
    public func load(reader: ProfileSelfProjectsScopedReader) async {
        guard reader.isCurrentContext else { retire(); return }
        guard !isLoading else { return }
        let scope = reader.scope
        if loadedScope != scope { page = nil; issue = nil }
        generation &+= 1; let run = generation
        isLoading = true; issue = nil; loadedScope = scope
        defer { if generation == run { isLoading = false } }
        func current() -> Bool { generation == run && !Task.isCancelled && reader.isCurrentContext && loadedScope == scope }
        do {
            guard current() else { return }
            let next = try await reader.projects(query: .init())
            guard current() else { return }
            page = next // Authoritative empty replaces old rows; failures never masquerade as empty.
        } catch is CancellationError { }
        catch {
            guard current() else { return }
            issue = CreatorContentIssue(error)
            if issue == .login { page = nil }
        }
    }
    public func canOpen(_ row: CreatorContentProject, reader: ProfileSelfProjectsScopedReader, today: String) -> Bool {
        guard reader.isCurrentContext, loadedScope == reader.scope, issue == nil, !isLoading, let page else { return false }
        return ProfileSelfProjectsPreview(page: page, today: today).rows.contains(row)
    }
}
