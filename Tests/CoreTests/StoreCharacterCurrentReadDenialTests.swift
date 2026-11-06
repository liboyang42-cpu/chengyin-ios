import Foundation
import XCTest
@testable import QuestifyCore

@MainActor private final class CurrentCharacterReader: StoreCharacterReading {
    var scope = UUID(), isAuthenticated = true
    var deniedInitially = false
    var profileError: Error?
    var duringProfile: (() -> Void)?
    var profileReads = 0
    func access() async throws -> MerchantOperationsAccess {
        if deniedInitially { throw MerchantOperationsFailure.accessDenied }
        return try JSONDecoder().decode(MerchantOperationsAccess.self, from: Data(#"{"active":true,"merchant":{"id":31},"roleCode":"MERCHANT_OWNER","permissions":["merchant:profile:write"]}"#.utf8))
    }
    func profile() async throws -> StoreCharacterProfile {
        profileReads += 1; duringProfile?()
        if let profileError { throw profileError }
        return StoreCharacterProfile()
    }
    func voiceStatus() async throws -> StoreCharacterVoiceState { throw StoreCharacterFailure.notConfigured }
    func mapPoint() async throws -> StoreCharacterMapPointState { throw StoreCharacterFailure.notConfigured }
}

@MainActor final class StoreCharacterCurrentReadDenialTests: XCTestCase {
    func testCurrentProfileDenialIsDistinctFromInitialAdmissionAndCanBeExplicitlyReread() async {
        let reader = CurrentCharacterReader()
        let owner = StoreCharacterCoordinator(reader: reader)
        reader.profileError = MerchantOperationsFailure.accessDenied
        await owner.load()
        XCTAssertEqual(owner.phase, .currentReadDenied(.noViewPermission))
        XCTAssertEqual(reader.profileReads, 1)
        reader.profileError = nil
        await owner.load()
        XCTAssertEqual(owner.phase, .ready)
        XCTAssertEqual(reader.profileReads, 2)
    }
    func testInitialRefusalRetainsOriginalDeniedStateAndDoesNotReadProfile() async {
        let reader = CurrentCharacterReader(); reader.deniedInitially = true
        let owner = StoreCharacterCoordinator(reader: reader)
        await owner.load()
        XCTAssertEqual(owner.phase, .denied(.noViewPermission)); XCTAssertEqual(reader.profileReads, 0)
    }
    func testUnauthorizedRemainsLoginAndOrdinaryFailureRemainsFailed() async {
        let reader = CurrentCharacterReader()
        let owner = StoreCharacterCoordinator(reader: reader)
        reader.profileError = APIError.unauthorized
        await owner.load(); XCTAssertEqual(owner.phase, .login)
        reader.profileError = StoreCharacterFailure.malformed
        await owner.load(); XCTAssertEqual(owner.phase, .failed(message: nil))
    }
    func testStoreCharacterDenialUsesExistingClassifier() async {
        let reader = CurrentCharacterReader(); reader.profileError = StoreCharacterFailure.accessDenied
        let owner = StoreCharacterCoordinator(reader: reader)
        await owner.load(); XCTAssertEqual(owner.phase, .currentReadDenied(.noViewPermission))
    }
    func testOldScopeDenialCannotPublishIntoNewIdentity() async {
        let reader = CurrentCharacterReader(); reader.profileError = MerchantOperationsFailure.accessDenied
        reader.duringProfile = { reader.scope = UUID() }
        let owner = StoreCharacterCoordinator(reader: reader)
        await owner.load(); XCTAssertEqual(owner.phase, .loading)
    }
    func testInvalidatedOwnerIgnoresLateDenial() async {
        let reader = CurrentCharacterReader(); reader.profileError = MerchantOperationsFailure.accessDenied
        let owner = StoreCharacterCoordinator(reader: reader)
        reader.duringProfile = { owner.invalidate() }
        await owner.load(); XCTAssertEqual(owner.phase, .loading)
    }
}
