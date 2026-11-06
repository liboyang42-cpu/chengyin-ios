import Foundation
import Combine
import CryptoKit

/// Mirrors the original Core digest at the final transport boundary. This is not a journal.
enum ClubWelcomeNoteOriginalWire {
    static func source(clubID: String, note: String) -> String {
        func digest(_ value: String) -> String {
            SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
        }
        return digest(["CLUB_WELCOME_NOTE_V1", clubID, digest(note)].joined(separator: "\u{001f}"))
    }
}

/// One sheet/navigation visit. A retired editor cannot reuse a later visit's identity,
/// callback, or service. Role refreshes are fenced even when account/epoch stay equal.
@MainActor final class ClubWelcomeNoteVisit: ObservableObject, Identifiable {
    let id = UUID()
    let clubID: Int
    let identity: ClubReadIdentity
    let revision: UInt64
    private weak var source: (any ClubOperationsAccess)?
    private let sourceID: ObjectIdentifier
    private let serviceID: ObjectIdentifier?
    @Published private(set) var retired = false
    lazy var access: any ClubOperationsAccess = ClubWelcomeNoteVisitAccess(visit: self)
    init(clubID: Int, identity: ClubReadIdentity, access: any ClubOperationsAccess) {
        self.clubID = clubID; self.identity = identity; revision = access.welcomeNoteRevision
        source = access; sourceID = ObjectIdentifier(access)
        serviceID = access.welcomeNote.map(ObjectIdentifier.init)
    }
    var isCurrent: Bool {
        guard !retired, clubID > 0, identity.isSignedIn, let source else { return false }
        return source.identity == identity && source.welcomeNoteRevision == revision &&
            source.welcomeNote.map(ObjectIdentifier.init) == serviceID
    }
    var service: ClubWelcomeNoteService? { isCurrent ? source?.welcomeNote : nil }
    func matches(clubID: Int, identity: ClubReadIdentity?, access: any ClubOperationsAccess) -> Bool {
        isCurrent && self.clubID == clubID && self.identity == identity &&
            sourceID == ObjectIdentifier(access) && access.identity == identity &&
            access.welcomeNoteRevision == revision && access.welcomeNote.map(ObjectIdentifier.init) == serviceID
    }
    func retire() { retired = true }
    fileprivate func snapshot(target: ClubOperationsTarget) async throws -> ClubOperationsSnapshot {
        guard isCurrent, target == .club(clubID), let source else { throw ClubWelcomeNoteFailure.notSent }
        let value = try await source.snapshot(target: target)
        guard isCurrent, value.target == target else { throw ClubWelcomeNoteFailure.notSent }
        return value
    }
}

/// Gates the unchanged Core Flow's existing identity/current closures by the UI visit.
/// Ordinary perform and profile/media capabilities are never passed through this wrapper.
@MainActor private final class ClubWelcomeNoteVisitAccess: ClubOperationsAccess {
    private weak var visit: ClubWelcomeNoteVisit?
    init(visit: ClubWelcomeNoteVisit) { self.visit = visit }
    var identity: ClubReadIdentity? { visit?.isCurrent == true ? visit?.identity : nil }
    var isConfigured: Bool { visit?.isCurrent == true }
    var writeAvailability: ClubOperationsWriteAvailability { .unverified }
    var welcomeNote: ClubWelcomeNoteService? { visit?.service }
    var welcomeNoteRevision: UInt64 { visit?.revision ?? 0 }
    func snapshot(target: ClubOperationsTarget) async throws -> ClubOperationsSnapshot {
        guard let visit else { throw ClubWelcomeNoteFailure.notSent }
        return try await visit.snapshot(target: target)
    }
    func perform(_ command: ClubOperationsCommand, target: ClubOperationsTarget,
                 expectedIdentity: ClubReadIdentity) async throws -> ClubOperationsReceipt {
        throw ClubWelcomeNoteFailure.disabled
    }
}

/// A UI invalidation notice, not a server receipt, write grant, or proof of current text.
/// The editor creates it only after the unchanged Core Flow accepts an APPLIED receipt.
struct ClubWelcomeNoteConfirmedReturn {
    let visitID: UUID
    let clubID: Int
    let identity: ClubReadIdentity
    let revision: UInt64
    private let accessID: ObjectIdentifier
    private let serviceID: ObjectIdentifier?
    @MainActor init?(visit: ClubWelcomeNoteVisit, access: any ClubOperationsAccess) {
        guard visit.matches(clubID: visit.clubID, identity: visit.identity, access: access) else { return nil }
        visitID = visit.id; clubID = visit.clubID; identity = visit.identity
        revision = visit.revision; accessID = ObjectIdentifier(access)
        serviceID = access.welcomeNote.map(ObjectIdentifier.init)
    }
    @MainActor func matches(target: ClubOperationsTarget, identity: ClubReadIdentity?, access: any ClubOperationsAccess) -> Bool {
        target == .club(clubID) && self.identity == identity && access.identity == identity &&
            access.welcomeNoteRevision == revision && ObjectIdentifier(access) == accessID &&
            access.welcomeNote.map(ObjectIdentifier.init) == serviceID
    }
}

/// Refreshes actual parent facts; the original APPLIED text is never substituted here.
@MainActor enum ClubWelcomeNoteCurrentReadback {
    static func read(_ notice: ClubWelcomeNoteConfirmedReturn, access: any ClubOperationsAccess,
                     current: () -> Bool) async throws -> ClubOperationsSnapshot {
        let target = ClubOperationsTarget.club(notice.clubID)
        guard current(), notice.matches(target: target, identity: access.identity, access: access) else { throw ClubWelcomeNoteFailure.notSent }
        let fresh = try await access.snapshot(target: target)
        guard current(), !Task.isCancelled, fresh.target == target,
              notice.matches(target: target, identity: access.identity, access: access) else { throw ClubWelcomeNoteFailure.notSent }
        return fresh
    }
}
