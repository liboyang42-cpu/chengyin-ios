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
    // Independent controls: a directory-class failure must not hide regular-file evidence.
    // These tests keep every original production and test Class A requirement unchanged.
    func testSyntheticRegularFileClassAIndependentControl() throws {
        try withSyntheticProtectionDirectory { directory, _ in
            let fd = openat(directory, "syscall-control", O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
            guard prerequisite(fd >= 0, stage: "control-create-file", code: fd < 0 ? errno : 0) else { throw ProtectionProbeFailure.failed }
            defer {
                Darwin.close(fd)
                let removed = unlinkat(directory, "syscall-control", 0)
                _ = prerequisite(removed == 0, stage: "control-remove-file", code: removed < 0 ? errno : 0)
            }
            var info = stat()
            let inspected = fstat(fd, &info)
            guard prerequisite(inspected == 0, stage: "control-stat-file", code: inspected < 0 ? errno : 0),
                  prerequisite((info.st_mode & S_IFMT) == S_IFREG && info.st_uid == geteuid() &&
                               info.st_nlink == 1 && info.st_mode & 0o077 == 0,
                               stage: "control-file-identity", code: 0) else { throw ProtectionProbeFailure.failed }
            let setResult = fcntl(fd, F_SETPROTECTIONCLASS, Int32(1))
            let setError = setResult < 0 ? errno : 0
            reportProtectionControl(stage: "regular-set-class-a", result: setResult, code: setError, expected: 0)
            let getResult = fcntl(fd, F_GETPROTECTIONCLASS)
            let getError = getResult < 0 ? errno : 0
            reportProtectionControl(stage: "regular-get-class-a", result: getResult, code: getError, expected: 1)
            var byte: UInt8 = 0xA7
            let written = withUnsafePointer(to: &byte) { Darwin.write(fd, $0, 1) }
            let writeError = written < 0 ? errno : 0
            reportProtectionControl(stage: "regular-write", result: Int32(written), code: writeError, expected: 1)
            let afterWrite = fcntl(fd, F_GETPROTECTIONCLASS)
            let afterWriteError = afterWrite < 0 ? errno : 0
            reportProtectionControl(stage: "regular-get-class-a-after-write", result: afterWrite, code: afterWriteError, expected: 1)
            let synced = fsync(fd)
            reportProtectionControl(stage: "regular-fsync", result: synced, code: synced < 0 ? errno : 0, expected: 0)
        }
    }
    func testSyntheticFoundationClassAIndependentControl() throws {
        try withSyntheticProtectionDirectory { directory, root in
            // Only a new, owned 0700 UUID directory is used by this path-based API control.
            // No production adapter uses this path-based creation route.
            let url = root.appendingPathComponent("foundation-control")
            defer {
                let removed = unlinkat(directory, "foundation-control", 0)
                let removeError = removed < 0 ? errno : 0
                _ = prerequisite(removed == 0 || removeError == ENOENT, stage: "foundation-remove-file", code: removeError)
            }
            do {
                try Data([0xA7]).write(to: url, options: [.completeFileProtection, .withoutOverwriting])
                print("Synthetic protection control stage=foundation-write result=0")
            } catch {
                print("Synthetic protection control stage=foundation-write result=-1 api-code=\((error as NSError).code)")
                XCTFail("Synthetic protection control stage=foundation-write")
                throw ProtectionProbeFailure.failed
            }
            let fd = openat(directory, "foundation-control", O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
            guard prerequisite(fd >= 0, stage: "foundation-open-file", code: fd < 0 ? errno : 0) else { throw ProtectionProbeFailure.failed }
            defer { Darwin.close(fd) }
            var info = stat()
            let inspected = fstat(fd, &info)
            guard prerequisite(inspected == 0, stage: "foundation-stat-file", code: inspected < 0 ? errno : 0),
                  prerequisite((info.st_mode & S_IFMT) == S_IFREG && info.st_uid == geteuid() && info.st_nlink == 1,
                               stage: "foundation-file-identity", code: 0) else { throw ProtectionProbeFailure.failed }
            let getResult = fcntl(fd, F_GETPROTECTIONCLASS)
            let getError = getResult < 0 ? errno : 0
            reportProtectionControl(stage: "foundation-get-class-a", result: getResult, code: getError, expected: 1)
            let attributes: [FileAttributeKey: Any]
            do { attributes = try FileManager.default.attributesOfItem(atPath: url.path) }
            catch {
                print("Synthetic protection control stage=foundation-attributes result=-1 api-code=\((error as NSError).code)")
                XCTFail("Synthetic protection control stage=foundation-attributes")
                throw ProtectionProbeFailure.failed
            }
            // Log only a numeric comparison, never paths, payloads, or attribute dictionaries.
            let complete: Int32 = (attributes[.protectionKey] as? String) == FileProtectionType.complete.rawValue ? 1 : 0
            reportProtectionControl(stage: "foundation-attribute-class-a", result: complete, code: 0, expected: 1)
        }
    }
    private enum ProtectionProbeFailure: Error { case failed }
    private func reportProtectionControl(stage: String, result: Int32, code: Int32, expected: Int32) {
        print("Synthetic protection control stage=\(stage) result=\(result) errno=\(code)")
        XCTAssertEqual(result, expected, "Synthetic protection control stage=\(stage) errno=\(code)")
    }
    private func withSyntheticProtectionDirectory(_ body: (Int32, URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("questify-class-a-control-" + UUID().uuidString, isDirectory: true)
        let components = root.pathComponents.filter { $0 != "/" }
        guard let leaf = components.last,
              prerequisite(root.isFileURL && root.path != "/" && root.path == root.standardizedFileURL.path &&
                           !components.contains("..") && !components.contains("."), stage: "control-path-shape", code: 0)
        else { throw ProtectionProbeFailure.failed }
        var parent = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard prerequisite(parent >= 0, stage: "control-open-root", code: parent < 0 ? errno : 0) else { throw ProtectionProbeFailure.failed }
        defer { Darwin.close(parent) }
        for component in components.dropLast() {
            let next = openat(parent, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard prerequisite(next >= 0, stage: "control-open-ancestor", code: next < 0 ? errno : 0) else { throw ProtectionProbeFailure.failed }
            Darwin.close(parent); parent = next
        }
        let created = mkdirat(parent, leaf, mode_t(0o700))
        guard prerequisite(created == 0, stage: "control-mkdir", code: created < 0 ? errno : 0) else { throw ProtectionProbeFailure.failed }
        defer {
            let removed = unlinkat(parent, leaf, AT_REMOVEDIR)
            _ = prerequisite(removed == 0, stage: "control-remove-directory", code: removed < 0 ? errno : 0)
        }
        let directory = openat(parent, leaf, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard prerequisite(directory >= 0, stage: "control-open-directory", code: directory < 0 ? errno : 0) else { throw ProtectionProbeFailure.failed }
        defer { Darwin.close(directory) }
        var info = stat()
        let inspected = fstat(directory, &info)
        guard prerequisite(inspected == 0, stage: "control-stat-directory", code: inspected < 0 ? errno : 0),
              prerequisite(info.st_uid == geteuid() && info.st_mode & 0o077 == 0,
                           stage: "control-directory-owner-mode", code: 0) else { throw ProtectionProbeFailure.failed }
        try body(directory, root)
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
