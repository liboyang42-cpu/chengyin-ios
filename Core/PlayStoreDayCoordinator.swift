import Foundation
import Observation

/// Host-supplied on-site evidence. Production supplies none: no camera or scanner runs here.
@MainActor public protocol PlayStoreDayEvidenceSource: AnyObject {
    func storeCode() -> String?
    func proofPictureURL() -> String?
}
public enum PlayStoreDayPhase: Equatable { case loading, loaded, notFound, failed, signedOut, unavailable }
/// Feedback line (source `feedback`). `server` carries plain backend text verbatim.
public enum PlayStoreDayNotice: Equatable {
    case arrivalRecorded, photoRecorded, proofFailed, proofLanded, proofNotLanded, arriveFirst
    case preferenceUnreachable, handoffFailed, noCoordinates, noCode, noPhoto, deviceUnavailable, writesUnavailable
    case needTicket, merchantUnconfirmed, verifyOpenFailed, consentRevoked, consentDeclined
    case consentWriteFailed, consentUnconfirmed, consentWritesUnavailable
    case server(String)
}
/// Status pill above the CTA (source `degradedMessage`).
public enum PlayStoreDayDegraded: Equatable { case quantityUnavailable, checking, stillUnknown }
public enum PlayStoreDayGameError: Equatable {
    case chooseOption, writeAnswer, wrong(String?), checking, stillUnknown, notRecorded
}
public struct PlayStoreDayGame: Equatable {
    public var show = false
    public var answer = ""
    public var choice: String?
    public var submitting = false
    public var result: PlayStoreDayAnswerResult?
    public var error: PlayStoreDayGameError?
    public var receipt: PlayStoreDayReceipt = .ready
    public var done: Bool { result != nil }
    public init() {}
}
public enum PlayStoreDayPreparedProof: Equatable { case scan(code: String), photo(url: String) }

@available(macOS 14.0, *)
@MainActor @Observable public final class PlayStoreDayCoordinator {
    public let nodeID: Int
    public let scope: PlaySessionScope
    public let registrationID: Int
    public let justScanned: Bool
    public private(set) var phase: PlayStoreDayPhase = .loading
    public private(set) var node: PlayStoreDayNode?
    public private(set) var receipt: PlayStoreDayReceipt = .ready
    public private(set) var busy = false
    public private(set) var notice: PlayStoreDayNotice?
    public private(set) var degraded: PlayStoreDayDegraded?
    public private(set) var consent: PlayStoreDayConsentState = .unknown
    public private(set) var consentBusy = false
    public var consentPromptVisible = false
    public var game = PlayStoreDayGame()
    public var taskVisible = false
    public var preparedProof: PlayStoreDayPreparedProof?
    private let service: PlayStoreDayService?
    private let evidence: (any PlayStoreDayEvidenceSource)?
    private let handoff: (@MainActor (PlayStoreDayNode) -> Bool)?
    private let presentVerification: (@MainActor () -> Bool)?
    private let onNodeChanged: (@MainActor (PlayStoreDayNode) -> Void)?
    private let now: () -> Date
    @ObservationIgnored private var loadedSession: PlayStoreDaySession?
    @ObservationIgnored private var unknownProofAutoPopup = false
    @ObservationIgnored private var preparedConsent: (event: ComplianceEvent, requestID: String)?
    public private(set) var dismissRequested = false

    public init(nodeID: Int, scope: PlaySessionScope, registrationID: Int, justScanned: Bool, service: PlayStoreDayService?,
                evidence: (any PlayStoreDayEvidenceSource)? = nil, handoff: (@MainActor (PlayStoreDayNode) -> Bool)? = nil,
                presentVerification: (@MainActor () -> Bool)? = nil, onNodeChanged: (@MainActor (PlayStoreDayNode) -> Void)? = nil, now: @escaping () -> Date = Date.init) {
        self.nodeID = nodeID; self.scope = scope; self.registrationID = max(0, registrationID); self.justScanned = justScanned
        self.service = service; self.evidence = evidence; self.handoff = handoff; self.presentVerification = presentVerification
        self.onNodeChanged = onNodeChanged; self.now = now
    }
    public var primaryAction: PlayStoreDayPrimaryAction? { node.map { PlayStoreDayPrimaryAction.resolve($0, receipt: receipt) } }
    public var canWriteProof: Bool { service?.permitsProofWrites == true }
    private var current: Bool { loadedSession != nil && service?.session == loadedSession }
    public func openText(nowMinutes: Int) -> PlayStoreDayOpenText? {
        node.flatMap { PlayStoreDayOpenText.resolve(openStatus: $0.openStatus, businessTime: $0.businessTime, nowMinutes: nowMinutes) }
    }

