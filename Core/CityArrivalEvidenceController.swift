import Foundation
import Observation

@available(macOS 14.0, *) @MainActor @Observable public final class CityArrivalEvidenceController {
    public struct Confirmation: Identifiable {
        public let id: UUID
        public let command: CityArrivalCommand
        public let player: CityArrivalPlayerSnapshot?
        public let merchant: CityArrivalMerchantSnapshot?
        public let pointTitle: String
    }
    public private(set) var player: CityArrivalPlayerSnapshot?
    public private(set) var merchant: CityArrivalMerchantSnapshot?
    public private(set) var proof: CityArrivalProof?
    public private(set) var codes: [String: String] = [:]
    public private(set) var confirmation: Confirmation?
    public private(set) var pendingRequestID: UUID?
    public private(set) var receipt: CityArrivalReceipt?
    public private(set) var busy = false
    public private(set) var messageKey = "cityArrival.status.initial"
    public let audience: CityArrivalAudience
    private let service: CityArrivalEvidenceService?
    private let journal: (any OperationPendingJournal)?
    private let unauthorized: () -> Void
    private var generation = 0
    public init(audience: CityArrivalAudience, service: CityArrivalEvidenceService?, journal: (any OperationPendingJournal)?, unauthorized: @escaping () -> Void = {}) { self.audience = audience; self.service = service; self.journal = journal; self.unauthorized = unauthorized }
    public var current: Bool { service?.transport.isCurrent() == true }
    public var canWrite: Bool { current && service?.approval.allowsWrite == true && (player?.writeApproved == true || merchant?.writeApproved == true) && !busy && pendingRequestID == nil && journal != nil }
    private var owner: String? { service.map { "city-arrival:\($0.approval.context.session.namespace):\($0.approval.context.baseURL.absoluteString):\($0.approval.context.session.accountID)" } }
    private var target: String { switch audience { case .player(let region): return "player:" + region; case .merchant(let id): return "merchant:\(id)" } }
    public func invalidate() { generation += 1; player = nil; merchant = nil; proof = nil; codes = [:]; confirmation = nil; pendingRequestID = nil; receipt = nil; busy = false; messageKey = "cityArrival.status.contextChanged" }
    public func cancelConfirmation() { confirmation = nil }
    public func load() async {
        guard !busy else { return }
        guard current, let journal, let owner else { invalidate(); messageKey = "cityArrival.status.disabled"; return }
        generation += 1; let issued = generation; busy = true; confirmation = nil; player = nil; merchant = nil; proof = nil; codes = [:]
        defer { if generation == issued { busy = false } }
        do { pendingRequestID = try journal.pending(ownerKey: owner, targetKey: target)?.operationID; try await refresh(issued); guard valid(issued) else { return }; messageKey = pendingRequestID == nil ? "cityArrival.status.ready" : "cityArrival.status.unknown" }
        catch { report(error, issued) }
    }
    private func refresh(_ issued: Int) async throws {
        guard let service else { throw CityArrivalEvidenceError.disabled }
        switch audience {
        case .player:
            let state = try await service.player(); guard valid(issued) else { return }; player = state; codes = [:]
            // Retrieve only this person's original issue receipt. Its old state never replaces the current snapshot.
            for point in state.points {
                if let challenge = point.challenge, ["ISSUED", "SUBMITTED"].contains(challenge.state) {
                    let code = try await service.code(for: challenge); guard valid(issued) else { return }; codes[challenge.id] = code
                }
            }
        case .merchant: let state = try await service.merchant(); guard valid(issued) else { return }; merchant = state
        }
    }
    public func prepareIssue(_ point: CityArrivalPoint) {
        confirmation = nil
        guard canWrite, let player, player.status == "READY", player.points.contains(point), point.canIssue, let binding = player.binding, let team = player.teamId, let version = player.teamVersion else { return }
        let id = UUID(); confirmation = .init(id: id, command: .init(id: id, binding: binding, team: team, teamVersion: version, point: point), player: player, merchant: nil, pointTitle: point.title)
    }
    public func prepareSubmit(_ point: CityArrivalPoint) {
        confirmation = nil
        guard canWrite, let player, player.status == "READY", player.points.contains(point), let challenge = point.challenge, challenge.state == "ISSUED", let code = codes[challenge.id] else { return }
        let id = UUID(); confirmation = .init(id: id, command: .init(id: id, kind: .submit, challenge: challenge, code: code), player: player, merchant: nil, pointTitle: point.title)
    }
    public func prepareReview(_ challenge: CityArrivalChallenge, confirms: Bool, code: String, reason: String) {
        confirmation = nil
        let reason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canWrite, let merchant, merchant.pending.contains(challenge), challenge.state == "SUBMITTED", !reason.isEmpty, reason.utf16.count <= 500, !confirms || CityArrivalEvidenceRoute.validCode(code) else { return }
        let id = UUID(); confirmation = .init(id: id, command: .init(id: id, kind: confirms ? .confirm : .reject, challenge: challenge, code: confirms ? code : "", reason: reason), player: nil, merchant: merchant, pointTitle: challenge.pointTitle ?? challenge.pointId)
    }
    public func confirm(_ captured: Confirmation) async {
        guard canWrite, confirmation?.id == captured.id, player == captured.player, merchant == captured.merchant, let service, let journal, let owner else { confirmation = nil; return }
        confirmation = nil; generation += 1; let issued = generation; busy = true
        defer { if generation == issued { busy = false } }
        do {
            guard try journal.pending(ownerKey: owner, targetKey: target) == nil else { messageKey = "cityArrival.status.recoverFirst"; return }
            let record = OperationPendingRecord(operationID: captured.id, ownerKey: owner, targetKey: target)
            // Journal identity only, never store the ephemeral challenge code, token or another member's identity.
            try journal.write(record); pendingRequestID = record.operationID; try await service.submit(captured.command)
        } catch { report(error, issued) }
        guard valid(issued) else { return }; busy = false; await recover()
    }
    public func recover() async {
        guard !busy, current, let service, let journal, let owner else { return }
        generation += 1; let issued = generation; busy = true; confirmation = nil
        defer { if generation == issued { busy = false } }
        do {
            guard let record = try journal.pending(ownerKey: owner, targetKey: target) else { pendingRequestID = nil; return }
            pendingRequestID = record.operationID; let value = try await service.receipt(record.operationID.uuidString); guard valid(issued) else { return }
            try journal.clear(record); pendingRequestID = nil; receipt = value; player = nil; merchant = nil; proof = nil; codes = [:]
            try await refresh(issued); guard valid(issued) else { return }
            if let original = value.evidence { let read = try await service.evidence(original.id); guard valid(issued) else { return }; proof = read }
            messageKey = value.succeeded ? "cityArrival.status.recorded" : "cityArrival.status.rejected"
        } catch { report(error, issued) }
    }
    public func readProof(_ id: String) async {
        guard !busy, current, let service, player?.points.contains(where: { $0.evidence?.id == id }) == true || receipt?.evidence?.id == id else { return }
        generation += 1; let issued = generation; busy = true; confirmation = nil; proof = nil
        defer { if generation == issued { busy = false } }
        do { let value = try await service.evidence(id); guard valid(issued) else { return }; proof = value }
        catch { report(error, issued) }
    }
    private func valid(_ issued: Int) -> Bool { generation == issued && current && !Task.isCancelled }
    private func report(_ error: Error, _ issued: Int) {
        guard generation == issued else { return }; player = nil; merchant = nil; proof = nil; codes = [:]; confirmation = nil
        if !current { receipt = nil; messageKey = "cityArrival.status.contextChanged"; return }
        if error as? APIError == .unauthorized { receipt = nil; unauthorized(); messageKey = "cityArrival.status.signedOut"; return }
        if case CityArrivalEvidenceError.server(403, _) = error { receipt = nil; messageKey = "cityArrival.status.accessWithdrawn"; return }
        messageKey = pendingRequestID == nil ? "cityArrival.status.unavailable" : "cityArrival.status.unknown"
    }
}
