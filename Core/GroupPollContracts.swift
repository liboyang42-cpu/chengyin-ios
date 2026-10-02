import Foundation

/// Separate poll, conversation and message identifiers. A type-4 card is a reference,
/// never a generic route or a user-editable /im/send payload.
public struct GroupPollReference: Equatable, Hashable {
    public let pollID: Int
    public let conversationID: Int
    public let messageID: Int
    public let creatorID: Int
    public init(poll: GroupPoll) {
        pollID = poll.id; conversationID = poll.conversationId; messageID = poll.messageId; creatorID = poll.creatorMemberId
    }
    public init?(message: MessagingMessage) {
        struct Card: Decodable { let pollId: Int }
        guard message.type == 4, let creator = message.senderID, creator > 0,
              let raw = message.extraJSON?.data(using: .utf8), raw.count <= 1024,
              let card = try? JSONDecoder().decode(Card.self, from: raw), card.pollId > 0 else { return nil }
        pollID = card.pollId; conversationID = message.conversationID; messageID = message.id; creatorID = creator
    }
}
public extension MessagingMessage { var pollReference: GroupPollReference? { GroupPollReference(message: self) } }
public extension MessagingConversation {
    /// Poll SQL currently snapshots team/club membership only. Hangout group chat remains
    /// available, but enabling a poll there would require a different backend contract.
    var supportsGroupPolls: Bool {
        guard kind == .group, let key = counterparty?.bizKey else { return false }
        let parts = key.split(separator: "_", omittingEmptySubsequences: false)
        guard parts.count == 2, ["team", "club"].contains(String(parts[0])),
              let id = Int(parts[1]), id > 0 else { return false }
        return String(id) == parts[1]
    }
}
public struct GroupPollDraft: Equatable, Encodable {
    public let conversationId: Int
    public let clientPollKey: String
    public let question: String
    public let options: [String]
    /// Jackson Date accepts epoch milliseconds; no device/server wall-time guess.
    public let deadlineAt: Int64?
    public init(conversationID: Int, question: String, options: [String], deadline: Date? = nil,
                clientPollKey: String = UUID().uuidString.lowercased(), now: Date = Date()) throws {
        let trim: (String) -> String = { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let question = trim(question), options = options.map(trim), key = trim(clientPollKey)
        guard conversationID > 0, (1...64).contains(key.utf16.count),
              (1...200).contains(question.utf16.count), (2...10).contains(options.count),
              options.allSatisfy({ (1...100).contains($0.utf16.count) }),
              deadline.map({ $0 > now && $0.timeIntervalSince1970.isFinite && $0.timeIntervalSince1970 < 253402300799 }) ?? true else { throw APIError.invalidRequest }
        self.conversationId = conversationID; self.clientPollKey = key; self.question = question; self.options = options
        self.deadlineAt = deadline.map { Int64(($0.timeIntervalSince1970 * 1000).rounded(.down)) }
    }
    public var deadline: Date? { deadlineAt.map { Date(timeIntervalSince1970: Double($0) / 1000) } }
}
public struct GroupPollOption: Decodable, Equatable, Identifiable {
    public let id: Int
    public let pollId: Int
    public let position: Int
    public let content: String
    public let voteCount: Int?
}
public struct GroupPoll: Decodable, Equatable, Identifiable {
    public let id: Int
    public let conversationId: Int
    public let creatorMemberId: Int
    public let clientPollKey: String
    public let question: String
    public let selectionMode: String
    public let visibility: String
    public let status: String
    public let deadlineAt: GroupPollDate?
    public let version: Int
    public let messageId: Int
    public let options: [GroupPollOption]
    public let totalVoters: Int?
    public let myOptionId: Int?
    public var hasResults: Bool { totalVoters != nil }
    public func isOpen(now: Date = Date()) -> Bool { status == "OPEN" && (deadlineAt.map { $0.value > now } ?? true) }
    public func validate(reference: GroupPollReference? = nil, conversationID: Int, results: Bool) throws {
        guard id > 0, conversationId == conversationID, conversationId > 0, creatorMemberId > 0,
              version > 0, messageId > 0, (1...64).contains(clientPollKey.utf16.count),
              (1...200).contains(question.utf16.count), selectionMode == "SINGLE", visibility == "PUBLIC",
              ["OPEN", "CLOSED"].contains(status), (2...10).contains(options.count),
              Set(options.map(\.id)).count == options.count,
              options.enumerated().allSatisfy({ index, row in row.id > 0 && row.pollId == id && row.position == index + 1 && (1...100).contains(row.content.utf16.count) && (row.voteCount.map { $0 >= 0 } ?? true) }),
              myOptionId.map({ selected in options.contains { $0.id == selected } }) ?? true else { throw APIError.malformedResponse }
        if let reference {
            guard id == reference.pollID, messageId == reference.messageID, creatorMemberId == reference.creatorID,
                  conversationId == reference.conversationID else { throw APIError.malformedResponse }
        }
        if results {
            guard let totalVoters, totalVoters >= 0, options.allSatisfy({ $0.voteCount != nil }) else { throw APIError.malformedResponse }
            var sum = 0
            for option in options { let addition = sum.addingReportingOverflow(option.voteCount!); guard !addition.overflow else { throw APIError.malformedResponse }; sum = addition.partialValue }
            guard sum == totalVoters, myOptionId == nil || totalVoters > 0,
                  myOptionId.map({ chosen in options.first(where: { $0.id == chosen })!.voteCount! > 0 }) ?? true else { throw APIError.malformedResponse }
        }
    }
}
public struct GroupPollDate: Decodable, Equatable {
    public let value: Date
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let milliseconds = try? c.decode(Double.self), milliseconds.isFinite, milliseconds >= 0, milliseconds < 253402300799000 {
            value = Date(timeIntervalSince1970: milliseconds / 1000); return
        }
        let raw = try c.decode(String.self)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: raw) { value = date; return }
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: raw) else { throw APIError.malformedResponse }
        value = date
    }
}
public enum GroupPollMutation: Equatable {
    case create(GroupPollDraft)
    case vote(pollID: Int, optionID: Int)
    case close(pollID: Int, expectedVersion: Int)
    public var path: String {
        switch self { case .create: return "api/im/poll/create"; case .vote: return "api/im/poll/vote"; case .close: return "api/im/poll/close" }
    }
    public func body() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        switch self {
        case .create(let draft): return try encoder.encode(draft)
        case .vote(let poll, let option):
            guard poll > 0, option > 0 else { throw APIError.invalidRequest }
            return try encoder.encode(["pollId": poll, "optionId": option])
        case .close(let poll, let version):
            guard poll > 0, version > 0 else { throw APIError.invalidRequest }
            return try encoder.encode(["pollId": poll, "expectedVersion": version])
        }
    }
}

public extension GroupPoll {
    func validateReceipt(_ mutation: GroupPollMutation, scope: IMScope) throws {
        guard conversationId == scope.conversationID else { throw APIError.malformedResponse }
        switch mutation {
        case .create(let draft):
            guard creatorMemberId == scope.identity.accountID, clientPollKey == draft.clientPollKey,
                  question == draft.question, options.map(\.content) == draft.options, deadlineAt?.value == draft.deadline else { throw APIError.malformedResponse }
        case .vote(let id, let option): guard self.id == id, myOptionId == option else { throw APIError.malformedResponse }
        case .close(let id, let expected):
            guard self.id == id, creatorMemberId == scope.identity.accountID, status == "CLOSED", expected < Int.max, version == expected + 1 else { throw APIError.malformedResponse }
        }
    }
}