    // MARK: Load
    public func load() async {
        guard let service, service.permitsReads else { phase = .unavailable; return }
        guard scope.isValid, nodeID > 0 else { phase = .notFound; return }
        phase = .loading
        let session = service.session
        do {
            guard let fresh = try await service.node(scope: scope, nodeID: nodeID) else { node = nil; phase = .notFound; return }
            guard service.session == session else { return }
            loadedSession = session; node = fresh; phase = .loaded
            degraded = fresh.quantityUnavailable ? .quantityUnavailable : nil
            if justScanned { maybeAutoPopup() }
            if fresh.merchantID != nil { await loadConsent() }
        } catch PlayStoreDayFailure.signedOut { node = nil; phase = .signedOut }
        catch PlayStoreDayFailure.staleSession { node = nil; phase = .signedOut }
        catch { node = nil; phase = .failed }
    }
    public func invalidate() { loadedSession = nil; node = nil; phase = .signedOut; game = .init(); taskVisible = false; preparedProof = nil; consentPromptVisible = false }

    // MARK: Experience layer
    public func maybeAutoPopup() {
        guard let node else { return }
        switch PlayStoreDayPopup.resolve(node) {
        case .none: break
        case .advancedHandoff: handOff(node) { [weak self] in self?.openTaskCard() }
        case .preferenceHandoff: handOff(node) { [weak self] in self?.notice = .preferenceUnreachable }
        case .quiz: openGame()
        case .taskCard: openTaskCard()
        }
    }
    public func openGame() {
        guard let node else { return }
        guard node.arrived else { notice = .arriveFirst; return }
        if node.isPreferenceGame { handOff(node) { [weak self] in self?.notice = .preferenceUnreachable }; return }
        guard node.question != nil else { openTaskCard(); return }
        // An unknown answer keeps its lock; reopening must never reset it.
        if game.receipt == .unknown { game.show = true; return }
        game = .init(); game.show = true
    }
    private func handOff(_ node: PlayStoreDayNode, unreachable: () -> Void) {
        guard node.arrived else { notice = .arriveFirst; return }
        guard let handoff else { unreachable(); return }
        if handoff(node) { dismissRequested = true } else { notice = .handoffFailed }
    }
    public func closeGame() {
        let wasDone = game.done
        game.show = false
        if wasDone, node?.selfReported == false { openTaskCard() }
    }
    public func pick(_ key: String) { game.choice = key; game.error = nil }
    public func setAnswer(_ text: String) { game.answer = text; game.error = nil }
    public func openTaskCard() { taskVisible = true }
    public func closeTaskCard() { taskVisible = false }
    public func closeSheets() { game.show = false; taskVisible = false }
    public func taskGoPhoto() { guard !busy else { return }; closeTaskCard(); preparePhoto() }

    public func submitGame() async {
        guard let node, current, !game.submitting, !game.done, game.receipt != .unknown, let service else { return }
        let choiceMode = node.validationMethod == 3
        let answer = choiceMode ? (game.choice ?? "") : game.answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty else { game.error = choiceMode ? .chooseOption : .writeAnswer; return }
        guard service.permitsProofWrites else { notice = .writesUnavailable; return }
        game.submitting = true; game.error = nil; game.receipt = .submitting
        switch await service.answer(scope: scope, nodeID: node.id, answer: answer) {
        case .unknown: await resolveGameUnknown()
        case .rejected(let message): game.submitting = false; game.receipt = .failed; game.error = .wrong(message)
        case .confirmed(let message, let data):
            game.submitting = false; game.receipt = .confirmed; game.error = nil
            game.result = PlayStoreDayAnswerResult(message: message, data: data)
        }
    }
    /// Unknown answer: only /api/play/nodes gameDone decides; the answer is never re-sent.
    public func resolveGameUnknown() async {
        game.submitting = true; game.receipt = .unknown; game.error = .checking
        guard let fresh = await readback() else { game.error = .stillUnknown; return }
        if fresh.gameDone {
            game.submitting = false; game.receipt = .confirmed; game.error = nil; game.result = .readbackRecorded
        } else { game.submitting = false; game.receipt = .failed; game.error = .notRecorded }
    }
    public func retryGameReadback() async { guard game.receipt == .unknown else { return }; await resolveGameUnknown() }

