import Foundation
import Observation

public struct ProfileSelfMedalsContext: Hashable {
    public let memberID: Int
    public let accountReader: ObjectIdentifier
    public let viewer: SocialAccountIdentity
    public let viewerRevision: UInt64
    public let profileReader: ObjectIdentifier
    public let owner: ProfileReadIdentity
    @MainActor public static func capture(memberID: Int, accountReader: any SocialAccountReading,
                                          profileReader: any ProfileReading, isCurrent: Bool) -> Self? {
        guard isCurrent, memberID > 0, accountReader.isConfigured, profileReader.isConfigured,
              accountReader.identity.accountID == memberID, let owner = profileReader.identity,
              owner.accountID == memberID else { return nil }
        return .init(memberID: memberID, accountReader: ObjectIdentifier(accountReader),
            viewer: accountReader.identity, viewerRevision: accountReader.presentationRevision,
            profileReader: ObjectIdentifier(profileReader), owner: owner)
    }
}
/// Own-account reads only, through the existing approved reader. No separate endpoint or image client.
@MainActor @Observable public final class ProfileSelfMedalsController {
    public enum Issue: Equatable { case readFailed, partial, signIn }
    public private(set) var context: ProfileSelfMedalsContext?
    public private(set) var medals: [ProfileMedal]?
    public private(set) var issue: Issue?
    public private(set) var isLoading = false
    private var generation: UInt64 = 0
    public init() {}
    /// Preserve rows that own a pushed NavigationLink. They render only against the exact context.
    public func suspend() { generation &+= 1; isLoading = false }
    public func retire() { suspend(); context = nil; medals = nil; issue = nil }
    public func load(memberID: Int, accountReader: any SocialAccountReading, profileReader: any ProfileReading,
                     isCurrent: @escaping @MainActor () -> Bool = { true }) async {
        guard let captured = ProfileSelfMedalsContext.capture(memberID: memberID, accountReader: accountReader,
            profileReader: profileReader, isCurrent: isCurrent()) else { retire(); return }
        guard !isLoading || context != captured else { return }
        if context != captured { medals = nil; issue = nil; context = captured }
        generation &+= 1; let run = generation; isLoading = true; issue = nil
        defer { if generation == run { isLoading = false } }
        func current() -> Bool {
            generation == run && context == captured && !Task.isCancelled &&
            ProfileSelfMedalsContext.capture(memberID: memberID, accountReader: accountReader,
                profileReader: profileReader, isCurrent: isCurrent()) == captured
        }
        do {
            guard current() else { return }
            let wall = try await profileReader.profileBadges()
            guard current() else { return }
            guard let rows = wall.medals else { issue = .partial; return }
            medals = rows // An authoritative empty array replaces previously loaded rows.
        } catch is CancellationError { }
        catch {
            guard current() else { return }
            if error as? APIError == .unauthorized || (error as? ProfileReadFailure)?.isUnauthorized == true {
                medals = nil; issue = .signIn
            } else { issue = .readFailed }
        }
    }
}

/// Only the badge read is forwarded. A queued destination task cannot read a replacement
/// account before its parent rerenders, even if the underlying reader follows live sessions.
@MainActor public final class ProfileSelfMedalsScopedReader: ProfileReading {
    private let expected: ProfileSelfMedalsContext
    private let accountReader: any SocialAccountReading
    private let reader: any ProfileReading
    private let isCurrent: @MainActor () -> Bool
    public init(context: ProfileSelfMedalsContext, accountReader: any SocialAccountReading,
                profileReader: any ProfileReading, isCurrent: @escaping @MainActor () -> Bool) {
        expected = context; self.accountReader = accountReader; reader = profileReader; self.isCurrent = isCurrent
    }
    private var matches: Bool {
        ProfileSelfMedalsContext.capture(memberID: expected.memberID, accountReader: accountReader,
            profileReader: reader, isCurrent: isCurrent()) == expected
    }
    public var identity: ProfileReadIdentity? { matches ? expected.owner : nil }
    public var isConfigured: Bool { matches && reader.isConfigured }
    public func profileBadges() async throws -> ProfileBadgeWall {
        try Task.checkCancellation()
        guard matches else { throw CancellationError() }
        let wall = try await reader.profileBadges()
        try Task.checkCancellation()
        guard matches else { throw CancellationError() }
        return wall
    }
    public func profileOrders() async throws -> [ProfileOrder] { throw APIError.invalidRequest }
    public func profileOrder(id: Int) async throws -> ProfileOrder { throw APIError.invalidRequest }
    public func profileParticipants() async throws -> [ProfileParticipant] { throw APIError.invalidRequest }
    public func profileParticipant(id: Int) async throws -> ProfileParticipant { throw APIError.invalidRequest }
}
