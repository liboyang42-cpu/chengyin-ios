import Foundation
import Observation

/// Presentation association, not a read approval. The injected owner-only reader remains
/// the authority; neither public profile access nor an account ID can grant order reads.
public struct ProfileSelfOrdersContext: Hashable {
    public let memberID: Int
    public let socialReaderID: ObjectIdentifier
    public let socialOwner: SocialAccountIdentity
    public let socialRevision: UInt64
    public let ordersReaderID: ObjectIdentifier
    public let ordersOwner: ProfileReadIdentity
    @MainActor public static func capture(memberID: Int, social: any SocialAccountReading,
        orders: any ProfileReading, owner: SocialAccountIdentity, ordersOwner: ProfileReadIdentity?,
        isCurrent: Bool) -> Self? {
        guard isCurrent, memberID > 0, owner.accountID == memberID, social.identity == owner,
              social.isConfigured, orders.isConfigured, let ordersOwner,
              ordersOwner.accountID == memberID, orders.identity == ordersOwner else { return nil }
        return .init(memberID: memberID, socialReaderID: ObjectIdentifier(social), socialOwner: owner,
            socialRevision: social.presentationRevision, ordersReaderID: ObjectIdentifier(orders), ordersOwner: ordersOwner)
    }
}

/// A bounded existing-reader proxy. It cannot issue a lease, manufacture a session,
/// dispatch mutations, or expose participants/badges through the profile preview.
@MainActor public final class ProfileSelfOrdersScopedReader: ProfileReading {
    public let scope = UUID()
    private let expected: ProfileSelfOrdersContext
    private let social: any SocialAccountReading
    private let orders: any ProfileReading
    private let isCurrent: @MainActor () -> Bool
    public init(context: ProfileSelfOrdersContext, social: any SocialAccountReading,
        orders: any ProfileReading, isCurrent: @escaping @MainActor () -> Bool) {
        expected = context; self.social = social; self.orders = orders; self.isCurrent = isCurrent
    }
    public var isCurrentContext: Bool {
        ProfileSelfOrdersContext.capture(memberID: expected.memberID, social: social, orders: orders,
            owner: expected.socialOwner, ordersOwner: expected.ordersOwner, isCurrent: isCurrent()) == expected
    }
    public var identity: ProfileReadIdentity? { isCurrentContext ? expected.ordersOwner : nil }
    public var isConfigured: Bool { isCurrentContext }
    public func profileOrders() async throws -> [ProfileOrder] {
        try Task.checkCancellation(); guard isCurrentContext else { throw CancellationError() }
        do {
            let rows = try await orders.profileOrders()
            try Task.checkCancellation(); guard isCurrentContext else { throw CancellationError() }
            guard rows.allSatisfy({ $0.id > 0 && $0.memberID == expected.memberID }),
                  Set(rows.map(\.id)).count == rows.count else { throw APIError.malformedResponse }
            return rows
        } catch {
            guard !Task.isCancelled, isCurrentContext else { throw CancellationError() }
            throw error
        }
    }
    public func profileOrder(id: Int) async throws -> ProfileOrder {
        try Task.checkCancellation(); guard isCurrentContext else { throw CancellationError() }
        guard id > 0 else { throw APIError.invalidRequest }
        do {
            let row = try await orders.profileOrder(id: id)
            try Task.checkCancellation(); guard isCurrentContext else { throw CancellationError() }
            guard row.id == id, row.memberID == expected.memberID else { throw APIError.malformedResponse }
            return row
        } catch {
            guard !Task.isCancelled, isCurrentContext else { throw CancellationError() }
            throw error
        }
    }
    public func profileParticipants() async throws -> [ProfileParticipant] { throw APIError.notConfigured }
    public func profileParticipant(id: Int) async throws -> ProfileParticipant { throw APIError.notConfigured }
    public func profileBadges() async throws -> ProfileBadgeWall { throw APIError.notConfigured }
}

public struct ProfileSelfOrdersPreview: Equatable {
    public let rows: [ProfileOrder]
    public init(rows: [ProfileOrder]) { self.rows = Array(rows.prefix(8)) }
    /// Source createTime is shown as a source label, not converted to a device timezone.
    public static func createdLabel(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return String(value.prefix(16)).replacingOccurrences(of: "T", with: " ")
    }
}
public enum ProfileSelfOrdersIssue: String, Equatable {
    case readFailed, signIn, unavailable
    public var titleKey: String { "profile.selfOrders." + rawValue }
    public init(_ error: Error) {
        if error as? APIError == .unauthorized || (error as? ProfileReadFailure)?.isUnauthorized == true { self = .signIn }
        else if error as? APIError == .notConfigured { self = .unavailable }
        else { self = .readFailed }
    }
}

@MainActor @Observable public final class ProfileSelfOrdersController {
    public private(set) var rows: [ProfileOrder]?
    public private(set) var issue: ProfileSelfOrdersIssue?
    public private(set) var isLoading = false
    public private(set) var loadedScope: UUID?
    private var generation: UInt64 = 0
    public init() {}
    public func suspend() { generation &+= 1; isLoading = false }
    public func retire() { suspend(); rows = nil; issue = nil; loadedScope = nil }
    public func load(reader: ProfileSelfOrdersScopedReader) async {
        guard reader.isCurrentContext else { retire(); return }
        guard !isLoading else { return }
        if loadedScope != reader.scope { rows = nil; issue = nil }
        generation &+= 1; let stamp = generation
        isLoading = true; issue = nil; loadedScope = reader.scope
        defer { if generation == stamp { isLoading = false } }
        func current() -> Bool { generation == stamp && !Task.isCancelled && reader.isCurrentContext && loadedScope == reader.scope }
        do {
            let next = try await reader.profileOrders()
            guard current() else { return }
            rows = next
        } catch is CancellationError { }
        catch {
            guard current() else { return }
            let failure = ProfileSelfOrdersIssue(error); issue = failure
            if failure == .signIn || failure == .unavailable { rows = nil }
        }
    }
    public func canOpen(_ row: ProfileOrder, reader: ProfileSelfOrdersScopedReader) -> Bool {
        guard reader.isCurrentContext, loadedScope == reader.scope, !isLoading, issue == nil, let rows else { return false }
        return ProfileSelfOrdersPreview(rows: rows).rows.contains(row)
    }
}
