import Foundation
import Observation

/// Only the server's complaint selector may supply these IDs. Order/registration IDs
/// are deliberately not accepted as a fallback and no eligibility is inferred locally.
public struct ProfileComplaintTopic: Equatable, Identifiable {
    public let id: Int
    public let name: String?
    public static func decode(_ value: CoopFlowJSON) throws -> [Self] {
        guard let rows = value.rows else { throw APIError.malformedResponse }
        var seen = Set<Int>()
        return try rows.map { row in
            guard case .object = row, let id = row["topicId"].integer,
                  id > 0, seen.insert(id).inserted else { throw APIError.malformedResponse }
            let name: String?
            switch row["topicName"] {
            case .null: name = nil
            case .string(let raw):
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                name = trimmed.isEmpty ? nil : trimmed
            default: throw APIError.malformedResponse
            }
            return Self(id: id, name: name)
        }
    }
}

public enum ProfileComplaintKind: String, CaseIterable, Identifiable {
    case service, fees, safety, advertising, other
    public var id: String { rawValue }
    public var titleKey: String { "profile.complaint.kind." + rawValue }
    /// Source text is part of the server reason contract, independent of UI language.
    public var sourceLabel: String {
        switch self {
        case .service: return "服务与履约"
        case .fees: return "费用与退款"
        case .safety: return "安全与纠纷"
        case .advertising: return "虚假宣传"
        case .other: return "其他"
        }
    }
}
public enum ProfileComplaintValidation: String, Equatable {
    case topic, reasonShort, reasonLong, contactLong
    public var titleKey: String { "profile.complaint.validation." + rawValue }
}
public struct ProfileComplaintDraft: Equatable {
    public var topicID: Int?
    public var kind: ProfileComplaintKind?
    public var reason = ""
    public var contact = ""
    public init() {}
    /// ECMAScript trim set used by the pinned Mini, including BOM but not U+0085.
    private static let trimSet = CharacterSet(charactersIn: "\u{0009}\u{000A}\u{000B}\u{000C}\u{000D}\u{0020}\u{00A0}\u{1680}\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}\u{2006}\u{2007}\u{2008}\u{2009}\u{200A}\u{2028}\u{2029}\u{202F}\u{205F}\u{3000}\u{FEFF}")
    private static func trimmed(_ value: String) -> String { value.trimmingCharacters(in: trimSet) }
    public func validation(topics: [ProfileComplaintTopic]) -> ProfileComplaintValidation? {
        guard let topicID, topics.contains(where: { $0.id == topicID }) else { return .topic }
        // JS String.length counts UTF-16 units. Do not use Swift grapheme count here.
        guard Self.trimmed(reason).utf16.count >= 5 else { return .reasonShort }
        guard reason.utf16.count <= 500 else { return .reasonLong }
        guard contact.utf16.count <= 50 else { return .contactLong }
        return nil
    }
    public func review(topics: [ProfileComplaintTopic]) -> ProfileComplaintReview? {
        guard validation(topics: topics) == nil,
              let topic = topics.first(where: { $0.id == topicID }) else { return nil }
        var text = Self.trimmed(reason)
        if let kind { text = "【" + kind.sourceLabel + "】" + text }
        let contact = Self.trimmed(contact)
        if !contact.isEmpty { text += "\n联系方式：" + contact }
        return .init(topic: topic, reason: text)
    }
}
/// Local, ephemeral review only. Not a request, receipt, submission, eligibility grant,
/// or persistent case. No dispatcher or production writer is exposed by this feature.
public struct ProfileComplaintReview: Equatable {
    public let topic: ProfileComplaintTopic
    public let reason: String
}
public enum ProfileComplaintReadIssue: String, Equatable {
    case failed, signIn, unavailable
    public var titleKey: String { "profile.complaint.read." + rawValue }
    public init(_ error: Error) {
        if error as? APIError == .unauthorized { self = .signIn }
        else if error as? APIError == .notConfigured { self = .unavailable }
        else { self = .failed }
    }
}

@MainActor @Observable public final class ProfileComplaintPreparationController {
    public private(set) var topics: [ProfileComplaintTopic]?
    public private(set) var issue: ProfileComplaintReadIssue?
    public private(set) var isNetworkFailure = false
    public private(set) var isLoading = false
    public private(set) var draft = ProfileComplaintDraft()
    public private(set) var review: ProfileComplaintReview?
    public private(set) var validation: ProfileComplaintValidation?
    private let reader: any CoopFlowReading
    private let owner: CoopFlowSession?
    private let isCurrent: @MainActor () -> Bool
    private var active = true
    private var generation: UInt64 = 0
    public init(reader: any CoopFlowReading, isCurrent: @escaping @MainActor () -> Bool) {
        self.reader = reader; owner = reader.session; self.isCurrent = isCurrent
    }
    public var contextMatches: Bool { active && owner != nil && reader.session == owner && isCurrent() }
    public var canEdit: Bool { contextMatches && topics?.isEmpty == false && !isLoading && issue == nil && review == nil }
    public var issueSourceSubtitle: String? {
        guard let issue else { return nil }
        return ProfileComplaintTopicLoadFailureCopy.sourceSubtitle(issue: issue, isNetworkError: isNetworkFailure)
    }
    public func change(_ update: (inout ProfileComplaintDraft) -> Void) {
        guard contextMatches else { retire(); return }
        guard canEdit else { return }
        update(&draft); validation = nil
    }
    @discardableResult public func beginReview() -> Bool {
        guard contextMatches else { retire(); return false }
        guard canEdit, let topics else { return false }
        validation = draft.validation(topics: topics)
        review = draft.review(topics: topics)
        return review != nil
    }
    public func continueEditing() {
        guard contextMatches else { retire(); return }
        review = nil
    }
    public func retire() {
        active = false; generation &+= 1; isLoading = false
        topics = nil; issue = nil; isNetworkFailure = false; draft = .init(); review = nil; validation = nil
    }
    public func load() async {
        guard contextMatches else { retire(); return }
        guard !isLoading, review == nil else { return }
        generation &+= 1; let stamp = generation
        isLoading = true; issue = nil; isNetworkFailure = false; validation = nil
        defer { if generation == stamp { isLoading = false } }
        func current() -> Bool { contextMatches && generation == stamp && !Task.isCancelled }
        func abandon() {
            if !contextMatches { retire() }
            else if generation == stamp { issue = .failed; isNetworkFailure = false }
        }
        do {
            try Task.checkCancellation()
            guard current() else { abandon(); return }
            let value = try await reader.read(.complaintTopics, isCurrent: { current() })
            guard current() else { abandon(); return }
            let fresh = try ProfileComplaintTopic.decode(value)
            topics = fresh
            if let selected = draft.topicID, !fresh.contains(where: { $0.id == selected }) { draft.topicID = nil }
        } catch {
            guard current() else { abandon(); return }
            let failure = ProfileComplaintReadIssue(error)
            isNetworkFailure = ProfileComplaintTopicLoadFailureCopy.isNetworkError(error)
            issue = failure
            if failure == .signIn || failure == .unavailable {
                topics = nil; draft = .init(); review = nil
            }
        }
    }
}
