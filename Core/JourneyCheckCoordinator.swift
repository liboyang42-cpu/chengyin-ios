import Foundation
import Observation

@MainActor @Observable public final class JourneyCheckCoordinator {
    public let scope: PlaySessionScope; public let topicID: Int; public let nodeID: Int
    public let roleContent: JourneyRoleViewCoordinator
    public private(set) var problem: JourneyCheckProblem?
    public private(set) var receipt: JourneyCheckReceipt?
    public private(set) var review: JourneyCheckReview?
    public private(set) var pending: JourneyCheckReview?
    public private(set) var acting = false
    public private(set) var nodeDone = false
    public private(set) var visible = false
    public private(set) var unknown = false
    public private(set) var issue: String?
    private let journal: any JourneyCheckJournal
    private let service: JourneyContentService
    private let currentSession: () -> PlayExperienceSession?
    private let unauthorized: (PlayExperienceSession) -> Void
    private var identity: PlayExperienceSession?
    private var generation: UInt64 = 0
    private var probed = false
    public init(scope: PlaySessionScope, topicID: Int, nodeID: Int, service: JourneyContentService,
                journal: (any JourneyCheckJournal)? = nil, currentSession: @escaping () -> PlayExperienceSession?, onUnauthorized: @escaping (PlayExperienceSession) -> Void = { _ in }) {
        self.scope = scope; self.topicID = topicID; self.nodeID = nodeID; self.service = service
        roleContent = JourneyRoleViewCoordinator(scope: scope, topicID: topicID, nodeID: nodeID, service: service, currentSession: currentSession, onUnauthorized: onUnauthorized)
        self.journal = journal ?? JourneyMemoryCheckJournal(); self.currentSession = currentSession; unauthorized = onUnauthorized; identity = currentSession()
    }
    public var canRecover: Bool { unknown && pending != nil && !acting && available }
    public var available: Bool { service.checksEnabled && !nodeDone && currentSession() != nil }
    public func synchronize() {
        roleContent.synchronize()
        guard identity != currentSession() else { return }
        generation &+= 1; identity = currentSession(); problem = nil; receipt = nil
        review = nil; pending = nil; visible = false; unknown = false; acting = false; probed = false; issue = nil
    }
    public func updateNodeDone(_ done: Bool) {
        nodeDone = done
        if done { visible = false; review = nil }
    }
    public func probe(nodeDone: Bool) async {
        synchronize(); updateNodeDone(nodeDone)
        guard !nodeDone, !probed, !acting, !unknown, scope.isValid, topicID > 0, nodeID > 0,
              let session = identity else { return }
        if case .topic(let id) = scope, id != topicID { return }
        probed = true; let stamp = generation
        do {
            let result = try await service.encounter(topicID: topicID, nodeID: nodeID, token: session.token)
            guard currentSession() == session, generation == stamp else { synchronize(); return }
            problem = result; visible = result != nil
            if let result {
                do {
                    if let checkID = try journal.pending(session: session, scope: scope, topicID: topicID, nodeID: nodeID) {
                        unknown = true
                        if checkID == result.checkID {
                            pending = JourneyCheckReview(session: session, topicID: topicID, nodeID: nodeID, checkID: checkID, action: .settle, receipt: nil)
                        }
                    }
                } catch { unknown = true } // Corrupt/unavailable journal must not enable rolls.
            }
        } catch {
            // Exactly one silent optional probe; never block, retry, or replace main task UI.
            guard currentSession() == session, generation == stamp else { synchronize(); return }
            if (error as? PlayExperienceError) == .unauthorized { unauthorized(session); synchronize() }
        }
    }
    public func reopen() { synchronize(); visible = problem != nil && !nodeDone }
    public func close() { visible = false; review = nil } // Pending outcome survives dismissal.
    public func prepare(_ action: JourneyCheckAction, recoverUnknown: Bool = false) throws {
        synchronize()
        guard available, !acting, let session = identity, let problem else { throw PlayExperienceError.disabled }
        if unknown {
            // Ambiguous rolls are never replayed. Explicit review of exact settle reconciles
            // the source-idempotent receipt endpoint, and may settle an un-settled check.
            guard recoverUnknown, action == .settle, pending != nil else { throw PlayExperienceError.unknownResult }
        } else {
            switch action {
            case .roll: guard receipt == nil else { throw PlayExperienceError.invalidAction }
            case .reroll: guard receipt?.canReroll == true else { throw PlayExperienceError.invalidAction }
            case .settle: guard let receipt, !receipt.settled else { throw PlayExperienceError.invalidAction }
            }
        }
        review = JourneyCheckReview(session: session, topicID: topicID, nodeID: nodeID,
                                    checkID: problem.checkID, action: action, receipt: receipt)
    }
    public func cancelReview() { review = nil }
    public func confirm(_ approved: JourneyCheckReview) async {
        synchronize()
        guard available, review == approved, approved.session == identity, !acting,
              approved.topicID == topicID, approved.nodeID == nodeID,
              approved.checkID == problem?.checkID, approved.receipt == receipt else { return }
        do { try journal.save(checkID: approved.checkID, session: approved.session, scope: scope, topicID: topicID, nodeID: nodeID) }
        catch { unknown = true; review = nil; return }
        review = nil; pending = approved; acting = true; issue = nil
        let stamp = generation
        do {
            var result: JourneyCheckReceipt
            do { result = try await service.act(approved) }
            catch PlayExperienceError.rejected(_, let message) where approved.action == .roll && (message?.contains("已结算") == true) {
                guard currentSession() == approved.session, generation == stamp else { synchronize(); return }
                // Source recovery is settle itself, using the identical topic/node/check.
                let recovery = JourneyCheckReview(session: approved.session, topicID: topicID, nodeID: nodeID,
                    checkID: approved.checkID, action: .settle, receipt: receipt)
                result = try await service.act(recovery)
                guard result.settled else { throw PlayExperienceError.malformed }
            }
            guard currentSession() == approved.session, generation == stamp else { synchronize(); return }
            guard approved.action != .settle || result.settled else { throw PlayExperienceError.malformed }
            try journal.save(checkID: nil, session: approved.session, scope: scope, topicID: topicID, nodeID: nodeID)
            receipt = result; acting = false; pending = nil; unknown = false
        } catch {
            guard currentSession() == approved.session, generation == stamp else { synchronize(); return }
            acting = false
            if case PlayExperienceError.rejected(_, let message) = error {
                issue = message
                if !unknown {
                    do { try journal.save(checkID: nil, session: approved.session, scope: scope, topicID: topicID, nodeID: nodeID); pending = nil }
                    catch { unknown = true }
                } // Unknown recovery rejection does not unlock a roll.
            } else if (error as? PlayExperienceError) == .unauthorized {
                unknown = true; unauthorized(approved.session); synchronize()
            } else if (error as? PlayExperienceError) == .disabled {
                pending = nil
            } else {
                unknown = true // Cancellation, malformed success and transport loss are not rejection.
            }
        }
    }
}
