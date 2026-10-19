import Foundation
import Observation

/// Read presentation only. Reader identity and revision retire account/role/token ABA.
public struct ProfileAuthorPostsContext: Hashable {
    public let memberID: Int
    public let viewer: SocialAccountIdentity
    public let revision: UInt64
    public let publicRetention: ProfilePublicInfoRetentionIdentity?
    public let squareScope: UUID
    public let isConfigured: Bool
    public let isSignedIn: Bool
    private let accountReaderID: ObjectIdentifier
    private let squareReaderID: ObjectIdentifier

    @MainActor public init(memberID: Int, accountReader: any SocialAccountReading, squareReader: any SquareReading) {
        self.memberID = memberID; viewer = accountReader.identity
        let publicReader = accountReader as? ProfilePublicInfoReader
        publicRetention = publicReader?.authorPostsRetentionIdentity
        // Generic readers still use their full presentation revision to fence ABA.
        revision = publicReader == nil ? accountReader.presentationRevision : 0
        squareScope = squareReader.scope
        isConfigured = accountReader.isConfigured && squareReader.isConfigured
            && (publicReader == nil || publicRetention?.memberID == memberID)
        isSignedIn = viewer.accountID != nil && squareReader.isSignedIn
        accountReaderID = ObjectIdentifier(accountReader); squareReaderID = ObjectIdentifier(squareReader)
    }
}

/// Page-local read controller. It never creates a service, session, token or mutation.
@MainActor @Observable public final class ProfileAuthorPostsRefreshController {
    public enum Operation: Equatable { case refresh, more }
    public private(set) var pagination = SquareFeedPagination()
    public private(set) var context: ProfileAuthorPostsContext?
    public private(set) var error: Error?
    public private(set) var failedOperation: Operation?
    public private(set) var activeOperation: Operation?
    private var generation: UInt64 = 0
    public init() {}
    public var isBusy: Bool { activeOperation != nil }
    public var retainsPreviousResult: Bool { pagination.hasLoadedPage && (error != nil || activeOperation == .refresh) }

