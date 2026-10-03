#if canImport(Security) && canImport(Darwin)
import Foundation
import Security
import Darwin

/// Only an explicitly invoked, reviewed composition may create the production adapter.
/// No AppSession/UI grant or default storage injection is installed by this factory.
@MainActor enum ContentDraftJournalFactory {
    static func make(scope: ContentDraftJournalScope) async throws -> ContentDraftDurableJournal {
        let root = await ContentDraftStorageRoot().directory()
        let storage = ContentDraftSystemStorage(
            anchors: ContentDraftSystemAnchors(service: "questify.content-draft.pending.v1"),
            ciphertexts: ContentDraftSystemCiphertexts(root: root, createApplicationSupport: true))
        return try ContentDraftDurableJournal(scope: scope, system: storage)
    }
}
/// Unforgeable outside this file, including from App/UI in the same module.
/// Only the bounded factory above constructs this handle; injectable primitives do not confer it.
struct ContentDraftSystemStorage {
    let anchors: ContentDraftSystemAnchors
    let ciphertexts: ContentDraftSystemCiphertexts
    fileprivate init(anchors: ContentDraftSystemAnchors, ciphertexts: ContentDraftSystemCiphertexts) {
        self.anchors = anchors; self.ciphertexts = ciphertexts
    }
}
private actor ContentDraftStorageRoot {
    func directory() -> URL {
        // Canonicalize only the OS-supplied sandbox container/home, never an app-writable tail.
        // The fixed Library/Application Support tail is validated/created through descriptors.
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).resolvingSymlinksInPath()
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("ContentDraftJournal-v1", isDirectory: true)
    }
}

/// OS unique insertion and attribute-conditional update/delete protect separate instances.
/// No credentials, access groups, authentication UI, synchronization, or upsert fallback.
actor ContentDraftSystemAnchors: ContentDraftAnchorStore {
    private let service: String
    init(service: String) { self.service = service }
    private func query(_ slot: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: slot, kSecAttrSynchronizable as String: false,
         kSecUseDataProtectionKeychain as String: true,
         kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail]
    }
    private func validate(_ item: ContentDraftAnchorItem) throws {
        guard item.bytes.count <= 8_192, item.tag.count == 32 else { throw ContentDraftIssue.storageUnavailable }
    }
    func read(slot: String) throws -> ContentDraftAnchorItem? {
        var request = query(slot)
        request[kSecReturnAttributes as String] = true; request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let attributes = result as? [String: Any],
              let bytes = attributes[kSecValueData as String] as? Data,
              let tag = attributes[kSecAttrGeneric as String] as? Data,
              (attributes[kSecAttrAccessible as String] as? String) == (kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String),
              (attributes[kSecAttrSynchronizable as String] as? NSNumber)?.boolValue == false else { throw ContentDraftIssue.storageUnavailable }
        let item = ContentDraftAnchorItem(bytes: bytes, tag: tag); try validate(item); return item
    }
    func insert(slot: String, item: ContentDraftAnchorItem) throws -> Bool {
        try validate(item)
        var request = query(slot)
        request[kSecValueData as String] = item.bytes; request[kSecAttrGeneric as String] = item.tag
        request[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(request as CFDictionary, nil)
        if status == errSecDuplicateItem { return false }
        guard status == errSecSuccess else { throw ContentDraftIssue.storageUnavailable }; return true
    }
    func exchange(slot: String, matchingTag: Data, item: ContentDraftAnchorItem) throws -> Bool {
        try validate(item)
        guard matchingTag.count == 32, matchingTag != item.tag else { throw ContentDraftIssue.storageUnavailable }
        var request = query(slot); request[kSecAttrGeneric as String] = matchingTag
        let changes = [kSecValueData as String: item.bytes, kSecAttrGeneric as String: item.tag]
        let status = SecItemUpdate(request as CFDictionary, changes as CFDictionary)
        if status == errSecItemNotFound { return false }
        guard status == errSecSuccess else { throw ContentDraftIssue.storageUnavailable }; return true
    }
    func remove(slot: String, matchingTag: Data) throws -> Bool {
        guard matchingTag.count == 32 else { throw ContentDraftIssue.storageUnavailable }
        var request = query(slot); request[kSecAttrGeneric as String] = matchingTag
        let status = SecItemDelete(request as CFDictionary)
        if status == errSecItemNotFound { return false }
        guard status == errSecSuccess else { throw ContentDraftIssue.storageUnavailable }; return true
    }
}

