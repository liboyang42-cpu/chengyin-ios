import XCTest
import CryptoKit
@testable import Questify

@MainActor final class NativeEnrollmentAppTests: XCTestCase {
    func testShippedEnrollmentPolicyHasNoPermissionToCreateOrRevoke() {
        let policy = NativeEnrollmentAcceptance()
        XCTAssertFalse(policy.enabled); XCTAssertFalse(policy.keyCreationEnabled); XCTAssertFalse(policy.revocationEnabled)
        XCTAssertTrue(policy.requiredPaths.isEmpty); XCTAssertNil(NativePlatformAcceptance().enrollment)
    }
    func testDormantDeviceAdapterNeverCreatesOrAttestsAKey() async {
        let provider = AppleEnrollmentDeviceProvider()
        XCTAssertFalse(provider.supported)
        do { _ = try await provider.generateKey(); XCTFail() } catch { XCTAssertEqual(error as? NativeEnrollmentIssue, .unsupported) }
        do { _ = try await provider.attest(key: Data(repeating: 1, count: 32).base64EncodedString(), challengeBytes: Data(0..<32)); XCTFail() }
        catch { XCTAssertEqual(error as? NativeEnrollmentIssue, .unsupported) }
    }
    func testBackendOwnedNonceVectorHashesDecodedBytesExactlyOnce() throws {
        let nonce = try XCTUnwrap(Data(base64Encoded: "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8="))
        let hash = try AppleEnrollmentDeviceProvider.clientDataHash(challengeBytes: nonce)
        XCTAssertEqual(hash.map { String(format: "%02x", $0) }.joined(), "630dcd2966c4336691125448bbb25b4ff412a49c732db2c8abc1b8581bd710dd")
        XCTAssertNotEqual(hash, nonce)
        XCTAssertNotEqual(hash, Data(SHA256.hash(data: Data(nonce.base64EncodedString().utf8))))
        XCTAssertThrowsError(try AppleEnrollmentDeviceProvider.clientDataHash(challengeBytes: Data(repeating: 0, count: 31)))
    }
}