    public func visibleRows(for expected: ProfileAuthorPostsContext, isCurrent: Bool = true) -> [SquarePost] {
        guard isCurrent, expected == context, expected.isConfigured, expected.isSignedIn else { return [] }
        return pagination.items
    }
    public func canOpen(_ post: SquarePost, context expected: ProfileAuthorPostsContext, isCurrent: Bool = true) -> Bool {
        visibleRows(for: expected, isCurrent: isCurrent).contains { $0.id == post.id && $0.generation == post.generation }
    }
    /// Stop only the pending read when opening a detail or switching tabs.
    /// Keep the current scoped snapshot so navigation does not remove its own source row.
    public func suspend() { generation &+= 1; activeOperation = nil }
    public func retire() {
        generation &+= 1; context = nil; pagination = .init()
        activeOperation = nil; error = nil; failedOperation = nil
    }
    /// Remounting the header/section is not an explicit feed refresh.
    /// Preserve accepted pages and recorded retry intent under the exact same read scope.
    public func activate(memberID: Int, accountReader: any SocialAccountReading, squareReader: any SquareReading,
                         isCurrent: @MainActor () -> Bool = { true }) async {
        let expected = ProfileAuthorPostsContext(memberID: memberID, accountReader: accountReader, squareReader: squareReader)
        guard !Task.isCancelled else { return }
        guard isCurrent() else { if context == expected { retire() }; return }
        if context != expected { retire() }
        guard expected.isConfigured, expected.isSignedIn, memberID > 0 else { retire(); return }
        if context == expected, pagination.hasLoadedPage || error != nil || isBusy { return }
        await refresh(memberID: memberID, accountReader: accountReader, squareReader: squareReader, isCurrent: isCurrent)
    }
    @discardableResult public func rejectHeader(_ error: Error, context expected: ProfileAuthorPostsContext) -> Bool {
        guard context == expected else { return false }
        var unavailable = Self.isAccessDenial(error)
        if case APIError.httpStatus(404) = error { unavailable = true }
        if case APIError.businessCode(404) = error { unavailable = true }
        if case SocialAccountFailure.rejected(let code, _) = error,
           [2, 401, 403, 404].contains(code) { unavailable = true }
        guard unavailable else { return false }
        retire(); return true
    }
    public func refresh(memberID: Int, accountReader: any SocialAccountReading, squareReader: any SquareReading,
                        isCurrent: @MainActor () -> Bool = { true }) async {
        await load(.refresh, memberID: memberID, accountReader: accountReader, squareReader: squareReader, isCurrent: isCurrent)
    }
    public func loadMore(memberID: Int, accountReader: any SocialAccountReading, squareReader: any SquareReading,
                         isCurrent: @MainActor () -> Bool = { true }) async {
        await load(.more, memberID: memberID, accountReader: accountReader, squareReader: squareReader, isCurrent: isCurrent)
    }
    public func retry(memberID: Int, accountReader: any SocialAccountReading, squareReader: any SquareReading,
                      isCurrent: @MainActor () -> Bool = { true }) async {
        let expected = ProfileAuthorPostsContext(memberID: memberID, accountReader: accountReader, squareReader: squareReader)
        guard expected == context, let operation = failedOperation else { return }
        await load(operation, memberID: memberID, accountReader: accountReader, squareReader: squareReader, isCurrent: isCurrent)
    }
    private func load(_ operation: Operation, memberID: Int, accountReader: any SocialAccountReading,
                      squareReader: any SquareReading, isCurrent: @MainActor () -> Bool) async {
        let captured = ProfileAuthorPostsContext(memberID: memberID, accountReader: accountReader, squareReader: squareReader)
        guard !Task.isCancelled else { return }
        guard isCurrent() else { if context == captured { retire() }; return }
        if context != captured { retire(); context = captured }
        guard !isBusy else { return }
        guard memberID > 0, captured.isConfigured, captured.isSignedIn else {
            pagination = .init(); failedOperation = nil
            error = memberID <= 0 ? APIError.invalidRequest : (captured.isConfigured ? APIError.unauthorized : APIError.notConfigured)
            return
        }
        if operation == .more {
            guard pagination.hasLoadedPage, pagination.hasMore, pagination.nextCursor != nil,
                  error == nil || failedOperation == .more else { return }
        }
        generation &+= 1; let run = generation
        let cursor = operation == .refresh ? nil : pagination.nextCursor
        activeOperation = operation; error = nil; failedOperation = nil
        defer { if run == generation { activeOperation = nil } }
        do {
            let page = try await squareReader.squareFeed(query: .init(authorID: memberID), cursor: cursor)
            try Task.checkCancellation()
            guard run == generation else { return }
            guard isCurrent(), captured == ProfileAuthorPostsContext(memberID: memberID, accountReader: accountReader, squareReader: squareReader) else { retire(); return }
            // Build separately: failed refresh never erases the old tail or its continuation.
            var replacement = operation == .refresh ? SquareFeedPagination() : pagination
            try replacement.accept(page, requestedCursor: cursor)
            pagination = replacement
        } catch is CancellationError {
            // A cancelled request is not a user-visible failure or a new retry intent.
            if run == generation, !isCurrent() || captured != ProfileAuthorPostsContext(memberID: memberID, accountReader: accountReader, squareReader: squareReader) { retire() }
        } catch {
            guard !Task.isCancelled, run == generation else { return }
            guard isCurrent(), captured == ProfileAuthorPostsContext(memberID: memberID, accountReader: accountReader, squareReader: squareReader) else { retire(); return }
            if Self.isAccessDenial(error) {
                pagination = .init(); failedOperation = nil
                self.error = error as? APIError == .notConfigured ? APIError.notConfigured : APIError.unauthorized
            } else {
                self.error = error; failedOperation = operation
            }
        }
    }
    private static func isAccessDenial(_ error: Error) -> Bool {
        if let api = error as? APIError {
            if api == .unauthorized || api == .notConfigured { return true }
            if case .httpStatus(let code) = api { return code == 401 || code == 403 }
            if case .businessCode(let code) = api { return code == 2 || code == 401 || code == 403 }
        }
        if let failure = error as? SquareReadFailure {
            if failure == .signInRequired { return true }
            if case .server(let code, _) = failure { return code == 2 || code == 401 || code == 403 }
        }
        return false
    }
}
