import SwiftUI

/// Package 01: binds the existing theme 本局记录 / 背包 coordinators to the existing
/// `PlayExperienceService` reads. No new endpoint: `themeHistory`, `themeCard`, `themeState`.
/// The reader is created only when the read capability is already accepted and a live session
/// exists; every call (and every late response) is re-checked against the captured session, so an
/// account switch/relogin discards results instead of showing them.
@MainActor final class PlayThemeAuxiliaryReader: PlayThemeRecordsReading, PlayThemeBackpackReading {
    let scope: PlaySessionScope
    let topicID: Int
    private let service: PlayExperienceService
    private let current: () -> PlayExperienceSession?
    private let captured: PlayExperienceSession

    init?(service: PlayExperienceService?, scope: PlaySessionScope, topicID: Int, current: @escaping () -> PlayExperienceSession?) {
        guard let service, service.enabled.contains(.reads), scope.isValid, topicID > 0, let captured = current() else { return nil }
        if case .topic(let scopedTopicID) = scope, scopedTopicID != topicID { return nil }
        self.service = service; self.scope = scope; self.topicID = topicID; self.current = current; self.captured = captured
    }

    private func live() throws -> PlayExperienceSession {
        guard let session = current(), session == captured else { throw PlayExperienceError.staleSession }
        return session
    }

    func history(topicID: Int, beforeSessionID: Int?) async throws -> [PlayWireValue] {
        guard topicID == self.topicID else { throw APIError.invalidRequest }
        let session = try live()
        let rows = try await service.themeHistory(topicID: topicID, beforeSessionID: beforeSessionID, token: session.token)
        _ = try live()
        return rows
    }

    func card(sessionID: Int) async throws -> PlayWireValue {
        let session = try live()
        let value = try await service.themeCard(sessionID: sessionID, token: session.token)
        _ = try live()
        return value
    }

    func state() async throws -> PlayWireValue {
        let session = try live()
        let value = try await service.themeState(scope: scope, topicID: topicID, token: session.token)
        _ = try live()
        return value
    }
}

typealias PlayThemeAuxiliaryProvider = @MainActor (PlaySessionScope, Int) -> PlayThemeAuxiliaryReader?

private struct PlayThemeAuxiliaryProviderKey: EnvironmentKey {
    static let defaultValue: PlayThemeAuxiliaryProvider? = nil
}

extension EnvironmentValues {
    var playThemeAuxiliaryProvider: PlayThemeAuxiliaryProvider? {
        get { self[PlayThemeAuxiliaryProviderKey.self] }
        set { self[PlayThemeAuxiliaryProviderKey.self] = newValue }
    }
}

/// Retains one pair of coordinators per `(sessionRevision, scope, topicID)` so SwiftUI redraws
/// do not wipe loaded records/backpack state, while any session or topic change replaces them.
@MainActor final class PlayThemeAuxiliaryStore {
    private struct Key: Equatable { let revision: UInt64; let scope: PlaySessionScope; let topicID: Int }
    private var key: Key?
    private var records: PlayThemeRecordsCoordinator?
    private var backpack: PlayThemeBackpackCoordinator?

    func models(revision: UInt64, scope: PlaySessionScope, topicID: Int?, provider: PlayThemeAuxiliaryProvider?)
        -> (records: PlayThemeRecordsCoordinator?, backpack: PlayThemeBackpackCoordinator?) {
        guard let topicID, topicID > 0, let provider else { key = nil; records = nil; backpack = nil; return (nil, nil) }
        if case .topic(let scopedTopicID) = scope, scopedTopicID != topicID { key = nil; records = nil; backpack = nil; return (nil, nil) }
        let next = Key(revision: revision, scope: scope, topicID: topicID)
        if key != next {
            key = next
            if let reader = provider(scope, topicID) {
                records = PlayThemeRecordsCoordinator(topicID: topicID, reader: reader)
                backpack = PlayThemeBackpackCoordinator(reader: reader)
            } else { records = nil; backpack = nil }
        }
        return (records, backpack)
    }
}
