import Foundation

@MainActor public protocol SocialActionAccess: AnyObject {
    var identity: SocialAccountIdentity { get }
    var availability: SocialActionAvailability { get }
    func availability(for command: SocialActionCommand, target: SocialActionTarget) -> SocialActionAvailability
    func hasPending(target: SocialActionTarget) -> Bool
    func snapshot(target: SocialActionTarget) async throws -> SocialActionSnapshot
    func snapshot(target: SocialActionTarget, generation: SquareContentGeneration?) async throws -> SocialActionSnapshot
    func perform(_ command: SocialActionCommand, snapshot: SocialActionSnapshot, expectedIdentity: SocialAccountIdentity) async throws -> SocialActionReceipt
    func perform(_ command: SocialActionCommand, snapshot: SocialActionSnapshot, expectedIdentity: SocialAccountIdentity, isCurrent: @escaping () -> Bool) async throws -> SocialActionReceipt
}
public extension SocialActionAccess {
    func availability(for command: SocialActionCommand, target: SocialActionTarget) -> SocialActionAvailability { availability }
    func hasPending(target: SocialActionTarget) -> Bool { false }
    func perform(_ command: SocialActionCommand, snapshot: SocialActionSnapshot, expectedIdentity: SocialAccountIdentity, isCurrent: @escaping () -> Bool) async throws -> SocialActionReceipt {
        guard isCurrent() else { throw SocialActionWriteFailure.notSent }
        return try await perform(command, snapshot: snapshot, expectedIdentity: expectedIdentity)
    }
}
public extension SocialActionAccess {
    func snapshot(target: SocialActionTarget, generation: SquareContentGeneration?) async throws -> SocialActionSnapshot {
        let value = try await snapshot(target: target)
        if let generation { guard value.post?.generation == generation else { throw SocialActionBlock.changed } }
        return value
    }
}
/// Read bridge cannot issue writes, even when an endpoint is configured.
@MainActor public final class SocialDisabledActionAccess: SocialActionAccess {
    private let reader: any SquareReading
    private let accountReader: any SocialAccountReading
    public var identity: SocialAccountIdentity { accountReader.identity }
    public let availability: SocialActionAvailability = .disabled
    public init(reader: any SquareReading, accountReader: any SocialAccountReading) { self.reader = reader; self.accountReader = accountReader }
    public func snapshot(target: SocialActionTarget) async throws -> SocialActionSnapshot {
        try await snapshot(target: target, generation: .legacySquare)
    }
    public func snapshot(target: SocialActionTarget, generation: SquareContentGeneration?) async throws -> SocialActionSnapshot {
        guard identity.accountID != nil else { throw SocialActionBlock.signIn }
        guard target.isValid else { throw SocialActionBlock.invalid }
        let captured = identity, scope = reader.scope
        if let memberID = target.memberID {
            let profile = try await accountReader.publicProfile(memberID: memberID)
            guard identity == captured, reader.scope == scope, !Task.isCancelled else { throw CancellationError() }
            return .init(target: target, profile: profile)
        }
        guard let postID = target.postID else { return .init(target: target) }
        let route = SquareContentRoute(id: postID, generation: generation ?? .legacySquare)
        let post = try await reader.squareDetail(route: route)
        var selected: SquareComment?
        if let commentID = target.commentID {
            var pagination = SquareCommentPagination()
            while pagination.hasMore && selected == nil {
                let page = try await reader.squareComments(route: route, pageNumber: pagination.nextPage)
                let previousCount = pagination.items.count
                try pagination.accept(page)
                selected = pagination.items.first { $0.id == commentID }
                // A repeating page is not proof that the target still exists.
                if pagination.items.count == previousCount && pagination.hasMore { throw SocialActionBlock.changed }
                guard identity == captured, reader.scope == scope else { throw CancellationError() }
                try Task.checkCancellation()
            }
            guard selected != nil else { throw SocialActionBlock.changed }
        }
        guard identity == captured, reader.scope == scope else { throw CancellationError() }
        return .init(target: target, post: post, comment: selected)
    }
    public func perform(_ command: SocialActionCommand, snapshot: SocialActionSnapshot, expectedIdentity: SocialAccountIdentity) async throws -> SocialActionReceipt {
        // Intentionally no request builder, token, transport or capability escape hatch here.
        throw SocialActionWriteFailure.notSent
    }
}
public struct SocialActionReview: Equatable, Identifiable {
    public let id: UUID
    public let ownerID: UUID
    public let identity: SocialAccountIdentity
    public let target: SocialActionTarget
    public let command: SocialActionCommand
    public let snapshot: SocialActionSnapshot
}
public enum SocialActionState: Equatable {
    case idle, preparing, reviewing, preflighting, submitting, notSent, rejected, outcomeUnknown
    case acknowledged(SocialActionReceipt)
    public var locksForm: Bool {
        switch self { case .preparing, .reviewing, .preflighting, .submitting, .outcomeUnknown: return true; default: return false }
    }
}
/// Session-owned review state. Concrete production access also supplies durable unknown
/// locks across relaunch/relogin. A fresh read never converts an unknown result into success.
@MainActor public final class SocialActionCoordinator {
    private let access: any SocialActionAccess
    private struct Key: Hashable { let accountID: Int; let target: SocialActionTarget; let generation: SquareContentGeneration? }
    private struct Record { let id: UUID; let identity: SocialAccountIdentity; let ownerID: UUID; var state: SocialActionState }
    private var records: [Key: Record] = [:]
    public var identity: SocialAccountIdentity { access.identity }
    public var availability: SocialActionAvailability { access.availability }
    public func availability(for command: SocialActionCommand, target: SocialActionTarget) -> SocialActionAvailability { access.availability(for: command, target: target) }
    public init(access: any SocialActionAccess) { self.access = access }
    private func key(_ target: SocialActionTarget, _ identity: SocialAccountIdentity, generation: SquareContentGeneration? = nil) -> Key? {
        guard let accountID = identity.accountID, accountID > 0 else { return nil }
        return .init(accountID: accountID, target: target, generation: target.postID == nil ? nil : (generation ?? .legacySquare))
    }
    public func synchronizeSession() {
        for key in Array(records.keys) {
            guard let record = records[key], record.identity != identity else { continue }
            switch record.state {
            case .submitting, .outcomeUnknown: records[key]?.state = .outcomeUnknown
            default: records[key] = nil
            }
        }
    }
    public func state(target: SocialActionTarget, generation: SquareContentGeneration? = nil) -> SocialActionState {
        synchronizeSession()
        guard let key = key(target, identity, generation: generation) else { return .idle }
        if let record = records[key], record.state == .submitting { return .submitting }
        if access.hasPending(target: target) { return .outcomeUnknown }
        return records[key]?.state ?? .idle
    }
    public func prepare(_ command: SocialActionCommand, target: SocialActionTarget, ownerID: UUID, expectedIdentity: SocialAccountIdentity) async throws -> SocialActionReview {
        synchronizeSession()
        guard identity == expectedIdentity, let key = key(target, identity, generation: command.requiredGeneration) else { throw SocialActionBlock.signIn }
        guard !state(target: target, generation: command.requiredGeneration).locksForm else { throw SocialActionBlock.pending }
        try Task.checkCancellation()
        let id = UUID()
        records[key] = .init(id: id, identity: identity, ownerID: ownerID, state: .preparing)
        do {
            let snapshot = try await access.snapshot(target: target, generation: command.requiredGeneration)
            guard identity == expectedIdentity, records[key]?.id == id, records[key]?.state == .preparing, !Task.isCancelled else { throw SocialActionBlock.cancelled }
            try snapshot.validate(); try command.validate(target: target, snapshot: snapshot, identity: expectedIdentity)
            records[key]?.state = .reviewing
            return .init(id: id, ownerID: ownerID, identity: identity, target: target, command: command, snapshot: snapshot)
        } catch {
            if records[key]?.id == id, records[key]?.state == .preparing { records[key] = nil }; throw error
        }
    }
    public func cancel(_ review: SocialActionReview) {
        guard let key = key(review.target, review.identity, generation: review.command.requiredGeneration), records[key]?.id == review.id, records[key]?.state == .reviewing else { return }; records[key] = nil
    }
    public func confirm(_ review: SocialActionReview) async {
        guard let key = key(review.target, review.identity, generation: review.command.requiredGeneration), records[key]?.id == review.id, records[key]?.state == .reviewing else { return }
        guard identity == review.identity, !Task.isCancelled else { records[key] = nil; return }
        guard availability(for: review.command, target: review.target) != .disabled else { records[key]?.state = .notSent; return }
        records[key]?.state = .preflighting
        do {
            let fresh = try await access.snapshot(target: review.target, generation: review.command.requiredGeneration)
            guard identity == review.identity, records[key]?.id == review.id, records[key]?.state == .preflighting, !Task.isCancelled else { throw SocialActionBlock.cancelled }
            try fresh.validate(); try review.command.validate(target: review.target, snapshot: fresh, identity: review.identity)
            guard fresh.sameContext(as: review.snapshot) else { throw SocialActionBlock.changed }
        } catch {
            if records[key]?.id == review.id, records[key]?.state == .preflighting { records[key]?.state = .notSent }; return
        }
        guard identity == review.identity, records[key]?.id == review.id, records[key]?.state == .preflighting, !Task.isCancelled else { return }
        records[key]?.state = .submitting
        let outcome: SocialActionState
        do {
            let receipt = try await access.perform(review.command, snapshot: review.snapshot, expectedIdentity: review.identity, isCurrent: { [weak self] in
                guard let self else { return false }
                return self.identity == review.identity && self.records[key]?.id == review.id && self.records[key]?.state == .submitting
            })
            outcome = Task.isCancelled ? .outcomeUnknown : .acknowledged(receipt)
        } catch SocialActionWriteFailure.notSent { outcome = .notSent }
        catch SocialActionWriteFailure.rejected { outcome = .rejected }
        catch { outcome = .outcomeUnknown }
        guard records[key]?.id == review.id else { return }
        if identity != review.identity || records[key]?.state != .submitting {
            switch outcome { case .notSent, .rejected: records[key] = nil; default: records[key]?.state = .outcomeUnknown }
        } else { records[key]?.state = outcome }
    }
    public func leaveScreen(target: SocialActionTarget, expectedIdentity: SocialAccountIdentity, ownerID: UUID, generation: SquareContentGeneration? = nil) {
        guard let key = key(target, expectedIdentity, generation: generation), let record = records[key], record.identity == expectedIdentity, record.ownerID == ownerID else { return }
        switch record.state {
        case .preparing, .reviewing, .preflighting: records[key] = nil
        case .submitting: records[key]?.state = .outcomeUnknown
        default: break
        }
    }
}
