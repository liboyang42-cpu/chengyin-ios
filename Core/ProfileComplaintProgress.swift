import Foundation
import Observation

/// Read-only rows from `POST /api/coop/complaint/mine`. Only the fields the
/// mini-program renders are kept; responsibility, deductions and refunds are never inferred.
public struct ProfileComplaintProgressRow: Equatable, Identifiable {
    public let id: Int
    public let topicName: String?
    public let statusText: String?
    public let reason: String?
    public let handleNote: String?
    /// One row without a positive id rejects the whole array, matching the source page.
    public static func decode(_ value: CoopFlowJSON) throws -> [Self] {
        guard let rows = value.rows else { throw APIError.malformedResponse }
        return try rows.map { row in
            guard case .object = row, let id = row["id"].integer, id > 0 else { throw APIError.malformedResponse }
            func text(_ key: String) -> String? {
                guard case .string(let raw) = row[key] else { return nil }
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            return Self(id: id, topicName: text("topicName"), statusText: text("statusText"),
                        reason: text("reason"), handleNote: text("handleNote"))
        }
    }
}

/// 400/401/403/422 hide progress and show the source's access message.
/// Other failures keep the last rows silently, as the source page does.
public enum ProfileComplaintProgressIssue: Equatable {
    case signIn
    case denied(String?)
    public init?(_ error: Error) {
        if error as? APIError == .unauthorized { self = .signIn; return }
        if case .server(let code, let message)? = error as? CoopFlowFailure {
            if code == 401 { self = .signIn; return }
            if [400, 403, 422].contains(code) {
                let trimmed = message?.trimmingCharacters(in: .whitespacesAndNewlines)
                self = .denied(trimmed?.isEmpty == false ? trimmed : nil); return
            }
        }
        if error as? CoopFlowFailure == .permission { self = .denied(nil); return }
        return nil
    }
    public var detailKey: String {
        switch self {
        case .signIn: return "profile.complaintProgress.signIn"
        case .denied: return "profile.complaintProgress.denied"
        }
    }
}

@MainActor @Observable public final class ProfileComplaintProgressController {
    public private(set) var rows: [ProfileComplaintProgressRow] = []
    public private(set) var issue: ProfileComplaintProgressIssue?
    public private(set) var isLoading = false
    private let reader: any CoopFlowReading
    private let owner: CoopFlowSession?
    private let isCurrent: @MainActor () -> Bool
    private var active = true
    private var generation: UInt64 = 0
    public init(reader: any CoopFlowReading, isCurrent: @escaping @MainActor () -> Bool) {
        self.reader = reader; owner = reader.session; self.isCurrent = isCurrent
    }
    public var contextMatches: Bool { active && owner != nil && reader.session == owner && isCurrent() }
    public func retire() {
        active = false; generation &+= 1; isLoading = false
        rows = []; issue = nil
    }
    public func load() async {
        guard contextMatches else {
            if owner == nil && active { rows = []; issue = .signIn } else { retire() }
            return
        }
        generation &+= 1; let stamp = generation
        isLoading = true; issue = nil
        defer { if generation == stamp { isLoading = false } }
        func current() -> Bool { contextMatches && generation == stamp && !Task.isCancelled }
        do {
            try Task.checkCancellation()
            guard current() else { return }
            let value = try await reader.read(.complaintProgress, isCurrent: { current() })
            guard current() else { return }
            rows = try ProfileComplaintProgressRow.decode(value)
        } catch {
            guard current() else { return }
            if let failure = ProfileComplaintProgressIssue(error) { rows = []; issue = failure }
        }
    }
}
