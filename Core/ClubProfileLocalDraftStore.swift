import Foundation
#if canImport(Security)
import Security
#endif

/// User content only. This separate local slot never supplies network approval or
/// clears an OperationPendingJournal. Namespace includes the deployment and bundle.
public struct ClubProfileLocalDraftScope: Codable, Equatable {
    public let namespace: String
    public let accountID: Int
    public let clubID: Int
    public init(namespace: String, accountID: Int, clubID: Int) throws {
        guard !namespace.isEmpty, namespace.utf8.count <= 2048, accountID > 0, clubID > 0 else {
            throw ClubProfileLocalDraftIssue.unavailable
        }
        self.namespace = namespace; self.accountID = accountID; self.clubID = clubID
    }
    var key: String { "club-profile.v1:" + Data("\(namespace.utf8.count):\(namespace):\(accountID):\(clubID)".utf8).base64EncodedString() }
}

/// The original editable allowlist. No token, temporary image bytes, upload proof,
/// membership record, pending writer identity, or server revision is serialized.
public struct ClubProfileLocalDraftForm: Codable, Equatable {
    public var name: String, city: String, description: String, keywords: String, style: String, clubType: String
    public var activityPrefs: [String]
    public var logo: String, cover: String
    public var prioritySignupEnabled: Bool
    public var memberReservedQuota: String
    public var joinPolicy: Int
    public init(_ draft: ClubOperationsDraft) {
        name = draft.name; city = draft.city; description = draft.description; keywords = draft.keywords
        style = draft.style; clubType = draft.clubType; activityPrefs = draft.activityPrefs
        logo = draft.logo; cover = draft.cover; prioritySignupEnabled = draft.prioritySignupEnabled
        memberReservedQuota = draft.memberReservedQuota; joinPolicy = draft.joinPolicy
    }
    func validateShape() throws {
        guard Self.publicMediaReference(logo), Self.publicMediaReference(cover),
              [0, 1].contains(joinPolicy), activityPrefs.count <= 64,
              ([name, city, description, keywords, style, clubType, logo, cover, memberReservedQuota] + activityPrefs)
                .allSatisfy({ $0.utf8.count <= 16384 }) else { throw ClubProfileLocalDraftIssue.corrupt }
    }
    private static func publicMediaReference(_ value: String) -> Bool {
        if value.isEmpty { return true }
        guard value.utf8.count <= 16384, value.utf8.allSatisfy({ $0 >= 33 && $0 != 127 }),
              let url = URLComponents(string: value), url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil else { return false }
        if let scheme = url.scheme { return ["https", "http"].contains(scheme.lowercased()) && url.host?.isEmpty == false }
        return value.hasPrefix("/") && !value.hasPrefix("//") && url.host == nil
    }
    public var contentIdentity: Data? {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(self)
    }
    /// Raw UTF-8 is significant in the local envelope, unlike Swift String's
    /// canonical-equivalence equality. This is NOT an atomic server revision.
    public func exactlyMatches(_ other: Self) -> Bool {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        guard let a = try? encoder.encode(self), let b = try? encoder.encode(other) else { return false }
        return a == b
    }
    public func restoring(against profile: ClubOperationsProfile) -> ClubOperationsDraft {
        var value = ClubOperationsDraft(profile: profile)
        value.name = name; value.city = city; value.description = description; value.keywords = keywords
        value.style = style; value.clubType = clubType; value.activityPrefs = activityPrefs
        value.logo = logo; value.cover = cover
        // No upload receipt can survive restoration. Existing media validation
        // requires re-selection or explicit use of the current server image.
        if profile.club.isOwner {
            value.prioritySignupEnabled = prioritySignupEnabled; value.memberReservedQuota = memberReservedQuota
            if profile.club.joinPolicySupported { value.joinPolicy = joinPolicy }
        }
        return value
    }
    /// Matches the already-existing writer's trimming/empty-quota behavior only.
    func submitted(against profile: ClubOperationsProfile) -> Self {
        var value = self
        value.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        value.city = city.trimmingCharacters(in: .whitespacesAndNewlines)
        value.description = description.trimmingCharacters(in: .whitespacesAndNewlines)
        value.keywords = keywords.trimmingCharacters(in: .whitespacesAndNewlines)
        value.style = style.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = Self(ClubOperationsDraft(profile: profile))
        if profile.club.isOwner {
            value.memberReservedQuota = String(Int(memberReservedQuota.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0)
            if !profile.club.joinPolicySupported { value.joinPolicy = source.joinPolicy }
        } else {
            value.prioritySignupEnabled = source.prioritySignupEnabled; value.memberReservedQuota = source.memberReservedQuota
            value.joinPolicy = source.joinPolicy
        }
        if value.memberReservedQuota.isEmpty { value.memberReservedQuota = "0" }
        return value
    }
    func matchesReadback(_ profile: ClubOperationsProfile) -> Bool {
        var current = Self(ClubOperationsDraft(profile: profile))
        if current.memberReservedQuota.isEmpty { current.memberReservedQuota = "0" }
        return exactlyMatches(current)
    }
}

public struct ClubProfileLocalDraftBaseline: Codable, Equatable {
    public let form: ClubProfileLocalDraftForm
    public let isOwner: Bool, viewerIsAdmin: Bool, joinPolicySupported: Bool
    public init(_ profile: ClubOperationsProfile) {
        form = .init(ClubOperationsDraft(profile: profile)); isOwner = profile.club.isOwner
        viewerIsAdmin = profile.club.viewerIsAdmin; joinPolicySupported = profile.club.joinPolicySupported
    }
    func sameRole(_ profile: ClubOperationsProfile) -> Bool {
        !profile.club.viewerIdentityUnavailable && profile.club.canGovern && isOwner == profile.club.isOwner && viewerIsAdmin == profile.club.viewerIsAdmin && joinPolicySupported == profile.club.joinPolicySupported
    }
    public func matches(_ profile: ClubOperationsProfile) -> Bool {
        sameRole(profile) && form.exactlyMatches(.init(ClubOperationsDraft(profile: profile)))
    }
}

public struct ClubProfileLocalDraftAttempt: Codable, Equatable {
    public enum Result: String, Codable { case awaitingOriginalResult, acknowledged }
    public let reviewID: UUID
    public let submitted: ClubProfileLocalDraftForm
    public var result: Result
}
public struct ClubProfileLocalDraftRecord: Codable, Equatable {
    public let schema: Int
    public let scope: ClubProfileLocalDraftScope
    public var baseline: ClubProfileLocalDraftBaseline
    public var form: ClubProfileLocalDraftForm
    public var attempt: ClubProfileLocalDraftAttempt?
    public init(scope: ClubProfileLocalDraftScope, profile: ClubOperationsProfile, form: ClubProfileLocalDraftForm) {
        schema = 1; self.scope = scope; baseline = .init(profile); self.form = form; attempt = nil
    }
    func validate(scope: ClubProfileLocalDraftScope) throws {
        guard schema == 1, self.scope == scope, baseline.isOwner || baseline.viewerIsAdmin else { throw ClubProfileLocalDraftIssue.corrupt }
        try baseline.form.validateShape(); try form.validateShape(); try attempt?.submitted.validateShape()
    }
}
public enum ClubProfileLocalDraftIssue: Error { case unavailable, corrupt, changed }
public struct ClubProfileLocalDraftBytes: Equatable {
    public let data: Data
    public let tag: Data
    public init(data: Data, tag: Data) { self.data = data; self.tag = tag }
}
@MainActor public protocol ClubProfileLocalDraftStorage: AnyObject {
    func read(key: String) throws -> ClubProfileLocalDraftBytes?
    /// Atomic LOCAL exact-preimage replacement; not a server CAS/locking contract.
    func replace(key: String, expected: ClubProfileLocalDraftBytes?, data: Data?) throws -> ClubProfileLocalDraftBytes?
}
public struct ClubProfileLocalDraftSnapshot {
    public let record: ClubProfileLocalDraftRecord?
    fileprivate let bytes: ClubProfileLocalDraftBytes?
}
@MainActor public final class ClubProfileLocalDraftStore {
    private let storage: any ClubProfileLocalDraftStorage
    public init(storage: any ClubProfileLocalDraftStorage) { self.storage = storage }
    public func read(_ scope: ClubProfileLocalDraftScope) throws -> ClubProfileLocalDraftSnapshot {
        let raw = try storage.read(key: scope.key)
        guard let raw else { return .init(record: nil, bytes: nil) }
        guard raw.data.count <= 131072, raw.tag.count == 32,
              let record = try? JSONDecoder().decode(ClubProfileLocalDraftRecord.self, from: raw.data) else { throw ClubProfileLocalDraftIssue.corrupt }
        try record.validate(scope: scope)
        // Reject duplicate/unknown keys and lossy decoding instead of overwriting a
        // future or corrupted record after JSONDecoder silently drops its fields.
        let canonical = try JSONEncoder().encode(record)
        guard let source = String(data: raw.data, encoding: .utf8),
              let parsed = try? ContentDraftJSON.parse(source),
              let retained = try? ContentDraftJSON.parse(String(decoding: canonical, as: UTF8.self)),
              parsed == retained else {
            throw ClubProfileLocalDraftIssue.corrupt
        }
        return .init(record: record, bytes: raw)
    }
    public func verify(_ expected: ClubProfileLocalDraftSnapshot, scope: ClubProfileLocalDraftScope) throws {
        guard try storage.read(key: scope.key) == expected.bytes else { throw ClubProfileLocalDraftIssue.changed }
    }
    public func replace(_ record: ClubProfileLocalDraftRecord?, scope: ClubProfileLocalDraftScope,
                        expected: ClubProfileLocalDraftSnapshot) throws -> ClubProfileLocalDraftSnapshot {
        try record?.validate(scope: scope)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try record.map { try encoder.encode($0) }
        guard (data?.count ?? 0) <= 131072 else { throw ClubProfileLocalDraftIssue.unavailable }
        let next = try storage.replace(key: scope.key, expected: expected.bytes, data: data)
        return .init(record: record, bytes: next)
    }
    public static func system() -> ClubProfileLocalDraftStore? {
        #if canImport(Security)
        return .init(storage: ClubProfileLocalDraftKeychain())
        #else
        return nil
        #endif
    }
}

#if canImport(Security)
/// Protected, device-only user content, no plaintext/UserDefaults fallback, token,
/// access-group, synchronisation, authentication UI, or read-then-blind upsert.
@MainActor private final class ClubProfileLocalDraftKeychain: ClubProfileLocalDraftStorage {
    private func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "questify.club-profile.local-draft.v1",
         kSecAttrAccount as String: key, kSecAttrSynchronizable as String: false,
         kSecUseDataProtectionKeychain as String: true, kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail]
    }
    func read(key: String) throws -> ClubProfileLocalDraftBytes? {
        var request = query(key); request[kSecReturnAttributes as String] = true; request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let value = result as? [String: Any],
              let data = value[kSecValueData as String] as? Data, let tag = value[kSecAttrGeneric as String] as? Data,
              data.count <= 131072, tag.count == 32,
              (value[kSecAttrAccessible as String] as? String) == (kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String),
              (value[kSecAttrSynchronizable as String] as? NSNumber)?.boolValue == false else { throw ClubProfileLocalDraftIssue.unavailable }
        return .init(data: data, tag: tag)
    }
    func replace(key: String, expected: ClubProfileLocalDraftBytes?, data: Data?) throws -> ClubProfileLocalDraftBytes? {
        guard try read(key: key) == expected else { throw ClubProfileLocalDraftIssue.changed }
        if data == nil {
            guard let expected else { return nil }
            var request = query(key); request[kSecAttrGeneric as String] = expected.tag
            let status = SecItemDelete(request as CFDictionary)
            guard status == errSecSuccess else { throw ClubProfileLocalDraftIssue.changed }; return nil
        }
        guard let data, data.count <= 131072 else { throw ClubProfileLocalDraftIssue.unavailable }
        var tag = Data(count: 32)
        let random = tag.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) }
        guard random == errSecSuccess else { throw ClubProfileLocalDraftIssue.unavailable }
        var request = query(key)
        let status: OSStatus
        if let expected {
            request[kSecAttrGeneric as String] = expected.tag
            status = SecItemUpdate(request as CFDictionary, [kSecValueData as String: data, kSecAttrGeneric as String: tag] as CFDictionary)
        } else {
            request[kSecValueData as String] = data; request[kSecAttrGeneric as String] = tag
            request[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(request as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw ClubProfileLocalDraftIssue.changed }
        return .init(data: data, tag: tag)
    }
}
#endif
