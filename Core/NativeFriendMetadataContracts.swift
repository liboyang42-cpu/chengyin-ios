import Foundation
import CoreFoundation
import CryptoKit

public struct NativeFriendMetadata: Codable, Equatable, Sendable {
    public let viewerID: Int64
    public let peerID: Int64
    public let friendVersion: Int64
    public let version: Int64
    public let remark: String?
    public let groupID: Int64?
    public let starred: Int
    public let notificationEffect: String
    /// Nil means an older/unconfigured producer; it never silently enables the author control.
    public let progressScope: Int?
    public init(viewerID: Int64, peerID: Int64, friendVersion: Int64, version: Int64, remark: String?,
                groupID: Int64?, starred: Int, notificationEffect: String, progressScope: Int? = nil) {
        self.viewerID = viewerID; self.peerID = peerID; self.friendVersion = friendVersion; self.version = version
        self.remark = remark; self.groupID = groupID; self.starred = starred; self.notificationEffect = notificationEffect; self.progressScope = progressScope
    }
    enum CodingKeys: String, CodingKey {
        case viewerID = "viewer_id", peerID = "peer_id", friendVersion = "friend_version", version, remark
        case groupID = "group_id", starred, notificationEffect = "notification_effect", progressScope = "progress_scope"
    }
}
public struct NativeFriendMetadataGroup: Codable, Equatable, Identifiable, Sendable {
    public let id: Int64?
    public let name: String
    public let position: Int
    public let version: Int64
    public let isDefault: Int
    public let friendCount: Int?
    public init(id: Int64?, name: String, position: Int, version: Int64, isDefault: Int, friendCount: Int? = nil) {
        self.id=id;self.name=name;self.position=position;self.version=version;self.isDefault=isDefault;self.friendCount=friendCount
    }
    enum CodingKeys: String, CodingKey { case id, name, position, version, isDefault = "is_default", friendCount = "friend_count" }
}
public struct NativeFriendMetadataGroups: Codable, Equatable, Sendable {
    public let viewerID: Int64
    public let list: [NativeFriendMetadataGroup]
    enum CodingKeys: String, CodingKey { case viewerID = "viewer_id", list }
}
public enum NativeFriendMetadataAction: String, Codable, Sendable {
    case remark, groupSave = "group_save", groupDelete = "group_delete"
    public var path: String {
        switch self { case .remark: return "api/friend/remark"; case .groupSave: return "api/friend/group/save"; case .groupDelete: return "api/friend/group/delete" }
    }
}
/// A frozen review, not an auto-saved draft. No credential or new friendship authority is carried.
public struct NativeFriendMetadataCommand: Equatable, Sendable {
    public let requestID: UUID
    public let action: NativeFriendMetadataAction
    public let targetID: Int64
    public let expectedVersion: Int64
    public let expectedFriendVersion: Int64?
    public let remark: String?
    public let groupID: Int64?
    public let starred: Int?
    public let name: String?
    public let position: Int?
    public let progressScope: Int?
    public let updatesRemark: Bool
    public let updatesGroup: Bool
    public init(requestID: UUID = UUID(), action: NativeFriendMetadataAction, targetID: Int64,
                expectedVersion: Int64, expectedFriendVersion: Int64? = nil, remark: String? = nil,
                groupID: Int64? = nil, starred: Int? = nil, name: String? = nil, position: Int? = nil, updatesRemark: Bool = true, updatesGroup: Bool = false, progressScope: Int? = nil) {
        self.requestID = requestID; self.action = action; self.targetID = targetID; self.expectedVersion = expectedVersion
        self.expectedFriendVersion = expectedFriendVersion; self.remark = remark; self.groupID = groupID
        self.starred = starred; self.name = name; self.position = position; self.updatesRemark = updatesRemark; self.updatesGroup = updatesGroup; self.progressScope = progressScope
    }
    /// Matches server v1 semantic encoding, without storing the private command in the recovery journal.
    public func fingerprint() throws -> String {
        guard let fields = try JSONSerialization.jsonObject(with: body()) as? [String: Any] else { throw NativeFriendFailure.invalid }
        var raw = "friend-metadata-v1\n"
        for key in fields.keys.sorted() {
            raw += "\(key.utf8.count):\(key)"
            let value = fields[key]!
            if value is NSNull { raw += "N" }
            else if let text = value as? String { raw += "S\(text.utf8.count):\(text)" }
            else if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                    !["f", "d"].contains(String(cString: number.objCType)) { raw += "I\(number.int64Value);" }
            else { throw NativeFriendFailure.invalid }
        }
        return SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    public func body() throws -> Data {
        var fields: [String: Any] = ["request_id": requestID.uuidString, "expected_version": expectedVersion]
        switch action {
        case .remark:
            fields["peer_id"] = targetID; fields["expected_friend_version"] = expectedFriendVersion
            if updatesRemark { fields["remark"] = remark.map { $0 as Any } ?? NSNull() }
            if let starred { fields["starred"] = starred }
            if let progressScope { guard [0,1].contains(progressScope) else { throw NativeFriendFailure.invalid }; fields["progress_scope"] = progressScope }
            if updatesGroup { fields["group_id"] = groupID.map { $0 as Any } ?? NSNull() }
            // Omitted fields are unchanged. A star-only gesture never clears a private remark/group.
        case .groupSave:
            fields["id"] = targetID == 0 ? NSNull() : targetID as Any
            fields["name"] = name; fields["position"] = position
        case .groupDelete:
            fields["id"] = targetID; fields["move_to_group_id"] = groupID.map { $0 as Any } ?? NSNull()
        }
        return try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
    }
}
public struct NativeFriendMetadataReceipt: Codable, Equatable, Sendable {
    public let viewerID: Int64
    public let requestID: String
    public let action: NativeFriendMetadataAction
    public let targetID: Int64
    public let outcome: String
    public let reason: String?
    public let payloadHash: String?
    public let current: NativeFriendMetadata?
    public let groups: NativeFriendMetadataGroups?
    enum CodingKeys: String, CodingKey {
        case viewerID = "viewer_id", requestID = "request_id", action, targetID = "target_id", outcome, reason, current, groups, payloadHash = "payload_hash"
    }
    public init(viewerID: Int64, requestID: String, action: NativeFriendMetadataAction, targetID: Int64,
                outcome: String, current: NativeFriendMetadata?, groups: NativeFriendMetadataGroups?, payloadHash: String? = nil, reason: String? = nil) {
        self.viewerID = viewerID; self.requestID = requestID; self.action = action; self.targetID = targetID
        self.outcome = outcome; self.reason = reason; self.current = current; self.groups = groups; self.payloadHash = payloadHash
    }

}
public enum NativeFriendMetadataFailure: Error { case rejected(Int, String) }

@MainActor public protocol NativeFriendMetadataServing: AnyObject {
    var viewerID: Int64 { get }
    var isCurrent: Bool { get }
    var canWrite: Bool { get }
    var canStarWrite: Bool { get }
    var canProgressWrite: Bool { get }
    var canReadGroups: Bool { get }
    var canManageGroups: Bool { get }
    var canAssignGroup: Bool { get }
    var canSettle: Bool { get }
    func read(peerID: Int64) async throws -> NativeFriendMetadata
    func groups() async throws -> NativeFriendMetadataGroups
    func write(_ command: NativeFriendMetadataCommand) async throws -> NativeFriendMetadataReceipt
    func receipt(action: NativeFriendMetadataAction, targetID: Int64, requestID: UUID) async throws -> NativeFriendMetadataReceipt
    func settle(action: NativeFriendMetadataAction, targetID: Int64, requestID: UUID, payloadHash: String) async throws -> NativeFriendMetadataReceipt
}
@MainActor public extension NativeFriendMetadataServing {
    var canReadGroups: Bool { false }
    var canManageGroups: Bool { false }
    var canAssignGroup: Bool { false }
    var canProgressWrite: Bool { false }
    var canStarWrite: Bool { false } // Existing/read-only providers never silently gain star mutation.
}
public enum NativeFriendMetadataValidation {
    public static func remark(_ raw: String) -> String? { let text = raw.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping; return text.isEmpty ? nil : text }
    public static func validRemark(_ raw: String?) -> Bool {
        guard let raw else { return true }
        let text = raw.replacingOccurrences(of: "[0-9#*]\u{FE0F}?\u{20E3}", with: "", options: .regularExpression)
        return raw.unicodeScalars.count <= 30 && !raw.unicodeScalars.contains { $0.properties.generalCategory == .control } &&
            text.unicodeScalars.contains {
                let value = $0.value
                return !CharacterSet.whitespacesAndNewlines.contains($0) &&
                    (CharacterSet.decimalDigits.contains($0) || value == 35 || value == 42 ||
                     (!$0.properties.isEmoji && value != 0x200D && value != 0xFE0F && value != 0xFE0E && value != 0x20E3 && !(0xE0020...0xE007F).contains(value)))
            }
    }
    public static func validGroups(_ value: NativeFriendMetadataGroups, viewerID: Int64) -> Bool {
        value.viewerID == viewerID && (1...20).contains(value.list.count) &&
        Set(value.list.map { $0.id ?? 0 }).count == value.list.count &&
        value.list.filter { $0.isDefault == 1 && ($0.id ?? 0) == 0 && $0.version == 0 }.count == 1 &&
        value.list.allSatisfy { group in
            group.position >= 0 && group.position <= Int(Int32.max) && (group.friendCount.map { $0 >= 0 } ?? true) &&
            ((group.isDefault == 1 && (group.id ?? 0) == 0 && group.version == 0) ||
             (group.isDefault == 0 && (group.id ?? 0) > 0 && group.version > 0 && validGroupName(group.name)))
        }
    }
    public static func groupName(_ raw: String) -> String { raw.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping }
    public static func validGroupName(_ text: String) -> Bool {
        !text.isEmpty && text.unicodeScalars.count <= 12 && !text.unicodeScalars.contains { $0.properties.generalCategory == .control }
    }
}
