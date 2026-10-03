import XCTest
import Security
@testable import Questify

#if targetEnvironment(simulator)
/// Real Security API checks, confined to unique synthetic simulator-only keys.
/// These do not simulate locking the device or validate physical-device access groups.
@MainActor final class PrivateHomeSystemKeychainTests: XCTestCase {
    private func namespace() -> (service: String, key: String) {
        ("questify.tests.private-home." + UUID().uuidString, "synthetic-" + UUID().uuidString)
    }
    private func query(service: String, key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: key,
         kSecAttrSynchronizable as String: false, kSecUseDataProtectionKeychain as String: true]
    }
    private func cleanup(service: String, key: String, file: StaticString = #filePath, line: UInt = #line) {
        // Caller invokes this only after a successful insert of its exact newly generated key.
        let status = SecItemDelete(query(service: service, key: key) as CFDictionary)
        XCTAssertTrue(status == errSecSuccess || status == errSecItemNotFound,
                      "Synthetic-key cleanup failed with OSStatus \(status)", file: file, line: line)
    }
    private func item(_ marker: UInt8) -> PrivateHomeKeychainItem {
        .init(bytes: Data("synthetic fixture bytes".utf8), tag: Data(repeating: marker, count: 32))
    }
    func testRealInsertDuplicateReadAndProtectionAttributes() async throws {
        let identity = namespace(), expected = item(0x11)
        let vault = PrivateHomeSystemKeychain(service: identity.service)
        let inserted = try await vault.insert(key: identity.key, item: expected)
        XCTAssertTrue(inserted)
        guard inserted else { return }
        defer { cleanup(service: identity.service, key: identity.key) }
        let duplicate = try await vault.insert(key: identity.key,
            item: .init(bytes: Data("different synthetic bytes".utf8), tag: Data(repeating: 0x22, count: 32)))
        XCTAssertFalse(duplicate, "An existing value must never be overwritten")
        let result = try await vault.read(key: identity.key)
        let restored = try XCTUnwrap(result)
        XCTAssertEqual(restored.bytes, expected.bytes)
        XCTAssertEqual(restored.tag, expected.tag)

        var attributesQuery = query(service: identity.service, key: identity.key)
        attributesQuery[kSecReturnAttributes as String] = true
        attributesQuery[kSecReturnData as String] = true
        attributesQuery[kSecMatchLimit as String] = kSecMatchLimitOne
        attributesQuery[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        var raw: CFTypeRef?
        let status = SecItemCopyMatching(attributesQuery as CFDictionary, &raw)
        XCTAssertEqual(status, errSecSuccess)
        let attributes = try XCTUnwrap(raw as? [String: Any])
        XCTAssertEqual(attributes[kSecValueData as String] as? Data, expected.bytes)
        XCTAssertEqual(attributes[kSecAttrGeneric as String] as? Data, expected.tag)
        XCTAssertEqual(attributes[kSecAttrAccessible as String] as? String,
                       kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
        XCTAssertEqual((attributes[kSecAttrSynchronizable as String] as? NSNumber)?.boolValue, false)
    }
    func testRealConditionalDeletePreservesWrongTagAndDeletesMatchingTag() async throws {
        let identity = namespace(), expected = item(0x33)
        let vault = PrivateHomeSystemKeychain(service: identity.service)
        let inserted = try await vault.insert(key: identity.key, item: expected)
        XCTAssertTrue(inserted)
        guard inserted else { return }
        defer { cleanup(service: identity.service, key: identity.key) }
        let wrong = try await vault.remove(key: identity.key, matchingTag: Data(repeating: 0x44, count: 32))
        XCTAssertFalse(wrong, "A nonmatching generation must not delete the record")
        let afterWrong = try await vault.read(key: identity.key)
        XCTAssertEqual(afterWrong?.bytes, expected.bytes)
        XCTAssertEqual(afterWrong?.tag, expected.tag)
        let matching = try await vault.remove(key: identity.key, matchingTag: expected.tag)
        XCTAssertTrue(matching)
        let afterMatching = try await vault.read(key: identity.key)
        XCTAssertNil(afterMatching)
    }
    func testRealStaleTagCannotDeleteReplacementAtTheSameKey() async throws {
        let identity = namespace(), first = item(0x55), replacement = item(0x66)
        let writer = PrivateHomeSystemKeychain(service: identity.service)
        let other = PrivateHomeSystemKeychain(service: identity.service)
        let inserted = try await writer.insert(key: identity.key, item: first)
        XCTAssertTrue(inserted)
        guard inserted else { return }
        defer { cleanup(service: identity.service, key: identity.key) }
        let captured = try await writer.read(key: identity.key)
        let removed = try await other.remove(key: identity.key, matchingTag: first.tag)
        XCTAssertTrue(removed)
        let replaced = try await other.insert(key: identity.key, item: replacement)
        XCTAssertTrue(replaced)
        let staleDelete = try await writer.remove(key: identity.key, matchingTag: try XCTUnwrap(captured).tag)
        XCTAssertFalse(staleDelete)
        let remaining = try await other.read(key: identity.key)
        XCTAssertEqual(remaining?.tag, replacement.tag)
        XCTAssertEqual(remaining?.bytes, replacement.bytes)
    }
}
#endif
