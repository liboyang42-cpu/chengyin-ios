import Foundation

/// Values mirror P045's AI_IDEA_CHIPS. Selecting a chip only replaces the local idea.
public enum ClubAIDesignIdea: String, CaseIterable, Identifiable {
    case jingan, bund, suzhouRiver
    public var id: String { rawValue }
    public var text: String {
        switch self {
        case .jingan: return "静安 情侣 夜间 Citywalk 90分钟"
        case .bund: return "外滩 亲子 半天 城市打卡"
        case .suzhouRiver: return "苏州河 摄影 徒步 2小时"
        }
    }
}

public struct ClubAIDesignFeedbackContext: Equatable {
    public let clubID: Int
    public let session: PublishingSession?
    public let operationID: UUID
    public let resultGeneration: Int?
    public let promoCopy: String
    public init(clubID: Int, session: PublishingSession?, operationID: UUID, resultGeneration: Int? = nil, promoCopy: String = "") {
        self.clubID = clubID; self.session = session; self.operationID = operationID
        self.resultGeneration = resultGeneration; self.promoCopy = promoCopy
    }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.clubID == rhs.clubID && lhs.session == rhs.session && lhs.operationID == rhs.operationID &&
        lhs.resultGeneration == rhs.resultGeneration && lhs.promoCopy.utf8.elementsEqual(rhs.promoCopy.utf8)
    }
    public var canInteract: Bool { clubID > 0 && session != nil }
    public var canCopy: Bool { canInteract && resultGeneration != nil && !promoCopy.isEmpty }
}

/// Local interaction leases do not authorize AI requests or project adoption.
/// A rebind or visibility loss retires old closures even if the same context returns.
public struct ClubAIDesignFeedbackState {
    public enum Phase: Equatable { case idle, copying, copied, failed }
    public struct Permit: Equatable {
        fileprivate let lifetime: UUID
        fileprivate let context: ClubAIDesignFeedbackContext
    }
    public struct CopyAttempt: Equatable {
        fileprivate let id: UUID
        fileprivate let permit: Permit
        public var text: String { permit.context.promoCopy }
    }
    private var context: ClubAIDesignFeedbackContext?
    private var lifetime = UUID()
    private var visible = false
    private var pending: CopyAttempt?
    public private(set) var phase: Phase = .idle
    public init() {}
    public mutating func bind(_ value: ClubAIDesignFeedbackContext) {
        guard context != value else { return }
        context = value; retire()
    }
    public mutating func appear() { visible = true }
    public mutating func leave() { visible = false; retire() }
    private mutating func retire() { lifetime = UUID(); pending = nil; phase = .idle }
    public func permit(_ value: ClubAIDesignFeedbackContext, generating: Bool) -> Permit? {
        guard visible, !generating, value.canInteract, context == value else { return nil }
        return Permit(lifetime: lifetime, context: value)
    }
    public func accepts(_ permit: Permit, current: ClubAIDesignFeedbackContext, generating: Bool) -> Bool {
        self.permit(current, generating: generating) == permit
    }
    public func choose(_ idea: ClubAIDesignIdea, permit: Permit, current: ClubAIDesignFeedbackContext, generating: Bool) -> String? {
        guard accepts(permit, current: current, generating: generating) else { return nil }
        return idea.text
    }
    public mutating func beginCopy(_ permit: Permit, current: ClubAIDesignFeedbackContext, generating: Bool) -> CopyAttempt? {
        guard accepts(permit, current: current, generating: generating), current.canCopy, pending == nil else { return nil }
        let attempt = CopyAttempt(id: UUID(), permit: permit); pending = attempt; phase = .copying
        return attempt
    }
    @discardableResult public mutating func completeCopy(_ attempt: CopyAttempt, succeeded: Bool, current: ClubAIDesignFeedbackContext?, generating: Bool) -> Bool {
        guard pending == attempt, let current, accepts(attempt.permit, current: current, generating: generating) else {
            if pending == attempt { retire() }
            return false
        }
        pending = nil; phase = succeeded ? .copied : .failed; return true
    }
}
