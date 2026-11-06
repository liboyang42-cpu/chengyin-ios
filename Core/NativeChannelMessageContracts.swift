import Foundation

/// Native mapped-channel IDs are decimal strings on the audited wire. Never Double.
public struct NativeChannelMessageID: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: String
    public init?(rawValue: String) {
        guard !rawValue.isEmpty, rawValue.utf8.allSatisfy({ (48...57).contains($0) }),
              let value = Int64(rawValue), value > 0, String(value) == rawValue else { return nil }
        self.rawValue = rawValue
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        guard let value = Self(rawValue: try c.decode(String.self)) else { throw APIError.malformedResponse }
        self = value
    }
    public func encode(to encoder: Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(rawValue) }
}

/// Issued from the current real channel record/mapping, never an old conversation row.
/// The host owns provenance and permission revocation. This value grants no permission.
public struct NativeChannelMessageBinding: Codable, Equatable, Sendable {
    public let channelID: NativeChannelMessageID
    public let conversationID: NativeChannelMessageID
    public let mappingRevision: String
    public init(channelID: NativeChannelMessageID, conversationID: NativeChannelMessageID, mappingRevision: String) throws {
        guard !mappingRevision.isEmpty else { throw APIError.invalidRequest }
        self.channelID = channelID; self.conversationID = conversationID; self.mappingRevision = mappingRevision
    }
    public func sameTarget(as other: Self) -> Bool { channelID == other.channelID && conversationID == other.conversationID }
}

public enum NativeChannelMessageOperation: String, Codable, CaseIterable, Sendable {
    case edit = "EDIT", recall = "RECALL", pin = "PIN", unpin = "UNPIN", sort = "PIN_SORT"
}

/// An original mutation, separate from the existing client_message_id send journal.
public struct NativeChannelMessageCommand: Codable, Equatable, Sendable {
    public let operation: NativeChannelMessageOperation
    public let requestID: String
    public let binding: NativeChannelMessageBinding
    public let messageID: NativeChannelMessageID?
    public let expectedVersion: Int64?
    public let content: String?
    public let reason: String?
    public let memberIDs: [NativeChannelMessageID]
    public let roleIDs: [NativeChannelMessageID]
    public let mentionEveryone: Bool
    public let orderedPinIDs: [NativeChannelMessageID]
    public init(operation: NativeChannelMessageOperation, requestID: String,
                binding: NativeChannelMessageBinding, messageID: NativeChannelMessageID? = nil,
                expectedVersion: Int64? = nil, content: String? = nil, reason: String? = nil,
                memberIDs: [NativeChannelMessageID] = [], roleIDs: [NativeChannelMessageID] = [],
                mentionEveryone: Bool = false, orderedPinIDs: [NativeChannelMessageID] = []) throws {
        self.operation = operation; self.requestID = requestID; self.binding = binding
        self.messageID = messageID; self.expectedVersion = expectedVersion
        self.content = content; self.reason = reason; self.memberIDs = memberIDs; self.roleIDs = roleIDs
        self.mentionEveryone = mentionEveryone; self.orderedPinIDs = orderedPinIDs
        try validate()
    }
    public func validate() throws {
        guard (16...64).contains(requestID.utf8.count), requestID.utf8.allSatisfy({
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95
        }), !binding.mappingRevision.isEmpty,
        memberIDs.count <= 20, roleIDs.count <= 20, orderedPinIDs.count <= 20,
        Set(memberIDs).count == memberIDs.count, Set(roleIDs).count == roleIDs.count,
        Set(orderedPinIDs).count == orderedPinIDs.count else { throw APIError.invalidRequest }
        switch operation {
        case .edit:
            guard messageID != nil, let expectedVersion, expectedVersion > 0,
                  let content, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  content.unicodeScalars.count <= 2000, reason == nil, orderedPinIDs.isEmpty else { throw APIError.invalidRequest }
        case .recall:
            guard messageID != nil, let expectedVersion, expectedVersion > 0,
                  (reason ?? "").unicodeScalars.count <= 200, content == nil,
                  memberIDs.isEmpty, roleIDs.isEmpty, !mentionEveryone, orderedPinIDs.isEmpty else { throw APIError.invalidRequest }
        case .pin, .unpin:
            guard messageID != nil, expectedVersion == nil, content == nil, reason == nil,
                  memberIDs.isEmpty, roleIDs.isEmpty, !mentionEveryone, orderedPinIDs.isEmpty else { throw APIError.invalidRequest }
        case .sort:
            guard messageID == nil, expectedVersion == nil, content == nil, reason == nil,
                  memberIDs.isEmpty, roleIDs.isEmpty, !mentionEveryone else { throw APIError.invalidRequest }
        }
    }
    public var body: [String: Any] {
        var fields: [String: Any] = ["conversation_id": binding.channelID.rawValue, "request_id": requestID]
        if let messageID { fields["message_id"] = messageID.rawValue }
        if let expectedVersion { fields["expected_version"] = expectedVersion }
        switch operation {
        case .edit:
            fields["content"] = content; fields["mention_member_ids"] = memberIDs.map(\.rawValue)
            fields["mention_role_ids"] = roleIDs.map(\.rawValue); fields["mention_everyone"] = mentionEveryone
        case .recall: fields["reason"] = reason ?? ""
        case .sort: fields["ordered_pin_ids"] = orderedPinIDs.map(\.rawValue)
        case .pin, .unpin: break
        }
        return fields
    }
}

