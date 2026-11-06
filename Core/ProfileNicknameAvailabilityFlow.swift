import Foundation
import Observation

public enum ProfileNicknameAvailabilityState: Equatable {
    case unchecked, checking, available, taken, invalid(String), unavailable
    public var message: String? {
        switch self {
        case .unchecked: return nil
        case .checking: return "nickname.read.checking"
        case .available: return "nickname.read.available"
        case .taken: return "nickname.read.taken"
        case .invalid(let text): return text
        case .unavailable: return "nickname.read.unavailable"
        }
    }
}

/// One ephemeral editor lifetime. A stale response never sets input or another editor's
/// candidates. Queries can fail without creating a business UNKNOWN write or save lock.
@MainActor @Observable public final class ProfileNicknameAvailabilityFlow {
    public let reader: (any ProfileNicknameAvailabilityReading)?
    private let expectedIdentity: ProfileReadIdentity?
    private let expectedViewerRevision: UInt64?
    private var source: UUID?
    private var action = UUID()
    private var owner: ProfileReadIdentity?
    private var viewer: UInt64?
    private var active = false
    private var generation: UInt64 = 0
    private var value = ""
    private var checkedState: ProfileNicknameAvailabilityState = .unchecked
    private var offered: [String] = []
    private var cursor: Int?
    private var suggesting = false
    private var suggestionError: String?
    public init(reader: (any ProfileNicknameAvailabilityReading)?,
                expectedIdentity: ProfileReadIdentity? = nil, expectedViewerRevision: UInt64? = nil) {
        self.reader = reader; self.expectedIdentity = expectedIdentity; self.expectedViewerRevision = expectedViewerRevision
    }
    private var sameOwner: Bool {
        active && reader?.isConfigured == true && source != nil && reader?.sourceRevision == source && owner != nil && reader?.identity == owner && reader?.viewerRevision == viewer &&
            (expectedIdentity == nil || (owner == expectedIdentity && viewer == expectedViewerRevision))
    }
    public func matchesInput(_ input: String) -> Bool { sameOwner && value.utf8.elementsEqual(ProfileNicknameRules.normalize(input).utf8) }
    public var actionID: UUID? { sameOwner ? action : nil }
    public var state: ProfileNicknameAvailabilityState { sameOwner ? checkedState : .unchecked }
    public var candidates: [String] { sameOwner && reader?.isConfigured == true ? offered : [] }
    public var isSuggesting: Bool { sameOwner && suggesting }
    public var suggestionsMessage: String? { sameOwner ? suggestionError : nil }
    public var canSuggest: Bool { sameOwner && reader?.isConfigured == true && !suggesting && checkedState == .taken }
    public func activate() { active = true }
    public func leave() {
        active = false; source = nil; action = UUID(); generation &+= 1; owner = nil; viewer = nil; value = ""
        offered = []; cursor = nil; suggesting = false; suggestionError = nil; checkedState = .unchecked
    }
    public func setInput(_ raw: String, original: String? = nil) {
        generation &+= 1; action = UUID(); value = ProfileNicknameRules.normalize(raw)
        owner = reader?.identity; viewer = reader?.viewerRevision; source = reader?.sourceRevision
        offered = []; cursor = nil; suggesting = false; suggestionError = nil
        if let issue = ProfileNicknameRules.issue(value) { checkedState = .invalid(issue) }
        else if let original, value.utf8.elementsEqual(ProfileNicknameRules.normalize(original).utf8) { checkedState = .unchecked }
        else { checkedState = .checking }
    }
    private func current(_ stamp: UInt64) -> Bool { !Task.isCancelled && generation == stamp && sameOwner }
    public func check(debounce: Bool = true) async {
        let stamp = generation, input = value
        guard active, ProfileNicknameRules.issue(input) == nil else { return }
        if checkedState == .unchecked { return }
        checkedState = .checking
        if debounce {
            do { try await Task.sleep(nanoseconds: 400_000_000) } catch { return }
        }
        guard current(stamp) else { return }
        guard let reader, reader.isConfigured else { checkedState = .unavailable; return }
        do {
            let result = try await reader.check(input)
            guard current(stamp) else { return }
            switch result {
            case .available: checkedState = .available
            case .taken: checkedState = .taken
            case .invalid: checkedState = .invalid("nickname.read.invalid")
            }
            if result == .taken, let actionID { await loadSuggestions(action: actionID) }
        } catch { if current(stamp) { checkedState = .unavailable } }
    }
    public func retryCheck(action expected: UUID) async {
        guard actionID == expected else { return }
        setInput(value); await check(debounce: false)
    }
    public func loadSuggestions(action expected: UUID) async {
        guard actionID == expected, canSuggest, let reader else { return }
        action = UUID()
        let stamp = generation, base = value
        suggesting = true; offered = []; suggestionError = nil
        defer { if generation == stamp { suggesting = false; action = UUID() } }
        var batch: [String] = []
        do {
            for _ in 0..<3 {
                let suggestion = try await reader.suggest(base, cursor: cursor)
                guard current(stamp), reader.isConfigured else { return }
                cursor = suggestion.cursor
                if !batch.contains(where: { $0.utf8.elementsEqual(suggestion.nickname.utf8) }) { batch.append(suggestion.nickname) }
                if cursor == nil { break }
            }
            guard current(stamp) else { return }
            offered = batch
            if batch.isEmpty { suggestionError = "nickname.read.noSuggestions" }
        } catch {
            guard current(stamp) else { return }
            offered = batch
            if batch.isEmpty {
                switch error {
                case ProfileNicknameSuggestionFailure.exhausted: suggestionError = "nickname.read.exhausted"
                case ProfileNicknameSuggestionFailure.invalid: suggestionError = "nickname.read.suggestionInvalid"
                default: suggestionError = "nickname.read.suggestionRetry"
                }
            }
        }
    }
    /// Only this explicit user action returns a candidate for staging. Never called
    /// from check/suggest completion. Membership is exact to the visible current batch.
    public func select(_ nickname: String, action expected: UUID) -> String? {
        guard actionID == expected, sameOwner, reader?.isConfigured == true, !suggesting,
              offered.contains(where: { $0.utf8.elementsEqual(nickname.utf8) }) else { return nil }
        generation &+= 1; action = UUID(); value = nickname; offered = []; cursor = nil; suggestionError = nil
        checkedState = .available; return nickname
    }
}
