import XCTest
import Security
import Darwin
@testable import Questify

#if targetEnvironment(simulator)
/// Opt-in Apple execution only: unique synthetic service/key and temporary ciphertext directory.
/// No real account, user Keychain namespace, backend, or device lock manipulation.
@MainActor final class ContentDraftSystemStorageTests: XCTestCase {
    // This additive probe mirrors the adapter prerequisites without changing its failure policy.
    // Fixed stage labels and numeric errno only; do not log resolved container paths or data.
    func testSyntheticFilesystemPrerequisitesReportNumericStage() {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("questify-storage-probe-" + UUID().uuidString, isDirectory: true)
        guard prerequisite(root.isFileURL && root.path != "/" && root.path == root.standardizedFileURL.path,
                           stage: "path-shape", code: 0) else { return }
        let components = root.pathComponents.filter { $0 != "/" }
        guard let leaf = components.last,
              prerequisite(!components.contains("..") && !components.contains("."), stage: "components", code: 0) else { return }
        var parent = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard prerequisite(parent >= 0, stage: "open-root", code: errno) else { return }
        defer { Darwin.close(parent) }
        for (index, component) in components.dropLast().enumerated() {
            let next = openat(parent, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard prerequisite(next >= 0, stage: "open-ancestor-\(index)", code: errno) else { return }
            Darwin.close(parent); parent = next
        }
        let created = mkdirat(parent, leaf, mode_t(0o700))
        guard prerequisite(created == 0, stage: "mkdir-leaf", code: errno) else { return }
        // Only our successful exclusive, random leaf creation authorizes cleanup.
        defer {
            let removed = unlinkat(parent, leaf, AT_REMOVEDIR)
            _ = prerequisite(removed == 0, stage: "remove-leaf", code: errno)
        }
        let directory = openat(parent, leaf, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard prerequisite(directory >= 0, stage: "open-leaf", code: errno) else { return }
        defer { Darwin.close(directory) }
        var info = stat()
        let inspected = fstat(directory, &info)
        guard prerequisite(inspected == 0, stage: "stat-leaf", code: errno),
              prerequisite(info.st_uid == geteuid() && info.st_mode & 0o077 == 0, stage: "owner-mode", code: 0) else { return }
        let protected = fcntl(directory, F_SETPROTECTIONCLASS, Int32(1))
        guard prerequisite(protected == 0, stage: "set-directory-class-a", code: errno) else { return }
        let protection = fcntl(directory, F_GETPROTECTIONCLASS)
        guard prerequisite(protection == 1, stage: "get-directory-class-a", code: protection == -1 ? errno : 0, result: protection) else { return }
        let parentSynced = fsync(parent)
        guard prerequisite(parentSynced == 0, stage: "fsync-parent", code: errno) else { return }
        let directorySynced = fsync(directory)
        guard prerequisite(directorySynced == 0, stage: "fsync-directory", code: errno) else { return }
        let directoryFlushed = fcntl(directory, F_FULLFSYNC)
        guard prerequisite(directoryFlushed == 0, stage: "fullfsync-directory", code: errno) else { return }
        let file = openat(directory, "synthetic-probe", O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        guard prerequisite(file >= 0, stage: "create-file", code: errno) else { return }
        defer {
            Darwin.close(file)
            let removed = unlinkat(directory, "synthetic-probe", 0)
            _ = prerequisite(removed == 0, stage: "remove-file", code: errno)
        }
        let fileProtected = fcntl(file, F_SETPROTECTIONCLASS, Int32(1))
        guard prerequisite(fileProtected == 0, stage: "set-file-class-a", code: errno) else { return }
        let fileProtection = fcntl(file, F_GETPROTECTIONCLASS)
        guard prerequisite(fileProtection == 1, stage: "get-file-class-a", code: fileProtection == -1 ? errno : 0, result: fileProtection) else { return }
        let fileSynced = fsync(file)
        guard prerequisite(fileSynced == 0, stage: "fsync-file", code: errno) else { return }
        let fileFlushed = fcntl(file, F_FULLFSYNC)
        _ = prerequisite(fileFlushed == 0, stage: "fullfsync-file", code: errno)
    }
    private func prerequisite(_ satisfied: Bool, stage: String, code: Int32, result: Int32 = 0,
                              file: StaticString = #filePath, line: UInt = #line) -> Bool {
        XCTAssertTrue(satisfied, "Synthetic filesystem stage=\(stage) errno=\(code) result=\(result)", file: file, line: line)
        return satisfied
    }
    func testRealGenerationCASAndConditionalDelete() async throws {
        let service = "questify.tests.content-draft." + UUID().uuidString, slot = UUID().uuidString
        let store = ContentDraftSystemAnchors(service: service)
        let first = ContentDraftAnchorItem(bytes: Data("synthetic first".utf8), tag: Data(repeating: 1, count: 32))
        let second = ContentDraftAnchorItem(bytes: Data("synthetic second".utf8), tag: Data(repeating: 2, count: 32))
        let added = try await store.insert(slot: slot, item: first)
        XCTAssertTrue(added); guard added else { return }
        defer {
            let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                kSecAttrAccount as String: slot, kSecAttrSynchronizable as String: false, kSecUseDataProtectionKeychain as String: true]
            let result = SecItemDelete(query as CFDictionary)
            XCTAssertTrue(result == errSecSuccess || result == errSecItemNotFound)
        }
        let duplicate = try await store.insert(slot: slot, item: second); XCTAssertFalse(duplicate)
        let read = try await store.read(slot: slot); XCTAssertEqual(read, first) // also verifies protection attributes
        let wrong = try await store.exchange(slot: slot, matchingTag: second.tag, item: first); XCTAssertFalse(wrong)
        let changed = try await store.exchange(slot: slot, matchingTag: first.tag, item: second); XCTAssertTrue(changed)
        let stale = try await store.remove(slot: slot, matchingTag: first.tag); XCTAssertFalse(stale)
        let kept = try await store.read(slot: slot); XCTAssertEqual(kept, second)
        let removed = try await store.remove(slot: slot, matchingTag: second.tag); XCTAssertTrue(removed)
    }
    func testRealExclusiveCiphertextFileBoundedReadAndCleanup() async throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("questify-draft-test-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ContentDraftSystemCiphertexts(root: root), name = UUID().uuidString
        let bytes = Data(repeating: 0xA7, count: 524_288) // synthetic ciphertext-shaped bytes only
        try await store.insert(name: name, bytes: bytes)
        do { try await store.insert(name: name, bytes: Data([0])); XCTFail("Expected exclusive-create failure") } catch {}
        let reopened = ContentDraftSystemCiphertexts(root: root)
        let restored = try await reopened.readDurably(name: name, limit: 4_194_304); XCTAssertEqual(restored, bytes)
        do { _ = try await reopened.readDurably(name: name, limit: 8_192); XCTFail("Expected bounded-read failure") } catch {}
        let attributes = try FileManager.default.attributesOfItem(atPath: root.appendingPathComponent(name).path)
        XCTAssertEqual(attributes[.posixPermissions] as? NSNumber, NSNumber(value: 0o600))
        XCTAssertEqual(attributes[.protectionKey] as? String, FileProtectionType.complete.rawValue)
        try await reopened.removeDurably(name: name)
        try await reopened.removeDurably(name: name)
    }
    func testRealPresenceMarkerIsExclusivePermanentAndEmpty() async throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("questify-draft-marker-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ContentDraftSystemCiphertexts(root: root), slot = String(repeating: "a", count: 64)
        let absent = try await store.hasPresence(slot: slot); XCTAssertFalse(absent)
        let first = try await store.createPresence(slot: slot), second = try await store.createPresence(slot: slot)
        XCTAssertTrue(first); XCTAssertFalse(second)
        let reopened = ContentDraftSystemCiphertexts(root: root)
        let present = try await reopened.hasPresence(slot: slot); XCTAssertTrue(present)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(slot + ".presence")).count, 0)
    }
    func testRealSymlinkAncestorIsRejectedWithoutTouchingTarget() async throws {
        let base = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("questify-draft-links-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: base) }
        let outside = base.appendingPathComponent("outside"), link = base.appendingPathComponent("link")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        let store = ContentDraftSystemCiphertexts(root: link.appendingPathComponent("journal"))
        do { _ = try await store.createPresence(slot: String(repeating: "a", count: 64)); XCTFail("Expected no-follow failure") } catch {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: outside.appendingPathComponent("journal").path))
    }
    func testRealWeakExistingDirectoryIsRejectedWithoutPermissionRepair() async throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("questify-draft-mode-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
        let store = ContentDraftSystemCiphertexts(root: root)
        do { _ = try await store.createPresence(slot: String(repeating: "a", count: 64)); XCTFail("Expected owner-only directory requirement") } catch {}
        let attributes = try FileManager.default.attributesOfItem(atPath: root.path)
        XCTAssertEqual(attributes[.posixPermissions] as? NSNumber, NSNumber(value: 0o755))
    }

}
#endif