public struct NativeChannelMessageResult: Decodable, Equatable {
    public let message_id: NativeChannelMessageID?
    public let conversation_id: NativeChannelMessageID?
    public let version: Int64?
    public let revision: Int64?
    public let status: Int?
    public let changed: Bool?
    public let pinned: Bool?
    public let unpinned: Bool?
    public let id: NativeChannelMessageID?
    public let sort_no: Int?
    public let updated: Int?
    public let sort_nos: [String: Int]?
    public func verify(_ command: NativeChannelMessageCommand) throws {
        if let conversation_id, conversation_id != command.binding.channelID { throw APIError.malformedResponse }
        guard command.operation == .sort || message_id == command.messageID else { throw APIError.malformedResponse }
        switch command.operation {
        case .edit:
            guard let version, version > 0, revision == version, let changed, let expected = command.expectedVersion else { throw APIError.malformedResponse }
            let next = expected.addingReportingOverflow(1)
            guard changed ? (!next.overflow && version == next.partialValue) : version == expected else { throw APIError.malformedResponse }
        case .recall:
            guard status == 1, let version, version > 0, let changed else { throw APIError.malformedResponse }
            if changed {
                guard let expected = command.expectedVersion else { throw APIError.malformedResponse }
                let next = expected.addingReportingOverflow(1)
                guard !next.overflow, version == next.partialValue else { throw APIError.malformedResponse }
            }
        case .pin:
            guard pinned == true, id != nil, sort_no != nil else { throw APIError.malformedResponse }
        case .unpin:
            guard pinned == false, unpinned == true else { throw APIError.malformedResponse }
        case .sort:
            guard updated == command.orderedPinIDs.count, let sort_nos,
                  Set(sort_nos.keys) == Set(command.orderedPinIDs.map(\.rawValue)),
                  command.orderedPinIDs.enumerated().allSatisfy({ sort_nos[$0.element.rawValue] == (command.orderedPinIDs.count - $0.offset) * 100 }) else { throw APIError.malformedResponse }
        }
    }
}

public struct NativeChannelMessageReceipt: Decodable {
    public let request_id: String
    public let state: String
    public let outcome_confirmed: Bool
    public let operation: NativeChannelMessageOperation?
    public let conversation_id: NativeChannelMessageID?
    public let result_redacted: Bool?
    public let result: NativeChannelMessageResult?
    public func verify(_ command: NativeChannelMessageCommand) throws -> Bool {
        guard request_id.utf8.elementsEqual(command.requestID.utf8) else { throw APIError.malformedResponse }
        if state == "NOT_FOUND" || state == "PENDING" {
            guard !outcome_confirmed, result == nil, result_redacted != true else { throw APIError.malformedResponse }
            return false
        }
        guard state == "APPLIED", outcome_confirmed, operation == command.operation,
              conversation_id == command.binding.channelID else { throw APIError.malformedResponse }
        if result_redacted == true { guard result == nil else { throw APIError.malformedResponse }; return true }
        guard let result else { throw APIError.malformedResponse }
        try result.verify(command); return true
    }
}

public struct NativeChannelMessageFailure: Error, Equatable {
    public let httpStatus: Int
    public let code: Int?
    public let errorCode: String?
    public let message: String?
    public let outcomeKnown: Bool?
    public var versionConflict: Bool { errorCode == "MESSAGE_VERSION_CONFLICT" }
    /// Current ApiChannelPlatformHttpResponse emits known 4xx, while uncertainty is
    /// HTTP/code500+OUTCOME_UNKNOWN+outcome_known=false. A request-key conflict stays locked.
    public var definiteRejection: Bool {
        (400..<500).contains(httpStatus) && code == httpStatus && outcomeKnown != false
            && errorCode != "OUTCOME_UNKNOWN" && errorCode != "REQUEST_ID_CONFLICT"
            && errorCode?.range(of: "^[A-Z][A-Z0-9_]{0,127}$", options: .regularExpression) != nil
    }
}