/// Files hold AES-GCM combined ciphertext only. Names are random blob IDs, never user fields.
/// Production factory supplies only its fixed app-private Application Support root.
/// Alternative roots are internal to synthetic filesystem tests. Ciphertext may enter OS backups;
/// no payload plaintext or key is in a file, and cross-device journal migration is unsupported.
actor ContentDraftSystemCiphertexts: ContentDraftCiphertextStore {
    // Apple File System Reference, Protection Classes, pp. 142–143:
    // PROTECTION_CLASS_A = 1 corresponds to FileProtectionType.complete.
    // Use the documented value rather than assume that macro is exposed by every Swift SDK.
    private static let completeProtectionClass: Int32 = 1
    private let root: URL
    private let createApplicationSupport: Bool
    init(root: URL, createApplicationSupport: Bool = false) { self.root = root; self.createApplicationSupport = createApplicationSupport }
    private func directory() throws -> Int32 {
        guard root.isFileURL, root.path != "/", root.path == root.standardizedFileURL.path else { throw ContentDraftIssue.storageUnavailable }
        let components = root.pathComponents.filter { $0 != "/" }
        guard let leaf = components.last, !components.contains(".."), !components.contains(".") else { throw ContentDraftIssue.storageUnavailable }
        var parent = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard parent >= 0 else { throw ContentDraftIssue.storageUnavailable }
        defer { Darwin.close(parent) }
        // Reject symlinks at EVERY path component. Keep the verified parent descriptor throughout
        // creation and opening; no path-based metadata write can escape through a replaced ancestor.
        for (index, component) in components.dropLast().enumerated() {
            if createApplicationSupport && index == components.count - 2 && component == "Application Support" {
                let result = mkdirat(parent, component, mode_t(0o700))
                guard result == 0 || errno == EEXIST else { throw ContentDraftIssue.storageUnavailable }
                guard fsync(parent) == 0, fcntl(parent, F_FULLFSYNC) == 0 else { throw ContentDraftIssue.storageUnavailable }
            }
            let next = openat(parent, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard next >= 0 else { throw ContentDraftIssue.storageUnavailable }
            Darwin.close(parent); parent = next
        }
        let created = mkdirat(parent, leaf, mode_t(0o700)) == 0
        guard created || errno == EEXIST else { throw ContentDraftIssue.storageUnavailable }
        let fd = openat(parent, leaf, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw ContentDraftIssue.storageUnavailable }
        do {
            var info = stat()
            guard fstat(fd, &info) == 0, info.st_uid == geteuid(), info.st_mode & 0o077 == 0 else { throw ContentDraftIssue.storageUnavailable }
            #if os(iOS)
            if created { guard fcntl(fd, F_SETPROTECTIONCLASS, Self.completeProtectionClass) == 0 else { throw ContentDraftIssue.storageUnavailable } }
            guard fcntl(fd, F_GETPROTECTIONCLASS) == Self.completeProtectionClass else { throw ContentDraftIssue.storageUnavailable }
            #endif
            guard fsync(parent) == 0, fsync(fd) == 0, fcntl(fd, F_FULLFSYNC) == 0 else { throw ContentDraftIssue.storageUnavailable }
            return fd
        } catch { Darwin.close(fd); throw error }
    }
    private func valid(_ name: String) throws {
        guard UUID(uuidString: name)?.uuidString == name else { throw ContentDraftIssue.storageUnavailable }
    }
    private func regular(_ fd: Int32, limit: Int) throws -> Int {
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
              info.st_uid == geteuid(), info.st_nlink == 1, info.st_mode & 0o077 == 0,
              info.st_size >= 0, info.st_size <= Int64(limit) else { throw ContentDraftIssue.storageUnavailable }
        #if os(iOS)
        guard fcntl(fd, F_GETPROTECTIONCLASS) == Self.completeProtectionClass else { throw ContentDraftIssue.storageUnavailable }
        #endif
        return Int(info.st_size)
    }
    private func durable(_ fd: Int32, directory: Int32) throws {
        // No successful return on a failed barrier. F_FULLFSYNC additionally requests device flush.
        guard fsync(fd) == 0, fsync(directory) == 0, fcntl(fd, F_FULLFSYNC) == 0 else { throw ContentDraftIssue.storageUnavailable }
    }
    private func presenceName(_ slot: String) throws -> String {
        guard slot.utf8.count == 64, slot.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { throw ContentDraftIssue.storageUnavailable }
        return slot + ".presence"
    }
    func hasPresence(slot: String) throws -> Bool {
        let name = try presenceName(slot), dir = try directory(); defer { Darwin.close(dir) }
        let fd = openat(dir, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        if fd < 0 && errno == ENOENT { return false }
        guard fd >= 0 else { throw ContentDraftIssue.storageUnavailable }; defer { Darwin.close(fd) }
        guard try regular(fd, limit: 0) == 0 else { throw ContentDraftIssue.storageUnavailable }
        try durable(fd, directory: dir); return true
    }
    func createPresence(slot: String) throws -> Bool {
        let name = try presenceName(slot), dir = try directory(); defer { Darwin.close(dir) }
        let fd = openat(dir, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        if fd < 0 && errno == EEXIST { return false }
        guard fd >= 0 else { throw ContentDraftIssue.storageUnavailable }; defer { Darwin.close(fd) }
        #if os(iOS)
        guard fcntl(fd, F_SETPROTECTIONCLASS, Self.completeProtectionClass) == 0 else { throw ContentDraftIssue.storageUnavailable }
        #endif
        guard try regular(fd, limit: 0) == 0 else { throw ContentDraftIssue.storageUnavailable }
        try durable(fd, directory: dir); return true
    }
    func insert(name: String, bytes: Data) throws {
        try valid(name)
        guard bytes.count <= 4_194_304 else { throw ContentDraftIssue.storageUnavailable }
        let dir = try directory(); defer { Darwin.close(dir) }
        let fd = openat(dir, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        guard fd >= 0 else { throw ContentDraftIssue.storageUnavailable }; defer { Darwin.close(fd) }
        #if os(iOS)
        guard fcntl(fd, F_SETPROTECTIONCLASS, Self.completeProtectionClass) == 0 else { throw ContentDraftIssue.storageUnavailable }
        #endif
        _ = try regular(fd, limit: 4_194_304)
        try bytes.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(fd, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw ContentDraftIssue.storageUnavailable }; offset += count
            }
        }
        try durable(fd, directory: dir)
    }
    func readDurably(name: String, limit: Int) throws -> Data {
        try valid(name)
        guard limit > 0, limit <= 4_194_304 else { throw ContentDraftIssue.storageUnavailable }
        let dir = try directory(); defer { Darwin.close(dir) }
        let fd = openat(dir, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw ContentDraftIssue.storageUnavailable }; defer { Darwin.close(fd) }
        let size = try regular(fd, limit: limit)
        var data = Data(count: size)
        try data.withUnsafeMutableBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.read(fd, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw ContentDraftIssue.storageUnavailable }; offset += count
            }
        }
        try durable(fd, directory: dir); return data
    }
    func removeDurably(name: String) throws {
        try valid(name)
        let dir = try directory(); defer { Darwin.close(dir) }
        let result = unlinkat(dir, name, 0)
        guard result == 0 || (result == -1 && errno == ENOENT), fsync(dir) == 0, fcntl(dir, F_FULLFSYNC) == 0 else { throw ContentDraftIssue.storageUnavailable }
    }
}

#endif