    // MARK: Proof
    public func prepareScan() {
        guard !busy, node != nil else { return }
        guard canWriteProof else { notice = .writesUnavailable; return }
        guard let evidence else { notice = .deviceUnavailable; return }
        guard let code = evidence.storeCode()?.trimmingCharacters(in: .whitespacesAndNewlines), !code.isEmpty else { notice = .noCode; return }
        preparedProof = .scan(code: code)
    }
    public func preparePhoto() {
        guard !busy, node != nil else { return }
        guard canWriteProof else { notice = .writesUnavailable; return }
        guard let evidence else { notice = .deviceUnavailable; return }
        guard let url = evidence.proofPictureURL(), !url.isEmpty else { notice = .noPhoto; return }
        preparedProof = .photo(url: url)
    }
    public func cancelPreparedProof() { preparedProof = nil }
    /// Sends exactly the evidence the user confirmed; a stale or replaced preparation is ignored.
    public func submitProof(_ prepared: PlayStoreDayPreparedProof) async {
        guard preparedProof == prepared, let node, let service, current, !busy else { return }
        preparedProof = nil
        busy = true; notice = nil; degraded = nil; receipt = .submitting
        let outcome: PlayStoreDayWriteOutcome
        let success: PlayStoreDayNotice, autoPopup: Bool
        switch prepared {
        case .scan(let code): outcome = await service.checkin(scope: scope, code: code); success = .arrivalRecorded; autoPopup = true
        case .photo(let url): outcome = await service.photo(scope: scope, nodeID: node.id, pictureURL: url); success = .photoRecorded; autoPopup = false
        }
        switch outcome {
        case .unknown: await resolveProofUnknown(autoPopup: autoPopup)
        case .rejected(let message):
            busy = false; receipt = .failed; degraded = nil
            notice = message.flatMap { $0.isEmpty ? nil : .server($0) } ?? .proofFailed
        case .confirmed(_, let data):
            let merged = node.merging(data)
            self.node = merged; busy = false; receipt = .confirmed; notice = success
            if autoPopup { maybeAutoPopup() }
            onNodeChanged?(merged)
        }
    }
    /// Unknown proof stays locked until the authoritative nodes read shows whether it landed.
    public func resolveProofUnknown(autoPopup: Bool? = nil) async {
        if let autoPopup { unknownProofAutoPopup = autoPopup }
        busy = true; receipt = .unknown; notice = nil; degraded = .checking
        let before = node
        guard let fresh = await readback() else { degraded = .stillUnknown; return }
        let landed = before?.proofLanded(after: fresh) ?? false
        node = fresh; busy = false; receipt = landed ? .confirmed : .failed; degraded = nil
        notice = landed ? .proofLanded : .proofNotLanded
        if landed { let carried = unknownProofAutoPopup; unknownProofAutoPopup = false; if carried { maybeAutoPopup() } }
        onNodeChanged?(fresh)
    }
    public func retryProofReadback() async { guard receipt == .unknown else { return }; await resolveProofUnknown() }
    private func readback() async -> PlayStoreDayNode? {
        guard let service, let base = node, current else { return nil }
        guard let row = try? await service.node(scope: scope, nodeID: nodeID), current else { return nil }
        return base.merging(.object(row.raw))
    }

    // MARK: Map / verification / consent
    public func mapUnavailable() { notice = .noCoordinates }
    public func openVerifyCode() {
        guard !consentBusy, let node else { return }
        guard registrationID > 0 else { notice = .needTicket; return }
        guard node.merchantID != nil else { notice = .merchantUnconfirmed; return }
        if consent != .agree { consentPromptVisible = true; return }
        showVerifyCode()
    }
    private func showVerifyCode() {
        guard let presentVerification, presentVerification() else { notice = .verifyOpenFailed; return }
    }
    public func declineConsent() { consentPromptVisible = false }
    public func agreeConsent() async {
        consentPromptVisible = false
        if await writeAndReadbackConsent(.agree) { showVerifyCode() }
    }
    public func revokeConsent() async {
        guard !consentBusy else { return }
        if await writeAndReadbackConsent(.revoke) { notice = .consentRevoked }
    }
    private func loadConsent() async {
        guard let merchantID = node?.merchantID, let service else { return }
        do { consent = PlayStoreDayConsent.state(latest: try await service.latestConsent(merchantID: merchantID), merchantID: merchantID) }
        catch { consent = .unavailable }
    }
    private func writeAndReadbackConsent(_ event: ComplianceEvent) async -> Bool {
        guard let merchantID = node?.merchantID, let service, current, !consentBusy else { return false }
        guard service.permitsConsentWrites else { notice = .consentWritesUnavailable; return false }
        // One request ID per prepared action; an unresolved retry reuses it.
        let requestID: String
        if let prepared = preparedConsent, prepared.event == event { requestID = prepared.requestID }
        else {
            guard let id = PlayStoreDayConsent.requestID(event: event, merchantID: merchantID, milliseconds: Int64(now().timeIntervalSince1970 * 1000)) else { return false }
            requestID = id; preparedConsent = (event, id)
        }
        consentBusy = true; notice = nil
        let outcome = await service.consent(merchantID: merchantID, event: event, requestID: requestID)
        if case .rejected(let message) = outcome {
            preparedConsent = nil; consentBusy = false; consent = .unavailable
            notice = message.flatMap { $0.isEmpty ? nil : .server($0) } ?? .consentWriteFailed
            return false
        }
        let readback: ComplianceConsent?
        do { readback = try await service.latestConsent(merchantID: merchantID) } catch { readback = nil }
        let matched = readback?.matches(PlayStoreDayConsent.subject(merchantID: merchantID), event: event) == true
        consentBusy = false
        consent = matched ? (event == .agree ? .agree : .revoke) : .unavailable
        if matched { preparedConsent = nil; notice = nil } else { notice = .consentUnconfirmed }
        return matched
    }
}
