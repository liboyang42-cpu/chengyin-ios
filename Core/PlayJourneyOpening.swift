import Foundation

/// Mini-program `pages/play/index.js continueChapterStory` (lines 3300-3336): the
/// opening chapter's 出发 button. `routeState.opening = {chapterId, ready, complete}`
/// (`utils/play-route-state.js`). Not ready → 请先完成开局玩法 and jump to the current
/// node's game; ready → `POST api/play/journey/opening/complete` (JSON
/// `{activityId|topicId, topicId, chapterId, expectedVersion}`), then reload.
public struct PlayJourneyOpening: Decodable, Equatable, Sendable {
    public let chapterID: Int
    public let ready: Bool
    public let complete: Bool
    private enum CodingKeys: String, CodingKey { case chapterId, ready, complete }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = try c.playInt(.chapterId), id > 0 else { throw APIError.malformedResponse }
        chapterID = id
        ready = try c.decodeIfPresent(Bool.self, forKey: .ready) ?? false
        complete = try c.decodeIfPresent(Bool.self, forKey: .complete) ?? false
    }
    public init(chapterID: Int, ready: Bool, complete: Bool) { self.chapterID = chapterID; self.ready = ready; self.complete = complete }
}

public enum PlayOpeningGate: Equatable, Sendable {
    /// Ordinary 继续 / 继续探索: no pending opening on this chapter.
    case notOpening
    /// 请先完成开局玩法; scroll to the current node's chapter game.
    case finishOpeningPlayFirst(currentNodeID: Int?)
    case readyToDepart(chapterID: Int, expectedVersion: Int)
    /// Pending and ready, but the route has no version to compare against.
    case versionUnavailable

    public static func evaluate(route: PlayRouteState?, chapterIsOpening: Bool, isPreview: Bool) -> PlayOpeningGate {
        guard !isPreview, chapterIsOpening, let route, let opening = route.opening, !opening.complete else { return .notOpening }
        guard opening.ready else { return .finishOpeningPlayFirst(currentNodeID: route.currentNodeID) }
        guard let version = route.version else { return .versionUnavailable }
        return .readyToDepart(chapterID: opening.chapterID, expectedVersion: version)
    }

    /// Opening pending suppresses the all-done / run-restore paths (`index.js:884,3870`).
    public static func suppressesCompletion(_ route: PlayRouteState?) -> Bool {
        route?.opening.map { !$0.complete } ?? false
    }
}

extension PlayExperienceService {
    /// Dormant: `.journeyOpening` is in no production capability set.
    public func completeOpening(scope: PlaySessionScope, topicID: Int, chapterID: Int, expectedVersion: Int, token: String) async throws {
        guard topicID > 0, chapterID > 0, expectedVersion >= 0 else { throw APIError.invalidRequest }
        var body = scopeJSON(scope)
        guard scope.isValid else { throw APIError.invalidRequest }
        body["topicId"] = .int(topicID); body["chapterId"] = .int(chapterID); body["expectedVersion"] = .int(expectedVersion)
        _ = try await request("api/play/journey/opening/complete", json: body, capability: .journeyOpening, token: token)
    }
}

public protocol PlayOpeningCompleting: AnyObject {
    @MainActor func route() async throws -> PlayRouteState
    @MainActor func complete(chapterID: Int, expectedVersion: Int) async throws
}

/// Explicit confirmation, one in-flight request, and route-state read-back for an
/// unknown result: the server's `opening.complete` (not a local animation) decides.
@available(macOS 14.0, *)
@MainActor @Observable public final class PlayOpeningCompletionCoordinator {
    public enum Phase: Equatable {
        case idle, loading, failed
        case finishPlayFirst(currentNodeID: Int?)
        case reviewing(chapterID: Int, expectedVersion: Int)
        case submitting
        case departed
        /// Server refusal; `conflict` means the route moved and was re-read.
        case rejected(message: String?, conflict: Bool)
        case unknown
        case disabled
    }
    public private(set) var phase: Phase
    public private(set) var route: PlayRouteState?
    private let client: (any PlayOpeningCompleting)?
    private var generation: UInt64 = 0

    public init(client: (any PlayOpeningCompleting)?) {
        self.client = client
        phase = client == nil ? .disabled : .idle
    }

    public func load() async {
        guard let client, phase != .submitting else { return }
        generation &+= 1; let request = generation
        let resting = phase
        phase = .loading
        do {
            let value = try await client.route()
            guard request == generation else { return }
            route = value
            phase = resting == .unknown ? (PlayOpeningGate.suppressesCompletion(value) ? .unknown : .departed) : .idle
        } catch {
            guard request == generation else { return }
            phase = resting == .unknown ? .unknown : .failed
        }
    }

    /// The 出发 tap. Reviews only; nothing is sent until `confirm()`.
    public func depart(chapterIsOpening: Bool) {
        guard client != nil, phase == .idle || phase == .failed || isFinishPlayFirst || isRejected else { return }
        switch PlayOpeningGate.evaluate(route: route, chapterIsOpening: chapterIsOpening, isPreview: false) {
        case .finishOpeningPlayFirst(let node): phase = .finishPlayFirst(currentNodeID: node)
        case .readyToDepart(let chapter, let version): phase = .reviewing(chapterID: chapter, expectedVersion: version)
        case .notOpening, .versionUnavailable: break
        }
    }
    public func cancelReview() { if case .reviewing = phase { phase = .idle } }

    public func confirm() async {
        guard let client, case .reviewing(let chapter, let version) = phase else { return }
        generation &+= 1
        phase = .submitting
        do {
            try await client.complete(chapterID: chapter, expectedVersion: version)
            phase = .unknown
            await load()
        } catch PlayExperienceError.rejected(let code, let message) {
            let conflict = Self.isRouteConflict(code: code, message: message)
            phase = .rejected(message: message, conflict: conflict)
            if conflict { let rejected = phase; await load(); if phase == .idle { phase = rejected } }
        } catch PlayExperienceError.disabled {
            phase = .disabled
        } catch {
            phase = .unknown
            await load()
        }
    }

    /// Re-read after an unknown result. Never resubmits.
    public func readBack() async {
        guard phase == .unknown else { return }
        await load()
    }

    private var isFinishPlayFirst: Bool { if case .finishPlayFirst = phase { return true }; return false }
    private var isRejected: Bool { if case .rejected = phase { return true }; return false }

    /// `utils/play-route-state.js isRouteConflict`.
    public static func isRouteConflict(code: Int, message: String?) -> Bool {
        if code == 409 { return true }
        let text = message ?? ""
        return text.range(of: "(?:路线|route).*(?:冲突|已更新|过期)|(?:版本|version).*(?:冲突|已更新|过期)", options: [.regularExpression, .caseInsensitive]) != nil
    }
}
